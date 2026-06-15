public with sharing class OrgHealthDashboardController {

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

    /** Returns the last numScans completed scans for the trend chart. */
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

    /** Returns per-module scores for the given scan, excluding deactivated modules. */
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

    /** Returns findings for a specific scan, optionally filtered by severity. */
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

    /** Kicks off a new manual scan and returns the HealthScan__c Id for polling. */
    @AuraEnabled
    public static Id triggerScan() {
        return OrgHealthScanOrchestrator.startScan();
    }

    /**
     * Lightweight poll endpoint. LWC calls this on a short interval after triggerScan()
     * until Status__c transitions out of 'In Progress'.
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

    /** Returns per-module progress for a scan in flight, ordered by execution sequence. */
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
