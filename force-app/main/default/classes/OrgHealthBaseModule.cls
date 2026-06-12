/**
 * Abstract base for every health check module.
 *
 * Execution contract (two phases to satisfy the Apex callout-after-DML restriction):
 *   Phase 1 – runChecks(): subclass performs queries / callouts and calls addFinding().
 *             No DML is issued during this phase.
 *   Phase 2 – after runChecks() returns (or throws), all DML is issued in one batch:
 *             insert HealthModuleScore__c, populate HealthFinding__c.HealthModuleScore__c,
 *             insert HealthFinding__c.
 *
 * Chaining: the last statement in execute() always enqueues the next module (or calls
 * finaliseScan if this is the last one), even when runChecks() threw.
 */
public abstract class OrgHealthBaseModule implements Queueable, Database.AllowsCallouts {

    protected final Id     scanId;
    protected final String moduleName;
    protected Id           moduleScoreId;

    private final List<HealthFinding__c> pendingFindings = new List<HealthFinding__c>();

    protected OrgHealthBaseModule(Id scanId, String moduleName) {
        this.scanId     = scanId;
        this.moduleName = moduleName;
    }

    // ── Subclass contract ────────────────────────────────────────────────────

    protected abstract void runChecks();

    // ── Queueable entry point ────────────────────────────────────────────────

    public void execute(QueueableContext ctx) {
        Long    startMs  = System.currentTimeMillis();
        String  status   = 'Complete';
        String  errorMsg = null;

        // Phase 1: callouts / SOQL — no DML
        try {
            runChecks();
        } catch (Exception e) {
            status   = 'Failed';
            errorMsg = (e.getMessage() + '\n' + e.getStackTraceString()).left(32000);
        }

        // Phase 2: all DML after callouts are done
        OrgHealthModuleConfig__mdt cfg = OrgHealthConstants.getModuleConfigs().get(moduleName);
        Decimal weight = cfg != null ? cfg.Weight__c : 0;

        HealthModuleScore__c ms = new HealthModuleScore__c(
            HealthScan__c    = scanId,
            Module__c        = moduleName,
            Weight__c        = weight,
            Status__c        = status,
            Score__c         = computeScore(),
            CriticalCount__c = countBySeverity('Critical'),
            HighCount__c     = countBySeverity('High'),
            MediumCount__c   = countBySeverity('Medium'),
            LowCount__c      = countBySeverity('Low'),
            InfoCount__c     = countBySeverity('Info'),
            DurationMs__c    = System.currentTimeMillis() - startMs,
            ErrorMessage__c  = errorMsg
        );
        insert ms;
        this.moduleScoreId = ms.Id;

        for (HealthFinding__c f : pendingFindings) {
            f.HealthModuleScore__c = ms.Id;
        }
        if (!pendingFindings.isEmpty()) {
            insert pendingFindings;
        }

        chainNext();
    }

    // ── Finding helpers for subclasses ───────────────────────────────────────

    protected void addFinding(
        String severity,
        String category,
        String title,
        String description,
        String recommendation,
        String affectedComponent,
        String affectedComponentType
    ) {
        pendingFindings.add(new HealthFinding__c(
            HealthScan__c           = scanId,
            Module__c               = moduleName,
            Severity__c             = severity,
            Category__c             = category,
            Title__c                = title,
            Description__c          = description,
            Recommendation__c       = recommendation,
            AffectedComponent__c    = affectedComponent,
            AffectedComponentType__c = affectedComponentType,
            FindingKey__c           = moduleName + '__' + category + '__' + affectedComponent
        ));
    }

    // Convenience overload for org-level findings with no specific component
    protected void addFinding(
        String severity,
        String category,
        String title,
        String description,
        String recommendation
    ) {
        addFinding(severity, category, title, description, recommendation, 'Org', 'Org');
    }

    // ── Tooling API helper ───────────────────────────────────────────────────

    /**
     * Issues a Tooling API SOQL query and returns the parsed response body.
     * Requires the org domain to be in Remote Site Settings (or a Named Credential).
     * UserInfo.getSessionId() is available in Queueable contexts.
     */
    protected Map<String, Object> toolingQuery(String soql) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            URL.getOrgDomainUrl().toExternalForm()
            + '/services/data/v66.0/tooling/query?q='
            + EncodingUtil.urlEncode(soql, 'UTF-8')
        );
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');

        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new OrgHealthException(
                'Tooling API returned ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private Decimal computeScore() {
        Decimal score = 100;
        Map<String, OrgHealthSeverityConfig__mdt> cfgs = OrgHealthConstants.getSeverityConfigs();
        for (HealthFinding__c f : pendingFindings) {
            OrgHealthSeverityConfig__mdt sc = cfgs.get(f.Severity__c);
            if (sc != null) {
                score -= sc.ScoreDeduction__c;
            }
        }
        return Math.max(0, score);
    }

    private Integer countBySeverity(String severity) {
        Integer n = 0;
        for (HealthFinding__c f : pendingFindings) {
            if (severity == f.Severity__c) n++;
        }
        return n;
    }

    private void chainNext() {
        List<String> chain = OrgHealthConstants.MODULE_CHAIN;
        Integer idx = chain.indexOf(moduleName);
        if (idx >= 0 && idx < chain.size() - 1) {
            System.enqueueJob(
                OrgHealthModuleFactory.create(chain.get(idx + 1), scanId)
            );
        } else {
            OrgHealthScanOrchestrator.finaliseScan(scanId);
        }
    }

    // ── Tooling API response helpers ─────────────────────────────────────────

    protected List<Map<String, Object>> extractRecords(Map<String, Object> response) {
        List<Object> raw = (List<Object>) response.get('records');
        if (raw == null) return new List<Map<String, Object>>();
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Object r : raw) {
            result.add((Map<String, Object>) r);
        }
        return result;
    }

    protected String str(Map<String, Object> row, String field) {
        Object val = row.get(field);
        return val == null ? '' : String.valueOf(val);
    }

    protected Integer toInt(Object val) {
        if (val == null) return 0;
        return Integer.valueOf(String.valueOf(val));
    }

    // Apex has no List.subList() — returns a new list with the first n elements
    protected List<String> firstN(List<String> src, Integer n) {
        List<String> out = new List<String>();
        for (Integer i = 0; i < Math.min(n, src.size()); i++) {
            out.add(src[i]);
        }
        return out;
    }

    // ── Exception ────────────────────────────────────────────────────────────

    public class OrgHealthException extends Exception {}
}
