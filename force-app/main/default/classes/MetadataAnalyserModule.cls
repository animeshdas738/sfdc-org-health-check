public class MetadataAnalyserModule extends OrgHealthBaseModule {

    private static final Integer STALE_FIELD_DAYS   = 730;  // 2 years
    private static final Integer STALE_OBJECT_DAYS  = 1095; // 3 years
    private static final Integer MAX_VLOOKUP_FIELDS = 25;

    public MetadataAnalyserModule(Id scanId) {
        super(scanId, OrgHealthConstants.MODULE_METADATA);
    }

    protected override void runChecks() {
        checkUnusedCustomFields();
        checkUnusedCustomObjects();
        checkOrphanedLayouts();
        checkDeprecatedFieldTypes();
    }

    private void checkUnusedCustomFields() {
        // Fields not modified in 2+ years are candidates for review.
        // Tooling SOQL DateTime literals must be ISO-8601.
        String cutoff = Datetime.newInstance(
            System.today().addDays(-STALE_FIELD_DAYS), Time.newInstance(0,0,0,0)
        ).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT QualifiedApiName, EntityDefinition.QualifiedApiName, LastModifiedDate ' +
                'FROM FieldDefinition ' +
                'WHERE IsCustom = true ' +
                'AND EntityDefinition.IsCustomizable = true ' +
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
        String cutoff = Datetime.newInstance(
            System.today().addDays(-STALE_OBJECT_DAYS), Time.newInstance(0,0,0,0)
        ).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');

        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT QualifiedApiName, Label, LastModifiedDate ' +
                'FROM EntityDefinition ' +
                'WHERE IsCustomizable = true AND IsCustom = true ' +
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
            'The following custom objects have not been modified in over 3 years: ' +
            String.join(staleObjects.size() <= 10 ? staleObjects : firstN(staleObjects, 10), ', ') +
            (staleObjects.size() > 10 ? ' … and ' + (staleObjects.size() - 10) + ' more.' : '.') +
            ' These objects may be legacy data stores no longer in active use.',
            'Run record count reports for each object. Objects with zero or near-zero records ' +
            'and no references in active Flows or Apex classes are candidates for deletion. ' +
            'Archive the data first if needed.',
            'Org',
            'Object'
        );
    }

    private void checkOrphanedLayouts() {
        // Objects with large numbers of validation rules indicate brittle metadata.
        // Each Tooling API VR record has EntityDefinition as a relationship field.
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
        // Short TextArea fields (255-char max, no formatting) are frequently a mistake —
        // developers reach for LongTextArea when data grows beyond 255 chars.
        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT QualifiedApiName, EntityDefinition.QualifiedApiName ' +
                'FROM FieldDefinition ' +
                'WHERE IsCustom = true ' +
                'AND DataType = \'Textarea\' ' +
                'AND EntityDefinition.IsCustomizable = true ' +
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
                'content to 255 characters: ' +
                String.join(fields.size() <= 6 ? fields : firstN(fields, 6), ', ') +
                (fields.size() > 6 ? ' … and ' + (fields.size() - 6) + ' more.' : '.'),
                'Consider converting these fields to Long Text Area (up to 131,072 chars) or ' +
                'Rich Text Area if users need formatted content. Verify existing data is within ' +
                'the new length before converting — data truncation can occur if you downgrade.',
                obj,
                'Object'
            );
        }
    }
}
