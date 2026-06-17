/**
 * Apex controller backing the orgHealthDashboard LWC.
 * Provides scan results, module scores, findings, and scan orchestration endpoints.
 */
public with sharing class OrgHealthDashboardController {

    /**
     * Returns the most recent scan (of any status).
     * Used to hydrate the dashboard on initial load.
     * @return The latest HealthScan__c record, or null if no scans exist
     */
    @AuraEnabled(cacheable=true)
    public static HealthScan__c getLatestScan() {
        List<HealthScan__c> rows = [
            SELECT Id, Name, Status__c, CompositeScore__c, Grade__c,
                   ScanStartTime__c, ScanEndTime__c, ScanDuration__c,
                   TriggerType__c, OrgName__c, TotalFindings__c,
                   CriticalCount__c, HighCount__c, ErrorMessage__c
            FROM HealthScan__c
            ORDER BY ScanStartTime__c DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Returns the most recent completed scans in reverse chronological order.
     * Used to populate the Score Trend chart.
     * @param numScans The maximum number of scans to return
     * @return List of completed HealthScan__c records (newest first)
     */
    @AuraEnabled(cacheable=true)
    public static List<HealthScan__c> getScoreTrend(Integer numScans) {
        return [
            SELECT Id, Name, CompositeScore__c, Grade__c, ScanStartTime__c, TriggerType__c
            FROM HealthScan__c
            WHERE Status__c = 'Complete'
            ORDER BY ScanStartTime__c DESC
            LIMIT :numScans
        ];
    }

    /**
     * Returns per-module health scores for a completed scan.
     * Automatically filters out modules disabled via OrgHealthModuleConfig__mdt or admin overrides.
     * @param scanId The HealthScan__c ID
     * @return List of enabled HealthModuleScore__c records (ordered by weight descending)
     */
    @AuraEnabled(cacheable=true)
    public static List<HealthModuleScore__c> getModuleScores(Id scanId) {
        if (scanId == null) return new List<HealthModuleScore__c>();

        Set<String> enabledModules = new Set<String>();
        Map<String, OrgHealthModuleConfig__mdt> configs = OrgHealthConstants.getModuleConfigs();
        for (String moduleName : OrgHealthConstants.MODULE_CHAIN) {
            OrgHealthModuleConfig__mdt cfg = configs.get(moduleName);
            Boolean defaultEnabled = cfg != null ? cfg.IsEnabled__c : false;
            if (OrgHealthConstants.isEnabled(moduleName, defaultEnabled)) {
                enabledModules.add(moduleName);
            }
        }

        return [
            SELECT Id, Module__c, Score__c, Weight__c, WeightedContribution__c,
                   Status__c, CriticalCount__c, HighCount__c, MediumCount__c,
                   LowCount__c, InfoCount__c, DurationMs__c
            FROM HealthModuleScore__c
            WHERE HealthScan__c = :scanId
            AND   Module__c IN :enabledModules
            ORDER BY Weight__c DESC
        ];
    }

    /**
     * Returns findings (issues) detected in a scan.
     * Optionally filtered by severity level.
     * @param scanId The HealthScan__c ID
     * @param severity Optional: filter to one severity level (Critical, High, Medium, Low, Info)
     * @return List of HealthFinding__c records (ordered by severity ascending, capped at 500)
     */
    @AuraEnabled(cacheable=true)
    public static List<HealthFinding__c> getFindings(Id scanId, String severity) {
        if (String.isNotBlank(severity)) {
            return [
                SELECT Id, Title__c, Severity__c, Category__c, Module__c,
                       AffectedComponent__c, AffectedComponentType__c,
                       Description__c, Recommendation__c, IsResolved__c, FindingKey__c
                FROM HealthFinding__c
                WHERE HealthScan__c = :scanId AND Severity__c = :severity
                ORDER BY Severity__c ASC
                LIMIT 500
            ];
        }
        return [
            SELECT Id, Title__c, Severity__c, Category__c, Module__c,
                   AffectedComponent__c, AffectedComponentType__c,
                   Description__c, Recommendation__c, IsResolved__c, FindingKey__c
            FROM HealthFinding__c
            WHERE HealthScan__c = :scanId
            ORDER BY Severity__c ASC
            LIMIT 500
        ];
    }

    /**
     * Initiates a new manual health scan (triggered from the dashboard).
     * Returns immediately; LWC polls getScanStatus() to track progress.
     * @return The ID of the newly created HealthScan__c record
     */
    @AuraEnabled
    public static Id triggerScan() {
        return OrgHealthScanOrchestrator.startScan();
    }

    /**
     * Retrieves the current status of an in-flight or completed scan.
     * Called by the LWC on a ~3-second poll interval to detect completion.
     * Not cacheable (status changes frequently).
     * @param scanId The HealthScan__c ID
     * @return The scan header with status and aggregate finding counts
     */
    @AuraEnabled(cacheable=false)
    public static HealthScan__c getScanStatus(Id scanId) {
        return [
            SELECT Id, Status__c, CompositeScore__c, Grade__c,
                   ScanEndTime__c, ErrorMessage__c, TotalFindings__c,
                   CriticalCount__c, HighCount__c
            FROM HealthScan__c
            WHERE Id = :scanId
            LIMIT 1
        ];
    }

    /**
     * Returns per-module progress records for a scan in flight.
     * Ordered by creation time (execution sequence) so the LWC can render a progress bar for each module.
     * Not cacheable (records are created as modules complete).
     * @param scanId The HealthScan__c ID
     * @return List of HealthModuleScore__c records ordered by module execution sequence
     */
    @AuraEnabled(cacheable=false)
    public static List<HealthModuleScore__c> getScanModuleProgress(Id scanId) {
        if (scanId == null) return new List<HealthModuleScore__c>();
        return [
            SELECT Id, Module__c, Status__c, Score__c, DurationMs__c
            FROM HealthModuleScore__c
            WHERE HealthScan__c = :scanId
            ORDER BY CreatedDate ASC
        ];
    }
}
