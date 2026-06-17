/**
 * Orchestrator for health scan execution.
 * Creates a new HealthScan__c record and enqueues the first enabled module in the chain.
 * Also handles scan finalisation (composite score calculation) when all modules complete.
 */
public class OrgHealthScanOrchestrator {

    // ── Public entry points ──────────────────────────────────────────────────

    /**
     * Initiates a health scan triggered manually from the dashboard LWC.
     * @return The ID of the newly created HealthScan__c record
     */
    @AuraEnabled
    public static Id startScan() {
        return initiateScan('Manual');
    }

    /**
     * Initiates a health scan triggered by a scheduled Apex job.
     * @return The ID of the newly created HealthScan__c record
     */
    public static Id startScheduledScan() {
        return initiateScan('Scheduled');
    }

    /**
     * Initiates a health scan via REST API.
     * @return The ID of the newly created HealthScan__c record
     */
    @AuraEnabled
    public static Id startApiScan() {
        return initiateScan('API');
    }

    // ── Finalisation — called by OrgHealthChainFinalizer after last module ────

    /**
     * Computes and persists the composite score after all modules complete.
     * Sums the weighted contributions from all module score records.
     * Assigns a letter grade and marks the scan Complete.
     * If an error occurs, marks the scan Failed (best-effort).
     * @param scanId The ID of the HealthScan__c to finalise
     */
    public static void finaliseScan(Id scanId) {
        try {
            Decimal composite = 0;
            for (HealthModuleScore__c ms : [
                SELECT WeightedContribution__c, Status__c
                FROM HealthModuleScore__c
                WHERE HealthScan__c = :scanId
            ]) {
                if (ms.Status__c == 'Complete' && ms.WeightedContribution__c != null) {
                    composite += ms.WeightedContribution__c;
                }
            }
            composite = Math.min(100, Math.max(0, composite));

            update new HealthScan__c(
                Id                = scanId,
                Status__c         = 'Complete',
                CompositeScore__c = composite,
                Grade__c          = OrgHealthConstants.calculateGrade(composite),
                ScanEndTime__c    = System.now()
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'finaliseScan failed for scan ' + scanId + ': ' + e.getMessage());
            // Best-effort: mark the scan Failed rather than leaving it In Progress
            try {
                update new HealthScan__c(
                    Id             = scanId,
                    Status__c      = 'Failed',
                    ScanEndTime__c = System.now()
                );
            } catch (Exception e2) {
                System.debug(LoggingLevel.ERROR,
                    'Could not update scan status to Failed: ' + e2.getMessage());
            }
        }
    }

    // ── Private ──────────────────────────────────────────────────────────────

    private static Id initiateScan(String triggerType) {
        HealthScan__c scan = new HealthScan__c(
            Status__c       = 'In Progress',
            TriggerType__c  = triggerType,
            ScanStartTime__c = System.now(),
            OrgId__c        = UserInfo.getOrganizationId(),
            OrgName__c      = UserInfo.getOrganizationName(),
            TriggeredBy__c  = UserInfo.getUserId()
        );
        insert scan;

        Map<String, OrgHealthModuleConfig__mdt> configs = OrgHealthConstants.getModuleConfigs();
        String firstEnabled = null;
        for (String module : OrgHealthConstants.MODULE_CHAIN) {
            OrgHealthModuleConfig__mdt cfg = configs.get(module);
            Boolean defaultEnabled = cfg != null ? cfg.IsEnabled__c : false;
            if (OrgHealthConstants.isEnabled(module, defaultEnabled)) {
                firstEnabled = module;
                break;
            }
        }

        if (firstEnabled != null) {
            System.enqueueJob(OrgHealthModuleFactory.create(firstEnabled, scan.Id));
        } else {
            // All modules disabled — finalise immediately
            OrgHealthScanOrchestrator.finaliseScan(scan.Id);
        }

        return scan.Id;
    }
}
