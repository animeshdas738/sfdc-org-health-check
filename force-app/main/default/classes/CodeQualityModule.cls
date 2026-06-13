public class CodeQualityModule extends OrgHealthBaseModule {

    private static final Integer COVERAGE_THRESHOLD  = 75;
    private static final Integer MAX_CLASS_CHARS      = 50000; // ~1 000 lines at 50 chars/line
    private static final Integer MIN_API_VERSION      = 50;    // Summer '20

    public CodeQualityModule(Id scanId) {
        super(scanId, OrgHealthConstants.MODULE_CODE_QUALITY);
    }

    protected override void runChecks() {
        checkTestCoverage();
        checkSoqlInLoops();
        checkLargeClasses();
        checkDeprecatedApiUsage();
        checkDocumentation();
    }

    private void checkTestCoverage() {
        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT ApexClassOrTrigger.Name, ApexClassOrTrigger.Type, ' +
                'NumLinesCovered, NumLinesUncovered ' +
                'FROM ApexCodeCoverageAggregate'
            )
        );

        List<String> zeroCoverage = new List<String>();
        List<String> lowCoverage  = new List<String>();

        for (Map<String, Object> row : rows) {
            Integer covered   = toInt(row.get('NumLinesCovered'));
            Integer uncovered = toInt(row.get('NumLinesUncovered'));
            Integer total     = covered + uncovered;
            if (total <= 10) continue; // skip trivially small or empty classes

            Decimal pct = ((Decimal) covered / total) * 100;
            Map<String, Object> classRef = (Map<String, Object>) row.get('ApexClassOrTrigger');
            String name = classRef != null ? str(classRef, 'Name') : 'Unknown';

            if (pct == 0) {
                zeroCoverage.add(name);
            } else if (pct < COVERAGE_THRESHOLD) {
                lowCoverage.add(name + ' (' + pct.setScale(0) + '%)');
            }
        }

        if (!zeroCoverage.isEmpty()) {
            addFinding(
                'High',
                'Test Coverage',
                zeroCoverage.size() + ' class(es)/trigger(s) have zero test coverage',
                'The following Apex components have no automated test coverage: ' +
                joinCapped(zeroCoverage, 10) +
                ' Zero-coverage code cannot be deployed to a production org.',
                'Write unit tests for each of these classes. A good starting point is to test ' +
                'every public method with at least one happy-path and one failure-path test case. ' +
                'Use @TestSetup to share fixture data and keep tests fast.',
                'Org',
                'ApexClass'
            );
        }

        if (!lowCoverage.isEmpty()) {
            addFinding(
                'Medium',
                'Test Coverage',
                lowCoverage.size() + ' class(es)/trigger(s) below ' + COVERAGE_THRESHOLD + '% coverage',
                'The following Apex components are below the ' + COVERAGE_THRESHOLD + '% threshold: ' +
                joinCapped(lowCoverage, 10),
                'Add tests that cover branching logic, error handling, and governor-limit edge cases. ' +
                'Use System.assert() to validate outputs, not just to hit lines.',
                'Org',
                'ApexClass'
            );
        }
    }

    private void checkSoqlInLoops() {
        // Fetches class bodies and does a line-by-line heuristic scan.
        // Limited to 200 classes to stay within heap limits.
        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT Name, Body ' +
                'FROM ApexClass ' +
                'WHERE Status = \'Active\' AND NamespacePrefix = null ' +
                'AND LengthWithoutComments < 100000 ' +
                'ORDER BY LengthWithoutComments ASC ' +
                'LIMIT 200'
            )
        );

        List<String> violators = new List<String>();
        for (Map<String, Object> row : rows) {
            if (containsSoqlInLoop(str(row, 'Body'))) {
                violators.add(str(row, 'Name'));
            }
        }

        if (!violators.isEmpty()) {
            addFinding(
                'High',
                'Code Anti-patterns',
                violators.size() + ' class(es) may contain SOQL inside a loop',
                'The following classes appear to execute SOQL inside a for or while loop: ' +
                joinCapped(violators, 15) +
                ' Each iteration consumes one of the 100 SOQL queries per-transaction governor limit.',
                'Collect all IDs before the loop, execute a single bulkified query outside the loop, ' +
                'and use a Map to look up values inside the loop. Example: ' +
                'Map<Id, Account> m = new Map<Id, Account>([SELECT Id, Name FROM Account WHERE Id IN :ids]);',
                String.join(violators, ', '),
                'ApexClass'
            );
        }
    }

    private Boolean containsSoqlInLoop(String body) {
        if (String.isBlank(body)) return false;
        List<String> lines = body.split('\n');
        Integer loopDepth = 0;
        Boolean inLoop    = false;
        for (String raw : lines) {
            String line = raw.trim().toLowerCase();
            // Detect loop start
            if (line.startsWith('for ') || line.startsWith('for(') ||
                line.startsWith('while ') || line.startsWith('while(')) {
                inLoop    = true;
                loopDepth = 0;
            }
            if (inLoop) {
                loopDepth += charCount(raw, '{') - charCount(raw, '}');
                if (line.contains('[select') || line.contains('database.query(') ||
                    line.contains('database.countquery(')) {
                    return true;
                }
                // Exit loop detection when all braces are closed
                if (loopDepth <= 0) inLoop = false;
            }
        }
        return false;
    }

    private Integer charCount(String s, String ch) {
        return s.length() - s.replace(ch, '').length();
    }

    private void checkLargeClasses() {
        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT Name, LengthWithoutComments ' +
                'FROM ApexClass ' +
                'WHERE Status = \'Active\' AND NamespacePrefix = null ' +
                'AND LengthWithoutComments > ' + MAX_CLASS_CHARS +
                ' ORDER BY LengthWithoutComments DESC ' +
                'LIMIT 50'
            )
        );

        if (rows.isEmpty()) return;

        List<String> largeClasses = new List<String>();
        for (Map<String, Object> row : rows) {
            Integer chars = toInt(row.get('LengthWithoutComments'));
            largeClasses.add(str(row, 'Name') + ' (~' + (chars / 50) + ' lines)');
        }

        addFinding(
            'Low',
            'Code Maintainability',
            largeClasses.size() + ' class(es) are very large',
            'The following classes exceed ~' + (MAX_CLASS_CHARS / 50) + ' estimated lines: ' +
            joinCapped(largeClasses, 10) +
            ' Large classes are harder to review, test, and maintain and typically signal ' +
            'missing separation of concerns.',
            'Break large classes into focused service, selector, and domain classes. ' +
            'Adopt a layered architecture (FFLIB or similar) to distribute responsibility. ' +
            'As a rule of thumb, a class doing more than one thing should be split.',
            String.join(largeClasses, ', '),
            'ApexClass'
        );
    }

    private void checkDeprecatedApiUsage() {
        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT Name, ApiVersion ' +
                'FROM ApexClass ' +
                'WHERE Status = \'Active\' AND NamespacePrefix = null ' +
                'AND ApiVersion < ' + MIN_API_VERSION + '.0'
            )
        );

        if (rows.isEmpty()) return;

        List<String> oldClasses = new List<String>();
        for (Map<String, Object> row : rows) {
            oldClasses.add(str(row, 'Name') + ' (v' + str(row, 'ApiVersion') + ')');
        }

        addFinding(
            'Medium',
            'Deprecated API Versions',
            oldClasses.size() + ' class(es) on API version < ' + MIN_API_VERSION + '.0',
            'The following Apex classes are compiled against API v' + MIN_API_VERSION +
            ' (Summer \'20) or older: ' + joinCapped(oldClasses, 10) +
            ' Old API versions may use deprecated platform behaviours and miss improvements ' +
            'such as null-safe operators and enhanced governor limit reporting.',
            'Update the apiVersion in each class\'s -meta.xml file to v66.0 (or the current release). ' +
            'Use the Salesforce CLI: sf project retrieve start --metadata ApexClass, then update the ' +
            'meta.xml files in bulk and redeploy. Review release notes for breaking changes per version.',
            'Org',
            'ApexClass'
        );
    }

    private void checkDocumentation() {
        List<Map<String, Object>> rows = extractRecords(
            toolingQuery(
                'SELECT Name, Body ' +
                'FROM ApexClass ' +
                'WHERE Status = \'Active\' AND NamespacePrefix = null ' +
                'AND LengthWithoutComments < 100000 ' +
                'ORDER BY LengthWithoutComments ASC ' +
                'LIMIT 200'
            )
        );

        List<String> noDoc      = new List<String>();
        List<String> partialDoc = new List<String>();

        for (Map<String, Object> row : rows) {
            String body = str(row, 'Body');
            String name = str(row, 'Name');
            if (String.isBlank(body)) continue;
            // Test classes don't require ApexDoc
            if (body.toLowerCase().contains('@istest')) continue;

            Integer apexDocCount    = countOccurrences(body, '/**');
            Integer publicMethods   = countPublicMethods(body);

            if (apexDocCount == 0) {
                noDoc.add(name);
            } else if (publicMethods > 0 && apexDocCount < publicMethods) {
                partialDoc.add(
                    name + ' (' + apexDocCount + ' comment' +
                    (apexDocCount == 1 ? '' : 's') +
                    ' for ' + publicMethods + ' public method' +
                    (publicMethods == 1 ? '' : 's') + ')'
                );
            }
        }

        if (!noDoc.isEmpty()) {
            addFinding(
                'Medium',
                'Code Documentation',
                noDoc.size() + ' class(es) have no ApexDoc comments',
                'The following Apex classes contain no ApexDoc (/** … */) blocks at all: ' +
                joinCapped(noDoc, 15) +
                ' Undocumented code increases onboarding time and makes maintenance error-prone.',
                'Add a class-level /** @description … */ block and a method-level comment for every ' +
                'public or global method. Use ApexDoc tags: @description, @param, @return, @throws. ' +
                'VS Code with the Salesforce Extension Pack can generate stubs automatically.',
                'Org',
                'ApexClass'
            );
        }

        if (!partialDoc.isEmpty()) {
            addFinding(
                'Low',
                'Code Documentation',
                partialDoc.size() + ' class(es) have fewer ApexDoc comments than public methods',
                'The following classes appear to have undocumented public methods: ' +
                joinCapped(partialDoc, 10) +
                ' Each public or global method should have a /** … */ comment describing its purpose, ' +
                'parameters, and return value.',
                'Review each flagged class and add missing ApexDoc blocks. Prioritise methods that are ' +
                'called by other classes, exposed via @AuraEnabled, or part of a public API contract.',
                'Org',
                'ApexClass'
            );
        }
    }

    // Counts non-overlapping occurrences of a fixed substring.
    private Integer countOccurrences(String text, String sub) {
        if (String.isBlank(text) || String.isBlank(sub)) return 0;
        return (text.length() - text.replace(sub, '').length()) / sub.length();
    }

    // Counts public/global method signatures (lines starting with public/global
    // that contain parentheses, excluding class, interface, and enum declarations).
    private Integer countPublicMethods(String body) {
        Integer count = 0;
        for (String raw : body.split('\n')) {
            String line = raw.trim().toLowerCase();
            if (!(line.startsWith('public ') || line.startsWith('global '))) continue;
            if (!line.contains('(')) continue;
            if (line.startsWith('public class')  || line.startsWith('global class'))  continue;
            if (line.startsWith('public interface') || line.startsWith('global interface')) continue;
            if (line.startsWith('public enum')   || line.startsWith('global enum'))   continue;
            count++;
        }
        return count;
    }

    private String joinCapped(List<String> items, Integer cap) {
        if (items.isEmpty()) return '';
        List<String> shown = items.size() <= cap ? items : firstN(items, cap);
        String result = String.join(shown, ', ');
        if (items.size() > cap) {
            result += ' … and ' + (items.size() - cap) + ' more.';
        }
        return result;
    }
}
