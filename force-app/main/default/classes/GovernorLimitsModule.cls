public class GovernorLimitsModule extends OrgHealthBaseModule {

    private static final Decimal STORAGE_WARN_PCT = 0.80;
    private static final Decimal API_WARN_PCT     = 0.80;
    private static final Decimal ASYNC_WARN_PCT   = 0.80;
    private static final Integer BATCH_BACKLOG_WARN = 10;
    private static final Integer FAILED_JOBS_WARN   = 1;

    public GovernorLimitsModule(Id scanId) {
        super(scanId, OrgHealthConstants.MODULE_GOVERNOR_LIMITS);
    }

    protected override void runChecks() {
        checkDataStorage();
        checkApiRequestUsage();
        checkQueryRowUsage();
        checkAsyncApexUsage();
    }

    private void checkDataStorage() {
        if (!OrgHealthConstants.isCheckpointEnabled('GovernorLimits.DataStorage')) return;
        OrgLimit storage = OrgLimits.getMap().get('DataStorageMB');
        if (storage == null || storage.getLimit() == 0) return;

        Decimal usagePct = (Decimal) storage.getValue() / storage.getLimit();
        if (usagePct < STORAGE_WARN_PCT) return;

        String severity = usagePct >= 0.95 ? 'Critical' : 'High';
        addFinding(
            severity,
            'Storage',
            'Data storage at ' + (usagePct * 100).setScale(0) + '% of org limit',
            'The org is using ' + storage.getValue() + ' MB of its ' + storage.getLimit() + ' MB ' +
            'data storage allocation (' + (usagePct * 100).setScale(1) + '%). ' +
            'Approaching the limit can cause DML operations to fail with a storage error.',
            'Archive or hard-delete stale records (use the Recycle Bin empty and Data Archive). ' +
            'Review large objects using the Storage Usage page (Setup > Storage Usage). ' +
            'Consider purchasing additional data storage if archival is not feasible.',
            'Org',
            'Org'
        );
    }

    private void checkApiRequestUsage() {
        if (!OrgHealthConstants.isCheckpointEnabled('GovernorLimits.ApiRequestUsage')) return;
        OrgLimit apiLimit = OrgLimits.getMap().get('DailyApiRequests');
        if (apiLimit == null || apiLimit.getLimit() == 0) return;

        Decimal usagePct = (Decimal) apiLimit.getValue() / apiLimit.getLimit();
        if (usagePct < API_WARN_PCT) return;

        addFinding(
            'High',
            'API Limits',
            'Daily API requests at ' + (usagePct * 100).setScale(0) + '% of limit',
            apiLimit.getValue() + ' of ' + apiLimit.getLimit() + ' daily API requests have been ' +
            'consumed today (' + (usagePct * 100).setScale(1) + '%). Hitting the limit blocks all ' +
            'REST, SOAP, and Bulk API calls for the remainder of the calendar day.',
            'Review integrations for unnecessary polling. Switch batch integrations to Bulk API 2.0 ' +
            '(counts separately). Implement caching for read-heavy integrations. ' +
            'Monitor trends in Setup > System Overview.',
            'Org',
            'Org'
        );
    }

    private void checkQueryRowUsage() {
        if (!OrgHealthConstants.isCheckpointEnabled('GovernorLimits.AsyncJobQueue')) return;
        Integer batchBacklog = [
            SELECT COUNT() FROM AsyncApexJob
            WHERE Status IN ('Queued', 'Processing')
            AND JobType = 'BatchApex'
        ];

        if (batchBacklog >= BATCH_BACKLOG_WARN) {
            addFinding(
                'Medium',
                'Async Queue Backlog',
                batchBacklog + ' batch Apex jobs are queued or processing',
                batchBacklog + ' batch Apex jobs are currently in the queue or actively running. ' +
                'A large backlog means jobs are scheduling faster than they complete, which can ' +
                'cause significant processing delays and consecutive governor limit hits.',
                'Review the Apex Jobs queue in Setup > Apex Jobs. Check for infinite scheduling loops, ' +
                'reduce batch scope on large jobs, and consider spreading scheduled jobs to off-peak hours.',
                'Org',
                'Org'
            );
        }

        Integer failedToday = [
            SELECT COUNT() FROM AsyncApexJob
            WHERE Status = 'Failed'
            AND CompletedDate = TODAY
        ];

        if (failedToday >= FAILED_JOBS_WARN) {
            addFinding(
                failedToday >= 5 ? 'High' : 'Medium',
                'Async Failures',
                failedToday + ' async Apex job(s) failed today',
                failedToday + ' Apex jobs (Batch, Scheduled, Queueable, or Future) failed today. ' +
                'Repeated async failures often indicate governor limit breaches, unhandled data exceptions, ' +
                'or broken integration callouts.',
                'Review failed jobs in Setup > Apex Jobs > View. Examine the ExtendedStatus field for ' +
                'error messages. Fix the root cause — governor limits, null-pointer exceptions, or missing ' +
                'error handling — and requeue jobs as needed.',
                'Org',
                'Org'
            );
        }
    }

    private void checkAsyncApexUsage() {
        if (!OrgHealthConstants.isCheckpointEnabled('GovernorLimits.AsyncApexUsage')) return;
        OrgLimit apexJobs = OrgLimits.getMap().get('DailyAsyncApexExecutions');
        if (apexJobs == null || apexJobs.getLimit() == 0) return;

        Decimal usagePct = (Decimal) apexJobs.getValue() / apexJobs.getLimit();
        if (usagePct < ASYNC_WARN_PCT) return;

        addFinding(
            'Medium',
            'Async Apex',
            'Daily async Apex executions at ' + (usagePct * 100).setScale(0) + '% of limit',
            apexJobs.getValue() + ' of ' + apexJobs.getLimit() + ' daily async Apex executions used ' +
            '(' + (usagePct * 100).setScale(1) + '%). This covers Queueable, Schedulable, Future, ' +
            'and Batch Apex. Exhausting this limit prevents any further async execution today.',
            'Review all scheduled and batch jobs for redundancy or consolidation. ' +
            'Combine multiple small Queueable chains into a single Batch job. ' +
            'Offload non-critical processing to nightly scheduled runs to spread load.',
            'Org',
            'Org'
        );
    }
}
