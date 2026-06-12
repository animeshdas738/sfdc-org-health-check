public class AutomationAuditorModule extends OrgHealthBaseModule {

    public AutomationAuditorModule(Id scanId) {
        super(scanId, OrgHealthConstants.MODULE_AUTOMATION);
    }

    protected override void runChecks() {
        checkInactiveFlows();
        checkOverlappingTriggers();
        checkDuplicateRules();
        checkActiveProcessBuilders();
    }

    private void checkInactiveFlows() {
        List<FlowDefinitionView> rows = [
            SELECT ApiName, Label, ProcessType
            FROM FlowDefinitionView
            WHERE IsActive = false
            AND ProcessType IN ('Flow', 'AutoLaunchedFlow', 'CustomEvent', 'ContactRequestFlow')
        ];

        if (rows.isEmpty()) return;

        Map<String, List<String>> byType = new Map<String, List<String>>();
        for (FlowDefinitionView row : rows) {
            if (!byType.containsKey(row.ProcessType)) byType.put(row.ProcessType, new List<String>());
            byType.get(row.ProcessType).add(row.Label);
        }

        for (String type : byType.keySet()) {
            List<String> names = byType.get(type);
            addFinding(
                'Low',
                'Inactive Automation',
                names.size() + ' ' + type + ' flow(s) have no active version',
                names.size() + ' flows of type ' + type + ' have never been activated or were ' +
                'deactivated without deletion: ' +
                String.join(names.size() <= 10 ? names : firstN(names, 10), ', ') +
                (names.size() > 10 ? ' … and ' + (names.size() - 10) + ' more.' : '.'),
                'Delete flows that are no longer needed. Inactive flows accumulate as tech debt, ' +
                'slow down deployments, and confuse developers browsing the org.',
                type,
                'Flow'
            );
        }
    }

    private void checkOverlappingTriggers() {
        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT TableEnumOrId, Name ' +
                'FROM ApexTrigger ' +
                'WHERE Status = \'Active\''
            )
        );

        Map<String, List<String>> triggersByObject = new Map<String, List<String>>();
        for (Map<String, Object> row : rows) {
            String obj  = str(row, 'TableEnumOrId');
            String name = str(row, 'Name');
            if (!triggersByObject.containsKey(obj)) triggersByObject.put(obj, new List<String>());
            triggersByObject.get(obj).add(name);
        }

        for (String obj : triggersByObject.keySet()) {
            List<String> triggers = triggersByObject.get(obj);
            if (triggers.size() > 1) {
                addFinding(
                    'Medium',
                    'Multiple Triggers',
                    obj + ' has ' + triggers.size() + ' active triggers',
                    'Object ' + obj + ' has ' + triggers.size() + ' active Apex triggers: ' +
                    String.join(triggers, ', ') + '. Salesforce does not guarantee execution order ' +
                    'when multiple triggers fire on the same DML event, which can produce ' +
                    'unpredictable or conflicting behaviour.',
                    'Consolidate all triggers on ' + obj + ' into a single trigger that delegates ' +
                    'to a handler class (one entry-point per object per DML event). ' +
                    'Deactivate and delete redundant triggers after consolidation.',
                    obj,
                    'ApexTrigger'
                );
            }
        }
    }

    private void checkDuplicateRules() {
        Set<String> protected_x = new Set<String>();
        for (DuplicateRule dr : [
            SELECT SobjectType
            FROM DuplicateRule
            WHERE SobjectType IN ('Account', 'Contact', 'Lead')
            AND IsActive = true
        ]) {
            protected_x.add(dr.SobjectType);
        }

        for (String obj : new List<String>{'Account', 'Contact', 'Lead'}) {
            if (!protected_x.contains(obj)) {
                addFinding(
                    'Medium',
                    'Data Governance',
                    'No active Duplicate Rule on ' + obj,
                    'The ' + obj + ' object has no active Duplicate Rule. Without one, users can ' +
                    'create duplicate records unchecked, which degrades CRM data quality over time ' +
                    'and causes duplicate sends in marketing campaigns.',
                    'Create and activate a Duplicate Rule for ' + obj + ' in Setup > ' +
                    'Duplicate Management. Pair it with a Matching Rule using name, email, and phone ' +
                    'as matching criteria. Set the action to "Allow" with a warning for a soft ' +
                    'enforcement, or "Block" for stricter control.',
                    obj,
                    'Object'
                );
            }
        }
    }

    private void checkActiveProcessBuilders() {
        List<FlowDefinitionView> rows = [
            SELECT Label
            FROM FlowDefinitionView
            WHERE IsActive = true
            AND ProcessType = 'Workflow'
        ];

        if (rows.isEmpty()) return;

        List<String> pbNames = new List<String>();
        for (FlowDefinitionView row : rows) {
            pbNames.add(row.Label);
        }

        addFinding(
            'Medium',
            'Deprecated Automation',
            pbNames.size() + ' active Process Builder(s) should be migrated to Flow',
            pbNames.size() + ' Process Builder automation(s) are still active: ' +
            String.join(pbNames.size() <= 10 ? pbNames : firstN(pbNames, 10), ', ') +
            (pbNames.size() > 10 ? ' … and ' + (pbNames.size() - 10) + ' more.' : '.') +
            ' Salesforce has announced the retirement of Process Builder in favour of Record-Triggered Flows.',
            'Use the Flow Builder migration tool (open a Process Builder → Migrate to Flow) to ' +
            'auto-generate an equivalent Record-Triggered Flow. Test thoroughly, then deactivate ' +
            'the Process Builder. Prioritise high-traffic objects first.',
            'Org',
            'Flow'
        );
    }
}
