/**
 * Metadata health checks for stale or over-complex configuration artifacts.
 * Detects unused custom fields/objects, high validation rule counts, and deprecated field types.
 */
public class MetadataAnalyserModule extends OrgHealthBaseModule {

    private static final Integer STALE_FIELD_DAYS   = 730;
    private static final Integer STALE_OBJECT_DAYS  = 1095;
    private static final Integer MAX_VLOOKUP_FIELDS = 25;

    /**
     * Constructs the Metadata module executor.
     * @param scanId The HealthScan__c ID to write module results to
     */
    public MetadataAnalyserModule(Id scanId) {
        super(scanId, OrgHealthConstants.MODULE_METADATA);
    }

    protected override void runChecks() {
        checkUnusedCustomFields();
        checkUnusedCustomObjects();
        checkOrphanedLayouts();
        checkDeprecatedFieldTypes();
    }

    private String customEntityIdInClause() {
        List<Map<String, Object>> entities = extractRecords(
            toolingQuery(
                'SELECT DurableId FROM EntityDefinition ' +
                'WHERE QualifiedApiName LIKE \'%__c\' ' +
                'AND IsDeprecatedAndHidden = false ' +
                'LIMIT 200'
            )
        );
        if (entities.isEmpty()) return null;
        List<String> quoted = new List<String>();
        for (Map<String, Object> e : entities) {
            quoted.add('\'' + str(e, 'DurableId') + '\'');
        }
        return String.join(quoted, ',');
    }

    private void checkUnusedCustomFields() {
        if (!OrgHealthConstants.isCheckpointEnabled('Metadata.StaleCustomFields')) return;
        String entityIdIn = customEntityIdInClause();
        if (entityIdIn == null) return;

        String cutoff = Datetime.newInstance(
            System.today().addDays(-STALE_FIELD_DAYS), Time.newInstance(0,0,0,0)
        ).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT QualifiedApiName, EntityDefinition.QualifiedApiName, LastModifiedDate ' +
                'FROM FieldDefinition ' +
                'WHERE EntityDefinitionId IN (' + entityIdIn + ') ' +
                'AND QualifiedApiName LIKE \'%__c\' ' +
                'AND LastModifiedDate < ' + cutoff +
                ' LIMIT 200'
            )
        );

        if (rows.isEmpty()) return;

        Map<String, Integer> countByObject = new Map<String, Integer>();
        for (Map<String, Object> row : rows) {
            Map<String, Object> entityDef = (Map<String, Object>) row.get('EntityDefinition');
            String objName = entityDef != null ? str(entityDef, 'QualifiedApiName') : 'Unknown';
            countByObject.put(objName, (countByObject.get(objName) ?? 0) + 1);
        }

        for (String obj : countByObject.keySet()) {
            Integer count = countByObject.get(obj);
            if (count >= 5) {
                addFinding(
                    'Low',
                    'Stale Metadata',
                    obj + ' has ' + count + ' custom field(s) untouched for 2+ years',
                    count + ' custom fields on ' + obj + ' have not been modified in over 2 years. ' +
                    'Stale fields may be unused, consume metadata API limits, and confuse developers ' +
                    'browsing the object manager.',
                    'Review these fields with the business and field usage reports. Delete fields that ' +
                    'have no data (run a report grouped by the field to verify). Add a description to ' +
                    'retained fields so their purpose is clear. Use Field History Tracking to detect ' +
                    'fields that are never populated.',
                    obj,
                    'Object'
                );
            }
        }
    }

    private void checkUnusedCustomObjects() {
        if (!OrgHealthConstants.isCheckpointEnabled('Metadata.StaleCustomObjects')) return;
        String cutoff = Datetime.newInstance(
            System.today().addDays(-STALE_OBJECT_DAYS), Time.newInstance(0,0,0,0)
        ).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT QualifiedApiName, Label, LastModifiedDate ' +
                'FROM EntityDefinition ' +
                'WHERE QualifiedApiName LIKE \'%__c\' ' +
                'AND IsDeprecatedAndHidden = false ' +
                'AND LastModifiedDate < ' + cutoff +
                ' ORDER BY LastModifiedDate ASC ' +
                'LIMIT 100'
            )
        );

        if (rows.size() < 3) return;

        List<String> staleObjects = new List<String>();
        for (Map<String, Object> row : rows) {
            staleObjects.add(str(row, 'Label') + ' (' + str(row, 'QualifiedApiName') + ')');
        }

        addFinding(
            'Info',
            'Stale Metadata',
            staleObjects.size() + ' custom object(s) not modified in 3+ years',
            formatComponentListWithIntro(
                'The following custom objects have not been modified in over 3 years',
                staleObjects
            ) + '\n\nThese objects may be legacy data stores no longer in active use.',
            'Run record count reports for each object. Objects with zero or near-zero records ' +
            'and no references in active Flows or Apex classes are candidates for deletion. ' +
            'Archive the data first if needed.',
            'Org',
            'Object'
        );
    }

    private void checkOrphanedLayouts() {
        if (!OrgHealthConstants.isCheckpointEnabled('Metadata.HighValidationRuleCount')) return;
        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT Id, EntityDefinition.QualifiedApiName, Active ' +
                'FROM ValidationRule ' +
                'WHERE Active = true'
            )
        );

        if (rows.isEmpty()) return;

        Map<String, Integer> countByObject = new Map<String, Integer>();
        for (Map<String, Object> row : rows) {
            Map<String, Object> entityDef = (Map<String, Object>) row.get('EntityDefinition');
            String obj = entityDef != null ? str(entityDef, 'QualifiedApiName') : 'Unknown';
            countByObject.put(obj, (countByObject.get(obj) ?? 0) + 1);
        }

        for (String obj : countByObject.keySet()) {
            Integer count = countByObject.get(obj);
            if (count > MAX_VLOOKUP_FIELDS) {
                addFinding(
                    'Low',
                    'Metadata Complexity',
                    obj + ' has ' + count + ' active Validation Rules',
                    obj + ' has ' + count + ' active Validation Rules. A high number of validation ' +
                    'rules makes data entry error-prone for users, slows DML operations, and ' +
                    'creates a maintenance burden when requirements change.',
                    'Audit these rules with the business. Consolidate rules that check similar ' +
                    'conditions using OR logic. Remove rules that are no longer aligned to current ' +
                    'business requirements. Document each rule\'s purpose in its Description field.',
                    obj,
                    'Object'
                );
            }
        }
    }

    private void checkDeprecatedFieldTypes() {
        if (!OrgHealthConstants.isCheckpointEnabled('Metadata.ShortTextAreaFields')) return;
        String entityIdIn = customEntityIdInClause();
        if (entityIdIn == null) return;

        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT QualifiedApiName, EntityDefinition.QualifiedApiName ' +
                'FROM FieldDefinition ' +
                'WHERE EntityDefinitionId IN (' + entityIdIn + ') ' +
                'AND QualifiedApiName LIKE \'%__c\' ' +
                'AND DataType = \'TextArea\' ' +
                'LIMIT 200'
            )
        );

        if (rows.isEmpty()) return;

        Map<String, List<String>> byObject = new Map<String, List<String>>();
        for (Map<String, Object> row : rows) {
            Map<String, Object> entityDef = (Map<String, Object>) row.get('EntityDefinition');
            String obj   = entityDef != null ? str(entityDef, 'QualifiedApiName') : 'Unknown';
            String field = str(row, 'QualifiedApiName');
            if (!byObject.containsKey(obj)) byObject.put(obj, new List<String>());
            byObject.get(obj).add(field);
        }

        for (String obj : byObject.keySet()) {
            List<String> fields = byObject.get(obj);
            addFinding(
                'Low',
                'Field Type Optimisation',
                obj + ' has ' + fields.size() + ' short TextArea field(s)',
                fields.size() + ' fields on ' + obj + ' use the TextArea type, which limits ' +
                'content to 255 characters:\n\n' +
                formatComponentList(fields),
                'Consider converting these fields to Long Text Area (up to 131,072 chars) or ' +
                'Rich Text Area if users need formatted content. Verify existing data is within ' +
                'the new length before converting — data truncation can occur if you downgrade.',
                obj,
                'Object'
            );
        }
    }
}
