# Salesforce Org Health Monitor — Object Model

## Entity Relationships

```
HealthScan__c  (1)
    │
    ├──── HealthModuleScore__c  (6 per scan, Master-Detail)
    │            │
    │            └──── HealthFinding__c  (Lookup, optional)
    │
    └──── HealthFinding__c  (N per scan, Master-Detail)

OrgHealthModuleConfig__mdt   (6 seed records — module weights)
OrgHealthSeverityConfig__mdt (5 seed records — severity deductions)
```

`HealthFinding__c` has two relationships:
- **Master-Detail → `HealthScan__c`**: enforces ownership, enables roll-up summaries, cascade-deletes findings when the scan is deleted.
- **Lookup → `HealthModuleScore__c`**: optional link so a finding knows which module run produced it; allows querying all findings for a specific module score record.

---

## 1. `HealthScan__c`

Header record for a single org health scan run. One record is created when a scan starts and updated with the composite score when the last module finishes.

| Field API Name | Type | Precision / Length | Notes |
|---|---|---|---|
| `Name` | Auto Number | `HS-{00000}` | System name field |
| `Status__c` | Picklist | — | `In Progress` · `Complete` · `Failed` |
| `TriggerType__c` | Picklist | — | `Manual` · `Scheduled` · `API` |
| `CompositeScore__c` | Number | 4,1 | 0–100; written by `finaliseScan()` |
| `Grade__c` | Text | 2 | `A` / `B` / `C` / `D` / `F` |
| `ScanStartTime__c` | DateTime | — | Set at scan creation |
| `ScanEndTime__c` | DateTime | — | Set by `finaliseScan()` |
| `ScanDuration__c` | Formula (Number) | 18,0 | `(ScanEndTime__c − ScanStartTime__c) × 86400` seconds |
| `OrgId__c` | Text | 18 | `UserInfo.getOrganizationId()` |
| `OrgName__c` | Text | 255 | `UserInfo.getOrganizationName()` |
| `TriggeredBy__c` | Lookup (User) | — | `UserInfo.getUserId()` at scan creation |
| `ErrorMessage__c` | Long Text Area | 32 768 | Populated only when `Status__c = Failed` |
| `TotalFindings__c` | Roll-Up Summary | COUNT | All child `HealthFinding__c` records |
| `CriticalCount__c` | Roll-Up Summary | COUNT | Findings where `Severity__c = Critical` |
| `HighCount__c` | Roll-Up Summary | COUNT | Findings where `Severity__c = High` |

**Grade thresholds** (applied by `finaliseScan()`):

| Score | Grade |
|---|---|
| ≥ 90 | A |
| ≥ 75 | B |
| ≥ 60 | C |
| ≥ 40 | D |
| < 40 | F |

---

## 2. `HealthModuleScore__c`

One record per module per scan. Stores the raw 0–100 score, the configured weight snapshot, the weighted contribution to the composite score, per-severity finding counts, and execution metadata (duration, error).

Sharing model: `ControlledByParent` (inherits from `HealthScan__c`).

| Field API Name | Type | Precision / Length | Notes |
|---|---|---|---|
| `Name` | Auto Number | `HMS-{00000}` | System name field |
| `HealthScan__c` | Master-Detail | — | Parent scan; `relationshipOrder=0` |
| `Module__c` | Picklist | — | `Security` · `Automation` · `CodeQuality` · `Metadata` · `DataQuality` · `GovernorLimits` |
| `Score__c` | Number | 4,1 | 0–100; written by module on completion |
| `Weight__c` | Number | 5,2 | Snapshot of weight at scan time (from `OrgHealthModuleConfig__mdt`) |
| `WeightedContribution__c` | Formula (Number) | 5,2 | `Score__c × Weight__c / 100` |
| `Status__c` | Picklist | — | `Complete` · `Failed` · `Skipped` |
| `CriticalCount__c` | Number | 6,0 | Written by module; used by dashboard |
| `HighCount__c` | Number | 6,0 | |
| `MediumCount__c` | Number | 6,0 | |
| `LowCount__c` | Number | 6,0 | |
| `InfoCount__c` | Number | 6,0 | |
| `DurationMs__c` | Number | 10,0 | `System.currentTimeMillis()` delta |
| `ErrorMessage__c` | Long Text Area | 32 768 | Populated only when `Status__c = Failed` |

**Why snapshot `Weight__c` here?** The weight in the CMT record can change between scans. Storing the weight at scan time means historical composite scores remain reproducible.

---

## 3. `HealthFinding__c`

One record per individual issue detected. Linked to the scan (master-detail) and to the specific module run that produced it (lookup). The `FindingKey__c` external ID gives each finding a stable, human-readable fingerprint across scans so the dashboard can detect repeat or resolved issues.

Sharing model: `ControlledByParent` (inherits from `HealthScan__c`).

| Field API Name | Type | Precision / Length | Notes |
|---|---|---|---|
| `Name` | Auto Number | `HF-{00000}` | System name field |
| `HealthScan__c` | Master-Detail | — | Parent scan |
| `HealthModuleScore__c` | Lookup | — | Module run that produced this finding |
| `Module__c` | Text | 50 | Denormalised copy for SOQL without join |
| `Severity__c` | Picklist | — | `Critical` · `High` · `Medium` · `Low` · `Info` |
| `Category__c` | Text | 100 | Human-readable category, e.g. `FLS Gaps` |
| `Title__c` | Text | 255 | Short title, e.g. `SOQL inside for-loop` |
| `Description__c` | Long Text Area | 32 768 | Full description of the issue |
| `Recommendation__c` | Long Text Area | 32 768 | Actionable remediation step |
| `AffectedComponent__c` | Text | 255 | e.g. `Account.Legacy__c`, `OrderTrigger` |
| `AffectedComponentType__c` | Picklist | — | `Object` · `Field` · `ApexClass` · `ApexTrigger` · `Flow` · `Profile` · `PermissionSet` · `Layout` · `Org` |
| `FindingKey__c` | Text (External ID) | 255 | Stable fingerprint: `{Module}__{Category}__{AffectedComponent}` |
| `IsResolved__c` | Checkbox | — | Default `false`; set manually after remediation |
| `ResolvedDate__c` | DateTime | — | |
| `ResolvedBy__c` | Lookup (User) | — | |
| `StackTrace__c` | Long Text Area | 32 768 | Apex stack trace when module throws an exception |

**`FindingKey__c` construction** (in Apex):
```apex
finding.FindingKey__c = moduleName + '__' + category + '__' + affectedComponent;
```
This lets the LWC dashboard identify whether the same issue recurred in a previous scan without an expensive SOQL join.

**Why denormalise `Module__c`?** `HealthModuleScore__c` is only a Lookup here (not Master-Detail), so you cannot use a cross-object formula or roll-up. The denormalised text field allows simple `WHERE Module__c = 'Security'` filters without an extra join.

---

## 4. `OrgHealthModuleConfig__mdt` — Custom Metadata Type

Stores per-module configuration. Six seed records are deployed with the package. Weight values must sum to 100.

| Field API Name | Type | Notes |
|---|---|---|
| `Label` | Text | Human-readable name (`Security`, `Code Quality`, …) |
| `Module__c` | Text (50) | API key used in Apex (`Security`, `CodeQuality`, …) |
| `Weight__c` | Number (5,2) | % contribution to composite score |
| `IsEnabled__c` | Checkbox | Skip this module's Queueable if `false` |
| `DisplayOrder__c` | Number (2,0) | Order in the LWC dashboard module-score panel |

**Seed records:**

| Record | `Module__c` | `Weight__c` | `DisplayOrder__c` |
|---|---|---|---|
| Security | Security | 30 | 1 |
| Automation | Automation | 20 | 2 |
| Code Quality | CodeQuality | 20 | 3 |
| Metadata | Metadata | 15 | 4 |
| Data Quality | DataQuality | 10 | 5 |
| Governor Limits | GovernorLimits | 5 | 6 |

---

## 5. `OrgHealthSeverityConfig__mdt` — Custom Metadata Type

Maps each severity level to its score deduction. Allows tuning the scoring model via a deployment rather than an Apex change.

| Field API Name | Type | Notes |
|---|---|---|
| `Label` | Text | `Critical`, `High`, … |
| `Severity__c` | Text (20) | API key; matches `HealthFinding__c.Severity__c` picklist values |
| `ScoreDeduction__c` | Number (4,1) | Points deducted per finding of this severity |
| `GradeImpact__c` | Text (100) | Informational description of impact |

**Seed records:**

| Severity | Deduction | Grade Impact |
|---|---|---|
| Critical | 20 | Can drop grade by two levels |
| High | 10 | Can drop grade by one level |
| Medium | 5 | Minor grade impact, cumulative effect significant |
| Low | 2 | Minimal individual impact |
| Info | 0 | Informational only, no score impact |

---

## Design Decisions

### Three objects instead of two (vs. README baseline)

The README baseline used `RecordType='ModuleSummary'` on `HealthFinding__c` to store per-module scores. This was collapsed into a dedicated `HealthModuleScore__c` object because:
- Roll-up summaries from findings to the scan header require a clean Master-Detail; a single object serving two record types makes those roll-ups ambiguous.
- The LWC module-score bar chart queries exactly one record type per module — a dedicated object makes that a `WHERE Module__c = '…'` query rather than `WHERE RecordType = 'ModuleSummary' AND Module__c = '…'`.
- Module execution metadata (`DurationMs__c`, `Status__c`) has no meaning on a finding record.

### Custom Metadata instead of Custom Settings or hardcoded constants

Weights and deduction values are deployment artifacts — they should be version-controlled alongside Apex and be testable in scratch orgs. Custom Metadata Types survive sandbox refreshes, can be included in change sets, and are readable in Apex without a DML-counted query. Custom Settings require a separate data load step after each scratch org creation.

### `FindingKey__c` external ID

A stable fingerprint (`Module__Category__Component`) across scans enables the dashboard to answer "how many consecutive scans has this finding appeared in?" and "was this finding resolved and then regressed?" without an O(n) SOQL loop. The external ID flag also allows upsert operations if a future batch process needs to deduplicate findings.

### `Weight__c` snapshot on `HealthModuleScore__c`

The composite score formula reads `SUM(WeightedContribution__c)` over the six module score records. If the weight in the CMT record were used directly at query time, retroactively changing a weight would silently recalculate historical scores. Snapshotting the weight at scan time keeps historical composite scores immutable.
