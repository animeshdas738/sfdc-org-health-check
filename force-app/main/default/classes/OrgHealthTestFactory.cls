/**
 * Test utility factory for creating standard test data.
 * Provides methods to create scans, module scores, and findings for testing.
 */
@isTest
public class OrgHealthTestFactory {

    /**
     * Creates a HealthScan__c record for testing.
     * @param status Scan status (In Progress, Complete, Failed)
     * @param triggerType Manual, Scheduled, or API
     * @return New HealthScan__c record (not inserted)
     */
    public static HealthScan__c createScan(String status, String triggerType) {
        return new HealthScan__c(
            Status__c = status,
            TriggerType__c = triggerType,
            ScanStartTime__c = System.now(),
            ScanEndTime__c = status != 'In Progress' ? System.now() : null,
            OrgId__c = UserInfo.getOrganizationId(),
            OrgName__c = UserInfo.getOrganizationName(),
            TriggeredBy__c = UserInfo.getUserId(),
            CompositeScore__c = 80,
            Grade__c = 'B'
        );
    }

    /**
     * Creates a HealthModuleScore__c record.
     * @param scanId Parent scan ID
     * @param moduleName Module name (Security, CodeQuality, etc.)
     * @param score Score 0–100
     * @param status Module status (Complete, Failed, Skipped)
     * @return New HealthModuleScore__c record (not inserted)
     */
    public static HealthModuleScore__c createModuleScore(Id scanId, String moduleName, Decimal score, String status) {
        // Ensure status is a valid value (Complete, Failed, Skipped)
        String validStatus = status;
        if (status == 'In Progress' || status == null) {
            validStatus = 'Complete';
        }

        return new HealthModuleScore__c(
            HealthScan__c = scanId,
            Module__c = moduleName,
            Score__c = score,
            Weight__c = 20,
            Status__c = validStatus,
            DurationMs__c = 1500,
            CriticalCount__c = 1,
            HighCount__c = 2,
            MediumCount__c = 3
        );
    }

    /**
     * Creates a HealthFinding__c record.
     * @param scanId Parent scan ID
     * @param moduleScoreId Parent module score ID
     * @param severity Critical, High, Medium, Low, Info
     * @param title Finding title
     * @return New HealthFinding__c record (not inserted)
     */
    public static HealthFinding__c createFinding(Id scanId, Id moduleScoreId, String severity, String title) {
        return new HealthFinding__c(
            HealthScan__c = scanId,
            HealthModuleScore__c = moduleScoreId,
            Module__c = 'Security',
            Severity__c = severity,
            Category__c = 'Test Category',
            Title__c = title,
            Description__c = 'Test description',
            Recommendation__c = 'Test recommendation',
            AffectedComponent__c = 'TestClass',
            AffectedComponentType__c = 'ApexClass',
            FindingKey__c = 'Security__TestCategory__TestClass'
        );
    }

    /**
     * Creates test CMT records for module configuration.
     * Must be called in test setup.
     */
    public static void createTestModuleConfigs() {
        // This would require test data setup via SObject creation
        // since CMT is typically deployed, not created in tests
    }

    /**
     * Creates a test Custom Setting override.
     * @param configKey Module or checkpoint key
     * @param isEnabled Enabled state
     * @return New OrgHealthConfigOverride__c record (not inserted)
     */
    public static OrgHealthConfigOverride__c createConfigOverride(String configKey, Boolean isEnabled) {
        return new OrgHealthConfigOverride__c(
            Name = configKey,
            IsEnabled__c = isEnabled
        );
    }
}
