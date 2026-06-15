/**
 * Finalizer attached to every module's Queueable job.
 *
 * Two responsibilities:
 *  1. Chain the next module — because a Queueable enqueued from a Finalizer
 *     always starts at stack depth 1, this sidesteps the 5-level Queueable
 *     chaining limit that would otherwise be hit at DataQuality in Dev/Sandbox orgs.
 *  2. Recover from a stuck scan — if the parent job throws an uncaught exception,
 *     the Finalizer still runs and marks the scan Failed rather than leaving it
 *     permanently In Progress.
 */
public class OrgHealthChainFinalizer implements Finalizer {

    private final Id     scanId;
    private final String moduleName;

    public OrgHealthChainFinalizer(Id scanId, String moduleName) {
        this.scanId     = scanId;
        this.moduleName = moduleName;
    }

    public void execute(FinalizerContext ctx) {
        if (ctx.getResult() == ParentJobResult.UNHANDLED_EXCEPTION) {
            Exception e = ctx.getException();
            String msg = ('Unhandled exception in module ' + moduleName + ': ' +
                          (e != null ? e.getMessage() : 'unknown')).left(32000);
            System.debug(LoggingLevel.ERROR, msg);
            markScanFailed(msg);
            return;
        }

        String nextModule = nextEnabledModule(moduleName);

        if (nextModule != null) {
            try {
                System.enqueueJob(OrgHealthModuleFactory.create(nextModule, scanId));
            } catch (Exception enqueueEx) {
                String msg = ('Failed to enqueue module after ' + moduleName + ': ' +
                              enqueueEx.getMessage()).left(32000);
                System.debug(LoggingLevel.ERROR, msg);
                markScanFailed(msg);
            }
        } else {
            OrgHealthScanOrchestrator.finaliseScan(scanId);
        }
    }

    private static String nextEnabledModule(String currentModule) {
        List<String> chain = OrgHealthConstants.MODULE_CHAIN;
        Map<String, OrgHealthModuleConfig__mdt> configs = OrgHealthConstants.getModuleConfigs();
        Integer idx = chain.indexOf(currentModule);
        for (Integer i = idx + 1; i < chain.size(); i++) {
            String candidate = chain.get(i);
            OrgHealthModuleConfig__mdt cfg = configs.get(candidate);
            Boolean defaultEnabled = cfg != null ? cfg.IsEnabled__c : false;
            if (OrgHealthConstants.isEnabled(candidate, defaultEnabled)) {
                return candidate;
            }
        }
        return null;
    }

    private void markScanFailed(String errorMsg) {
        try {
            update new HealthScan__c(
                Id              = scanId,
                Status__c       = 'Failed',
                ScanEndTime__c  = System.now(),
                ErrorMessage__c = errorMsg
            );
        } catch (Exception updateEx) {
            System.debug(LoggingLevel.ERROR,
                'Could not mark scan as Failed: ' + updateEx.getMessage());
        }
    }
}
