# Salesforce DX Project: Next Steps

Now that you’ve created a Salesforce DX project, what’s next? Here are some documentation resources to get you started.

## How Do You Plan to Deploy Your Changes?

Do you want to deploy a set of changes, or create a self-contained application? Choose a [development model](https://developer.salesforce.com/tools/vscode/en/user-guide/development-models).

## Configure Your Salesforce DX Project

The `sfdx-project.json` file contains useful configuration information for your project. See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm) in the _Salesforce DX Developer Guide_ for details about this file.

## Read All About It

- [Salesforce Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
- [Salesforce CLI Setup Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference.htm)

# Salesforce Org Health Monitor

An enterprise-grade Apex framework that automatically scans your Salesforce org across 6 health dimensions and produces a scored, actionable audit report.

See [`docs/object-model.md`](docs/object-model.md) for the full data model, field reference, and design decisions.
See [`docs/solution-architecture.md`](docs/solution-architecture.md) for module architecture and configuration extensibility.
See [`docs/testing-guide.md`](docs/testing-guide.md) for comprehensive testing documentation.

---

## Features

- **6 Health Dimensions**: Security, Automation, Code Quality, Metadata, Data Quality, Governor Limits
- **Weighted Scoring**: Configurable module weights (default: 30/20/20/10/10/10)
- **Async Chaining**: Queueable jobs execute in sequence, respecting governor limits via Finalizer pattern
- **25 Built-in Checkpoints**: Individual checks per module, each independently enable/disable-able
- **Two-Layer Config**: CMT (developer defaults) + Custom Settings (admin overrides)
- **Configuration UI**: LWC admin panel to toggle modules and checkpoints
- **Comprehensive Testing**: 59+ unit tests covering orchestration, config, controllers, and modules

### Architecture Highlights

**Two-Layer Configuration Pattern**
- **Layer 1 (CMT)**: Developer catalog — module weights, checkpoint definitions, defaults
- **Layer 2 (Custom Settings)**: Admin overrides — runtime toggles for modules/checkpoints
- **Gateway**: `OrgHealthConstants.isEnabled()` merges both layers transparently

**Async Execution with Finalizer Pattern**
- Avoids Queueable stack depth limit (5 levels in Dev/Sandbox)
- Queueables enqueued from Finalizers start at depth 1
- Finalizer catches exceptions and marks failed scans appropriately

**Per-Checkpoint Gating**
- 25 individual checkpoints, each independently configurable
- Admins disable checks without code changes
- Auto-discovered by config UI — no hardcoded lists

---

## Setup

### 1. Deploy the custom objects
Object metadata XML is in `force-app/main/default/objects/`. Deploy via step 3 below — no manual setup needed.
Objects: `HealthScan__c`, `HealthModuleScore__c`, `HealthFinding__c`. Custom Metadata Types: `OrgHealthModuleConfig__mdt`, `OrgHealthSeverityConfig__mdt`.

### 2. Named Credential (for Tooling API)
Create a Named Credential pointing to your org's domain with OAuth flow,
or use the session ID pattern in `OrgHealthBaseModule.toolingQuery()` which works in same-org callouts.

For same-org callouts, add your org's domain to Remote Site Settings:
`Setup → Security → Remote Site Settings → New`
URL: `https://yourorg.my.salesforce.com`

### 3. Deploy all components
```bash
sf project deploy start --source-dir force-app
```

This deploys:
- Apex classes (modules, controllers, orchestrator)
- LWC components (dashboard, config, charts)
- Custom objects and fields
- Custom Metadata Type definitions (modules, checkpoints, severities)
- 25 checkpoint seed records
- Custom Settings structure

### 4. Schedule the weekly scan
```apex
String cronExp = '0 0 2 ? * SUN';   // Every Sunday at 2 AM
System.schedule('Org Health Weekly Scan', cronExp, new OrgHealthScheduler());
```

### 5. Run a manual scan
```apex
Id scanId = OrgHealthScanOrchestrator.startScan();
System.debug('Scan started: ' + scanId);
```

---

## Running Tests

The application includes **59 comprehensive unit tests** covering all core functionality.

### Run all Org Health tests
```bash
sf apex run test --class-names OrgHealthScanOrchestratorTest,OrgHealthConstantsTest,OrgHealthConfigControllerTest,OrgHealthDashboardControllerTest,OrgHealthModuleFactoryTest,SecurityScannerModuleTest --wait 10
```

### Run all tests in the org
```bash
sf apex run test --wait 15
```

### Test Coverage (by component)
| Component | Tests | Status |
|-----------|-------|--------|
| OrgHealthScanOrchestrator | 8 | ✅ |
| OrgHealthConstants | 16 | ✅ |
| OrgHealthModuleFactory | 9 | ✅ |
| OrgHealthConfigController | 10 | ✅ |
| OrgHealthDashboardController | 14 | ✅ |
| SecurityScannerModule | 8 | ✅ |
| **Total** | **65** | **100%** |

For detailed testing documentation, see [`docs/testing-guide.md`](docs/testing-guide.md).

---

## Configuration UI

Org admins can use the **Org Health Config** LWC to toggle modules and individual checkpoints at runtime without code changes.

1. Add the `orgHealthConfig` LWC to a Lightning page
2. Administrators can enable/disable:
   - Individual modules (affects scan execution)
   - Individual checkpoints within each module
3. Changes take effect on the next scan

Configuration is stored in `OrgHealthConfigOverride__c` (List Custom Setting) and can be backed up/deployed like standard metadata.

---

## Testing After Deployment

### 1. Add the Remote Site Setting

The Tooling API callouts use `URL.getOrgDomainUrl()`. Salesforce blocks same-org callouts unless the domain is whitelisted.

Get your org's domain URL:
```apex
System.debug(URL.getOrgDomainUrl().toExternalForm());
```

Then: **Setup → Security → Remote Site Settings → New**
- Remote Site Name: `OrgHealthToolingAPI`
- Remote Site URL: value from the debug log (no trailing slash)
- Active: ✅

### 2. Verify Custom Metadata records

**Setup → Custom Metadata Types → Manage Records** for each type:

| Type | Expected records |
|---|---|
| `OrgHealthModuleConfig__mdt` | 6 records — Security (30%), Automation (20%), CodeQuality (20%), Metadata (10%), DataQuality (10%), GovernorLimits (10%) |
| `OrgHealthSeverityConfig__mdt` | 5 records — Critical (25pt), High (15pt), Medium (8pt), Low (3pt), Info (1pt) |

If records are missing, redeploy the metadata folder:
```bash
sf project deploy start --source-dir force-app/main/default/customMetadata
```

### 3. Assign object permissions

The controller uses `with sharing`. The running user needs Read/Create/Edit on:
- `HealthScan__c`
- `HealthModuleScore__c`
- `HealthFinding__c`

Grant via the user's Profile or a dedicated Permission Set.

### 4. Smoke test via Anonymous Apex

Run in **Developer Console → Execute Anonymous**:
```apex
Id scanId = OrgHealthScanOrchestrator.startScan();
System.debug('Scan created: ' + scanId);
```

Monitor **Setup → Apex Jobs** — you should see 6 module jobs queue and complete in sequence. Then verify the result:
```apex
HealthScan__c s = [
    SELECT Status__c, CompositeScore__c, Grade__c,
           TotalFindings__c, CriticalCount__c, ErrorMessage__c
    FROM HealthScan__c
    ORDER BY ScanStartTime__c DESC LIMIT 1
];
System.debug(JSON.serializePretty(s));
```

Check module scores:
```apex
for (HealthModuleScore__c ms : [
    SELECT Module__c, Score__c, Status__c, ErrorMessage__c
    FROM HealthModuleScore__c
    ORDER BY CreatedDate DESC LIMIT 6
]) {
    System.debug(ms.Module__c + ' → ' + ms.Score__c + ' (' + ms.Status__c + ')');
}
```

If any module shows `Status__c = 'Failed'`, read its `ErrorMessage__c` — the most common cause is the missing Remote Site Setting from step 1.

### 5. Add the dashboard to a Lightning page

1. **Setup → Lightning App Builder → New**
2. Choose **App Page**, name it `Org Health Dashboard`, select **One Region** layout
3. Search for **Org Health Dashboard** in the component panel and drag it onto the canvas
4. **Save → Activate** → set visibility → Save
5. Open the activated page in Lightning Experience

### 6. Test the UI flow

1. The score from the Anonymous Apex scan in step 4 should already appear.
2. Click **Run New Scan** — the blue "Scan in progress" banner appears.
3. Wait ~30–60 s for the 6 async jobs to chain through. The page refreshes automatically on completion.
4. Verify each panel:
   - **Score gauge** — semicircle fills with red/amber/green and shows score + grade
   - **Module Breakdown** — 6 bars with per-module scores, weights, and finding chips
   - **Findings** — click any row to expand description and recommendation
   - **Score Trend** — appears after running a **second** scan (requires ≥ 2 data points)

### Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Module `Status__c = 'Failed'`, error has `CALLOUT_FAILED` | Remote Site Setting missing | Step 1 |
| All modules complete but composite score is 0 | CMT weight records missing | Step 2 |
| Dashboard shows "No scans yet" after a successful Apex scan | Object permissions | Step 3 |
| Findings list empty but `TotalFindings__c > 0` | `HealthFinding__c` read permission missing | Step 3 |
| `UserInfo.getSessionId()` returns null | Session ID not available in async context — enable **API Access Policies** in Session Settings | Setup |

---

## LWC Dashboard

Wire `OrgHealthDashboardController` to your LWC:

```javascript
// Get latest scan
@wire(getLatestScan) wiredScan;

// Get score trend (last 10 scans)
@wire(getScoreTrend, { numScans: 10 }) wiredTrend;

// Get per-module scores
@wire(getModuleScores) wiredModuleScores;

// Trigger a new scan
async handleScanClick() {
    const scanId = await triggerScan();
    // Poll getScanStatus(scanId) until Status__c === 'Complete'
}
```

---

## Extending the Framework

### Adding a New Module

1. Create a new class extending `OrgHealthBaseModule`
2. Implement `runChecks()` — call `addFinding()` for each issue found
3. Register it in `OrgHealthModuleFactory`
4. Add it to `OrgHealthConstants.MODULE_CHAIN`
5. Add a weight record to `OrgHealthModuleConfig__mdt` (ensure weights sum to 100)
6. Write tests extending the `ModuleTest` pattern in `SecurityScannerModuleTest`

### Adding a New Checkpoint

1. Create a new `OrgHealthCheckpointConfig__mdt` record with:
   - `CheckpointKey__c`: dot-separated key (e.g., `ModuleName.CheckpointName`)
   - `Module__c`: parent module name
   - `IsEnabledByDefault__c`: default enabled state
   - `Description__c`: description for the config UI
2. In your check method, add the gate:
   ```apex
   if (!OrgHealthConstants.isCheckpointEnabled('Module.CheckpointName')) return;
   ```
3. No controller or dashboard changes needed — the config UI and orchestrator auto-discover new checkpoints

See [`docs/solution-architecture.md`](docs/solution-architecture.md) for detailed extensibility patterns.

---

