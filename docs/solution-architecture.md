# Org Health Monitor — Solution Architecture

## Overview

The Org Health Monitor is an automated Salesforce audit framework that scans an org across **6 health dimensions**, scores each dimension independently, and produces a single weighted composite score (0–100) with a letter grade. Every scan generates structured findings with descriptions and remediation recommendations.

Scans run asynchronously via chained Queueable Apex jobs — one job per module — so they never block the UI and can safely issue Tooling API callouts alongside standard SOQL.

---

## Composite Scoring Model

### Module Weights

Each module contributes a configurable percentage to the overall score. Default weights (stored in `OrgHealthModuleConfig__mdt`) are:

| Module | Weight |
|---|---|
| Security | 30% |
| Automation | 20% |
| Code Quality | 20% |
| Metadata | 10% |
| Data Quality | 10% |
| Governor Limits | 10% |
| **Total** | **100%** |

### Module Score Calculation

Each module starts with a perfect score of **100**. Every finding deducts points based on severity (configured in `OrgHealthSeverityConfig__mdt`):

| Severity | Score Deduction | Meaning |
|---|---|---|
| Critical | 25 pts | Immediate risk — security bypass, data exposure |
| High | 15 pts | Significant technical debt or deployment blocker |
| Medium | 8 pts | Notable risk requiring planned remediation |
| Low | 3 pts | Best-practice violation; low immediate impact |
| Info | 1 pt | Informational — no direct risk |

Module score is floored at 0. Multiple findings of the same severity stack (e.g., 5 Critical findings = 125 pts deducted → score capped at 0).

### Composite Score & Grade

```
Composite Score = Σ (Module Score × Module Weight / 100)
```

| Grade | Score Range | Meaning |
|---|---|---|
| A | 90 – 100 | Excellent — org is well-maintained |
| B | 75 – 89 | Good — minor issues present |
| C | 60 – 74 | Fair — meaningful risks to address |
| D | 40 – 59 | Poor — significant problems requiring attention |
| F | 0 – 39 | Critical — immediate remediation needed |

---

## Health Check Modules

### 1. Security (Weight: 30%)

The highest-weighted module. Checks for permission misconfigurations that could expose data or allow unauthorised access.

#### 1.1 Modify All / View All Data on Profiles

**What is checked:** Queries all standard-user Profiles (excluding System Administrator) for the `PermissionsModifyAllData` or `PermissionsViewAllData` permission. Also checks all custom Permission Sets for `PermissionsModifyAllData`.

**Why it matters:** These permissions bypass every object, record, and field-level security rule in the org. Any user on such a profile or permission set can read or overwrite every record regardless of sharing configuration.

**Severity:**
- `Critical` — Profile or Permission Set has Modify All Data
- `High` — Profile has View All Data (read-only bypass)

#### 1.2 FLS / Sharing Rule Bypass (ObjectPermissions)

**What is checked:** Identifies Profiles and Permission Sets with `PermissionsViewAllRecords = true` or `PermissionsModifyAllRecords = true` on core CRM objects: Account, Contact, Lead, Opportunity, Case. Flags when more than 3 profiles bypass sharing on a single object (a small number of admin/integration profiles is expected).

**Why it matters:** ViewAllRecords/ModifyAllRecords circumvents the role hierarchy and sharing rules for that object, even when those rules are otherwise correctly configured.

**Severity:** `High`

#### 1.3 Guest User Access to Custom Objects

**What is checked:** Finds all active Guest users (unauthenticated Experience Cloud visitors) and inspects their Profile's ObjectPermissions for read access to any custom object (`%__c`). Separately flags objects where the guest profile also has Create or Edit access.

**Why it matters:** Guest users represent the highest-risk access point — they require no authentication. Exposing custom objects to guest profiles without deliberate intent is a common misconfiguration.

**Severity:** `Critical`

#### 1.4 Login IP Range Restrictions

**What is checked:** Queries `ProfileIpAddressRange` (Tooling API). If no records exist, no profiles have Login IP Ranges configured.

**Why it matters:** Without IP restrictions, valid credentials can authenticate from anywhere in the world. This is particularly important for high-privilege profiles such as System Administrator.

**Severity:** `Medium`

---

### 2. Automation (Weight: 20%)

Audits the health and hygiene of declarative and programmatic automation.

#### 2.1 Inactive Flows

**What is checked:** Queries `FlowDefinitionView` for Flow, AutoLaunchedFlow, CustomEvent, and ContactRequestFlow definitions where `IsActive = false` — flows that exist in the org but have no active version.

**Why it matters:** Inactive flows accumulate as tech debt. They slow deployments (every flow is compiled on deploy), confuse developers browsing the org, and can be accidentally reactivated with unintended consequences.

**Severity:** `Low`

#### 2.2 Multiple Triggers on the Same Object

**What is checked:** Queries `ApexTrigger` (Tooling API) for all active triggers, groups them by `TableEnumOrId` (the SObject they fire on), and flags any object with more than one active trigger.

**Why it matters:** Salesforce does not guarantee execution order when multiple triggers fire on the same DML event. This leads to unpredictable behaviour and makes debugging extremely difficult.

**Severity:** `Medium`

#### 2.3 Missing Duplicate Rules

**What is checked:** Queries `DuplicateRule` for active rules on Account, Contact, and Lead. Any of the three objects without an active rule generates a finding.

**Why it matters:** Without duplicate rules, users can create duplicate records unchecked. Duplicate data degrades CRM data quality, causes duplicate sends in marketing campaigns, and inflates record counts in reports.

**Severity:** `Medium` (one finding per unprotected object)

#### 2.4 Active Process Builders

**What is checked:** Queries `FlowDefinitionView` for active automations with `ProcessType = 'Workflow'` (Process Builder's internal type).

**Why it matters:** Salesforce has announced the retirement of Process Builder in favour of Record-Triggered Flows. Active Process Builders should be migrated proactively to avoid disruption when retirement takes effect.

**Severity:** `Medium`

---

### 3. Code Quality (Weight: 20%)

Inspects Apex code for test coverage, anti-patterns, and API version hygiene using the Tooling API.

#### 3.1 Test Coverage

**What is checked:** Queries `ApexCodeCoverageAggregate` for all classes and triggers with more than 10 lines. Separates results into:
- Zero coverage (no test lines executed at all)
- Below 75% coverage (Salesforce's production deployment threshold)

**Why it matters:** Zero-coverage code cannot be deployed to production. Below-threshold code is fragile — bugs can be introduced without automated detection.

**Severity:**
- `High` — zero test coverage
- `Medium` — below 75% coverage

#### 3.2 SOQL Inside Loops

**What is checked:** Fetches the body of up to 200 active Apex classes (capped at 100,000 characters per class to stay within heap limits). Performs a line-by-line heuristic scan: detects `for`/`while` loop blocks by tracking brace depth, then checks for `[SELECT`, `Database.query()`, or `Database.countQuery()` calls within the loop body.

**Why it matters:** Each SOQL query inside a loop consumes one of the 100 SOQL queries allowed per Apex transaction. With bulk data operations (triggers processing 200 records), a single SOQL-in-loop can exhaust the limit and throw an unhandled exception.

**Severity:** `High`

#### 3.3 Oversized Classes

**What is checked:** Queries `ApexClass` for active, non-namespaced classes where `LengthWithoutComments > 50,000` characters (approximately 1,000+ lines of code).

**Why it matters:** Classes of this size nearly always violate the Single Responsibility Principle. They are harder to review, slower to test, and create merge conflicts in team environments.

**Severity:** `Low`

#### 3.4 Code Documentation

**What is checked:** Fetches the body of up to 200 active, non-namespaced Apex classes (capped at 100,000 characters each). For each non-test class:
- Counts ApexDoc comment blocks (`/**`)
- Counts public and global method signatures (lines starting with `public`/`global` that contain parentheses, excluding class/interface/enum declarations)

Two findings are possible:
- **No documentation** — class contains zero `/**` blocks
- **Partial documentation** — class has fewer `/**` blocks than public methods (some methods undocumented)

**Why it matters:** Undocumented Apex code increases onboarding time, makes maintenance error-prone, and creates risk when the original author leaves. ApexDoc comments are also consumed by IDEs and code generation tools.

**Severity:**
- `Medium` — class has zero ApexDoc comments
- `Low` — class has fewer comments than public methods

#### 3.5 Deprecated API Versions

**What is checked:** Queries `ApexClass` for active, non-namespaced classes with `ApiVersion < 50.0` (older than Summer '20 / API v50).

**Why it matters:** Classes on old API versions may use deprecated platform behaviours, miss null-safe operator support (`??`), and exhibit inconsistent governor limit reporting. They accumulate risk with every Salesforce release.

**Severity:** `Medium`

---

### 4. Metadata (Weight: 10%)

Identifies stale or over-complex metadata that increases maintenance burden.

#### 4.1 Stale Custom Fields

**What is checked:** Queries `FieldDefinition` (Tooling API, scoped to custom entity IDs to satisfy the required `EntityDefinitionId` filter) for custom fields (`QualifiedApiName LIKE '%__c'`) with `LastModifiedDate` older than **2 years**. Groups by parent object and flags objects with 5 or more stale fields.

**Why it matters:** Stale fields may be unmaintained or entirely unused. They consume metadata API limits, clutter the object manager, and confuse developers inheriting the org.

**Severity:** `Low`

#### 4.2 Stale Custom Objects

**What is checked:** Queries `EntityDefinition` (Tooling API) for custom objects (`QualifiedApiName LIKE '%__c'`) with `LastModifiedDate` older than **3 years**. Generates a single finding when 3 or more such objects are found.

**Why it matters:** Objects not touched in 3 years are strong candidates for decommission. Legacy objects with residual data consume storage and create confusion about the active data model.

**Severity:** `Info`

#### 4.3 High Validation Rule Count

**What is checked:** Queries `ValidationRule` (Tooling API) for all active validation rules, groups by object, and flags objects with more than **25 active rules**.

**Why it matters:** High validation rule counts make data entry error-prone for users, slow DML operations (every rule is evaluated on every save), and create a significant maintenance burden when business requirements change.

**Severity:** `Low`

#### 4.4 Short TextArea Fields

**What is checked:** Queries `FieldDefinition` (Tooling API, scoped to custom entity IDs) for custom fields with `DataType = 'TextArea'` — the 255-character short text area type.

**Why it matters:** Short TextArea is a common mistake — developers often use it when they need a longer text field. When the data outgrows 255 characters, a costly field-type migration (with risk of data truncation) is required.

**Severity:** `Low`

---

### 5. Data Quality (Weight: 10%)

Checks the quality and freshness of business data using standard SOQL aggregates.

#### 5.1 Duplicate Accounts

**What is checked:** Aggregates Account records grouped by `Name` and counts groups with more than 3 records sharing the same name.

**Why it matters:** Duplicate accounts degrade CRM reliability. Sales reps work from incomplete pictures of the customer, and reporting counts are inflated.

**Severity:** `High` (if > 100 groups), `Medium` (if > 10 groups)

#### 5.2 Duplicate Contacts

**What is checked:** Aggregates Contact records grouped by `Email` (excluding null emails) and counts groups with more than 1 record sharing the same email address.

**Why it matters:** Duplicate contacts cause duplicate marketing sends (damaging unsubscribe compliance), split activity history, and incorrect contact counts in campaign reporting.

**Severity:** `High` (if > 100 groups), `Medium` (if > 10 groups)

#### 5.3 Blank Key Fields

**What is checked:** Calculates the blank rate for critical fields across core objects:

| Object | Fields Checked |
|---|---|
| Account | `Name`, `Phone`, `BillingCity` |
| Contact | `Email`, `Phone` |
| Lead | `Email`, `Company` |

A finding is raised when blank rate exceeds **30%** of records.

**Why it matters:** Blank key fields reduce the usefulness of the CRM for sales, marketing, and support. They indicate gaps in data entry governance or integration pipelines that aren't populating expected fields.

**Severity:** `Medium` (> 30% blank), `Low` (> 10% blank)

#### 5.4 Stale Open Records

**What is checked:**
- **Opportunities:** Counts open (non-closed) Opportunities with a `CloseDate` more than **180 days** in the past
- **Cases:** Counts open Cases with no activity in more than **90 days** (`LastModifiedDate`)

**Why it matters:** Stale open records indicate pipeline data that has not been maintained. Stale Opportunities skew forecast reports; stale Cases indicate unresolved customer issues or abandoned tickets that affect support SLA metrics.

**Severity:** `Medium`

---

### 6. Governor Limits (Weight: 10%)

Monitors org-level consumption of Salesforce platform limits using the `OrgLimits` API and Async Apex job queries.

#### 6.1 Data Storage

**What is checked:** Reads `OrgLimits.getMap().get('DataStorageMB')` to compare current data storage consumption against the org's allocated limit.

**Thresholds:**
- Warning at **80%** utilisation → `Medium`
- Critical at **95%** utilisation → `High`

**Why it matters:** When data storage is exhausted, all DML operations that create new records fail. This can bring business processes to a halt.

#### 6.2 Daily API Requests

**What is checked:** Reads `OrgLimits.getMap().get('DailyApiRequests')` to compare API call consumption against the org's 24-hour rolling limit.

**Thresholds:**
- Warning at **80%** utilisation → `Medium`
- Critical at **95%** utilisation → `High`

**Why it matters:** Exhausting the daily API limit blocks all external integrations (ETL pipelines, connected apps, middleware) for the remainder of the 24-hour window.

#### 6.3 Async Apex Job Backlog

**What is checked:** Counts `AsyncApexJob` records with `Status IN ('Queued', 'Processing')` (backlog size) and `Status = 'Failed'` with `CreatedDate = TODAY` (failures today).

**Thresholds:**
- Backlog ≥ 10 jobs → `Medium`
- Any failed jobs today → `Low`

**Why it matters:** A growing async job queue indicates the Apex Flex Queue is saturated. Failed jobs mean scheduled business logic (batch data processing, nightly syncs) did not execute.

#### 6.4 Daily Async Apex Executions

**What is checked:** Reads `OrgLimits.getMap().get('DailyAsyncApexExecutions')` to compare the number of async Apex executions (Queueable, Future, Batch) against the org's daily limit.

**Thresholds:**
- Warning at **80%** utilisation → `Medium`
- Critical at **95%** utilisation → `High`

**Why it matters:** Exhausting async execution limits prevents any new Queueable, `@future`, or Batch Apex from being enqueued, breaking any asynchronous automation for the rest of the day.

---

## Data Model Summary

```
HealthScan__c (one per scan run)
│   CompositeScore__c, Grade__c, Status__c, TriggerType__c
│   CriticalCount__c, HighCount__c (roll-ups from findings)
│
├── HealthModuleScore__c (one per module per scan)
│       Module__c, Score__c, Weight__c, WeightedContribution__c
│       CriticalCount__c, HighCount__c, MediumCount__c, ...
│
└── HealthFinding__c (one per issue found)
        Severity__c, Category__c, Title__c
        Description__c, Recommendation__c
        AffectedComponent__c, AffectedComponentType__c
        FindingKey__c (external ID for deduplication)
```

Weights are snapshotted from `OrgHealthModuleConfig__mdt` at scan time so historical scores remain reproducible even if weights are later reconfigured.

---

## Extending the Framework

To add a new health check dimension:

1. Create a class extending `OrgHealthBaseModule`
2. Implement `runChecks()` — call `addFinding()` for each issue detected
3. Register the module name in `OrgHealthModuleFactory` (`switch on moduleName`)
4. Add the module name to `OrgHealthConstants.MODULE_CHAIN`
5. Add a weight record to `OrgHealthModuleConfig__mdt` (ensure all weights still sum to 100)
6. Optionally add severity deduction records to `OrgHealthSeverityConfig__mdt`

No changes are needed to the orchestrator, base module, or dashboard — the chain and scoring engine adapt automatically.
