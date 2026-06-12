public class DataQualityModule extends OrgHealthBaseModule {

    private static final Decimal BLANK_RATE_THRESHOLD    = 0.15;
    private static final Integer STALE_OPPORTUNITY_DAYS  = 180;
    private static final Integer STALE_CASE_DAYS         = 90;

    public DataQualityModule(Id scanId) {
        super(scanId, OrgHealthConstants.MODULE_DATA_QUALITY);
    }

    // No callouts — all checks use regular SOQL aggregates
    protected override void runChecks() {
        checkDuplicateAccounts();
        checkDuplicateContacts();
        checkBlankRequiredFields();
        checkStaleRecords();
    }

    private void checkDuplicateAccounts() {
        AggregateResult[] groups = [
            SELECT Name, COUNT(Id) cnt
            FROM Account
            GROUP BY Name
            HAVING COUNT(Id) > 1
            ORDER BY COUNT(Id) DESC
            LIMIT 50
        ];

        if (groups.isEmpty()) return;

        Integer totalRecords = 0;
        for (AggregateResult ar : groups) {
            totalRecords += (Integer) ar.get('cnt');
        }

        addFinding(
            'Medium',
            'Duplicate Records',
            groups.size() + ' Account name collision(s) detected (' + totalRecords + ' records)',
            totalRecords + ' Account records share a name with at least one other Account ' +
            '(' + groups.size() + ' distinct name groups). Duplicate accounts fragment customer ' +
            'history, cause integration mismatches, and inflate pipeline metrics.',
            'Enable Duplicate Management for Accounts in Setup > Duplicate Management. ' +
            'Activate a Matching Rule using Account Name and Billing Address. ' +
            'Run a merge report and resolve duplicates before the next pipeline review.',
            'Account',
            'Object'
        );
    }

    private void checkDuplicateContacts() {
        AggregateResult[] groups = [
            SELECT Email, COUNT(Id) cnt
            FROM Contact
            WHERE Email != null
            GROUP BY Email
            HAVING COUNT(Id) > 1
            ORDER BY COUNT(Id) DESC
            LIMIT 50
        ];

        if (groups.isEmpty()) return;

        Integer totalRecords = 0;
        for (AggregateResult ar : groups) {
            totalRecords += (Integer) ar.get('cnt');
        }

        addFinding(
            'Medium',
            'Duplicate Records',
            groups.size() + ' Contact email collision(s) detected (' + totalRecords + ' records)',
            totalRecords + ' Contact records share an email address with at least one other Contact ' +
            '(' + groups.size() + ' distinct email collisions). ' +
            'Duplicate contacts cause double-sends in marketing campaigns and split engagement history.',
            'Enable Duplicate Management for Contacts using Email as the matching key. ' +
            'Review and merge duplicates before the next campaign send. ' +
            'Consider a deduplication tool for large-volume cleanup.',
            'Contact',
            'Object'
        );
    }

    private void checkBlankRequiredFields() {
        checkBlankRate('Lead',        'Phone',     'Phone',     'Lead');
        checkBlankRate('Lead',        'Company',   'Company',   'Lead');
        checkBlankRate('Contact',     'Email',     'Email',     'Contact');
        checkBlankRate('Opportunity', 'AccountId', 'linked Account', 'Opportunity');
    }

    // objectApiName and fieldApiName are always trusted, hardcoded literals — no injection risk
    @SuppressWarnings('PMD.ApexSoqlInjection')
    private void checkBlankRate(
        String objectApiName,
        String fieldApiName,
        String fieldLabel,
        String objectLabel
    ) {
        Integer total = Database.countQuery('SELECT COUNT() FROM ' + objectApiName);
        if (total == 0) return;

        Integer nonBlank = Database.countQuery(
            'SELECT COUNT() FROM ' + objectApiName + ' WHERE ' + fieldApiName + ' != null'
        );
        Decimal blankRate = 1.0 - ((Decimal) nonBlank / total);

        if (blankRate > BLANK_RATE_THRESHOLD) {
            Integer blankCount = total - nonBlank;
            addFinding(
                blankRate > 0.40 ? 'High' : 'Medium',
                'Missing Data',
                (blankRate * 100).setScale(0) + '% of ' + objectLabel + ' records missing ' + fieldLabel,
                blankCount + ' of ' + total + ' ' + objectLabel + ' records (' +
                (blankRate * 100).setScale(1) + '%) have a blank ' + fieldLabel + '. ' +
                'Missing data reduces CRM effectiveness, prevents accurate segmentation, ' +
                'and limits automation that relies on this field.',
                'Add a Validation Rule to require ' + fieldLabel + ' on new records. ' +
                'Run a report filtered to blank ' + fieldApiName + ' and launch a data cleanup ' +
                'campaign to backfill historical records.',
                objectApiName + '.' + fieldApiName,
                'Field'
            );
        }
    }

    private void checkStaleRecords() {
        Date opportunityCutoff = System.today().addDays(-STALE_OPPORTUNITY_DAYS);
        Integer staleOpps = [
            SELECT COUNT() FROM Opportunity
            WHERE IsClosed = false AND CloseDate < :opportunityCutoff
        ];

        if (staleOpps > 0) {
            addFinding(
                'Medium',
                'Stale Records',
                staleOpps + ' open Opportunity/ies with a past Close Date',
                staleOpps + ' open Opportunities have a Close Date more than ' +
                STALE_OPPORTUNITY_DAYS + ' days in the past. These likely represent ' +
                'abandoned or forgotten deals that inflate pipeline figures and distort forecasting.',
                'Review these Opportunities with sales management. Close or update them. ' +
                'Consider a Scheduled Report that alerts on overdue close dates, ' +
                'or a Flow that automatically marks Opportunities as Closed Lost after a defined period.',
                'Opportunity',
                'Object'
            );
        }

        Date caseCutoff = System.today().addDays(-STALE_CASE_DAYS);
        Integer staleCases = [
            SELECT COUNT() FROM Case
            WHERE IsClosed = false AND LastModifiedDate < :caseCutoff
        ];

        if (staleCases > 0) {
            addFinding(
                'Low',
                'Stale Records',
                staleCases + ' open Case(s) inactive for ' + STALE_CASE_DAYS + ' days',
                staleCases + ' open Cases have not been modified in over ' + STALE_CASE_DAYS + ' days. ' +
                'Unresolved stale cases may indicate support process breakdowns, abandoned tickets, ' +
                'or issues that were resolved outside Salesforce without being closed.',
                'Review stale Cases with the service team. Close cases that are resolved. ' +
                'Consider a Case Escalation Rule or Entitlement Process to prevent cases from ' +
                'going dormant without follow-up.',
                'Case',
                'Object'
            );
        }
    }
}
