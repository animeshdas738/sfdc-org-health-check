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

### 3. Deploy classes
```bash
sf project deploy start --source-dir force-app
```

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

## Extending with a New Module

1. Create a new class extending `OrgHealthBaseModule`
2. Implement `runChecks()` — call `addFinding()` for each issue found
3. Register it in `OrgHealthModuleFactory`
4. Add it to `OrgHealthConstants.MODULE_CHAIN`
5. Add its weight in `OrgHealthScanOrchestrator.MODULE_WEIGHTS` (adjust others so total = 100)

---

