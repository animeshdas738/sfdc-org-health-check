public class OrgHealthScanOrchestrator {

    // ── Public entry points ──────────────────────────────────────────────────

    /** Called from LWC trigger button. */
    @AuraEnabled
    public static Id startScan() {
        return initiateScan('Manual');
    }

    /** Called by OrgHealthScheduler. */
    public static Id startScheduledScan() {
        return initiateScan('Scheduled');
    }

    /** For external REST API consumers. */
    @AuraEnabled
    public static Id startApiScan() {
        return initiateScan('API');
    }

    // ── Finalisation — called by last module in chain ────────────────────────

    public static void finaliseScan(Id scanId) {
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
            Id             = scanId,
            Status__c      = 'Complete',
            CompositeScore__c = composite,
            Grade__c       = OrgHealthConstants.calculateGrade(composite),
            ScanEndTime__c = System.now()
        );
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

        System.enqueueJob(
            OrgHealthModuleFactory.create(
                OrgHealthConstants.MODULE_CHAIN.get(0),
                scan.Id
            )
        );

        return scan.Id;
    }
}
