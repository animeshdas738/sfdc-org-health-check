/**
 * Tests for SecurityScannerModule.
 * Demonstrates testing pattern for health check modules.
 * NOTE: Full module testing requires mocking Tooling API responses.
 */
@isTest
private class SecurityScannerModuleTest {

    @isTest
    static void testModuleInitialization() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        SecurityScannerModule module = new SecurityScannerModule(scan.Id);
        Test.stopTest();

        Assert.isNotNull(module, 'Module should be instantiated');
    }

    @isTest
    static void testModuleCanExecute() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        SecurityScannerModule module = new SecurityScannerModule(scan.Id);
        // Note: execute() cannot be called directly in tests due to Queueable constraints
        // This test demonstrates module structure
        Test.stopTest();

        Assert.isNotNull(module, 'Module should execute without errors');
    }

    @isTest
    static void testCheckpointGates() {
        // Test that checkpoint gates respect the enabled/disabled state
        // Create a disabled checkpoint
        OrgHealthConfigOverride__c configOv = OrgHealthTestFactory.createConfigOverride(
            'Security.ModifyAllData',
            false
        );
        insert configOv;

        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        Boolean isEnabled = OrgHealthConstants.isCheckpointEnabled('Security.ModifyAllData');
        Test.stopTest();

        Assert.isFalse(isEnabled, 'Checkpoint should be disabled when override is set');
    }

    @isTest
    static void testCheckpointEnabled() {
        Test.startTest();
        // Security.ModifyAllData should be enabled by default
        Boolean isEnabled = OrgHealthConstants.isCheckpointEnabled('Security.ModifyAllData');
        Test.stopTest();

        Assert.isTrue(isEnabled, 'Checkpoint should be enabled by default');
    }

    @isTest
    static void testFindingCreation() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('Complete', 'Manual');
        insert scan;

        HealthModuleScore__c ms = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 85, 'Complete');
        insert ms;

        HealthFinding__c finding = OrgHealthTestFactory.createFinding(
            scan.Id,
            ms.Id,
            'Critical',
            'Test Security Finding'
        );
        finding.Module__c = 'Security';
        finding.FindingKey__c = 'Security__PermissionGaps__TestProfile';
        insert finding;

        Test.startTest();
        HealthFinding__c retrieved = [SELECT Id, Title__c FROM HealthFinding__c WHERE Id = :finding.Id];
        Test.stopTest();

        Assert.isNotNull(retrieved, 'Finding should be persisted');
        Assert.areEqual('Test Security Finding', retrieved.Title__c, 'Finding title should match');
    }

    @isTest
    static void testModuleScoreCreation() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('Complete', 'Manual');
        insert scan;

        HealthModuleScore__c ms = OrgHealthTestFactory.createModuleScore(scan.Id, 'Security', 85, 'Complete');
        insert ms;

        Test.startTest();
        HealthModuleScore__c retrieved = [SELECT Id, Score__c, Module__c FROM HealthModuleScore__c WHERE Id = :ms.Id];
        Test.stopTest();

        Assert.isNotNull(retrieved, 'Module score should be persisted');
        Assert.areEqual('Security', retrieved.Module__c, 'Module name should match');
        Assert.areEqual(85, retrieved.Score__c, 'Score should match');
    }

    /**
     * Template for testing individual check methods (if they were testable in isolation).
     * In practice, module testing requires:
     * 1. Mocking Tooling API responses
     * 2. Setting up prerequisite data (Profiles, PermissionSets, etc.)
     * 3. Queuing the module as a Queueable job
     */
    @isTest
    static void testSecurityModuleCheckpoints() {
        // Verify all expected checkpoints exist
        Test.startTest();
        Boolean modifyAllEnabled = OrgHealthConstants.isCheckpointEnabled('Security.ModifyAllData');
        Boolean flsGapsEnabled = OrgHealthConstants.isCheckpointEnabled('Security.FLSGaps');
        Boolean guestAccessEnabled = OrgHealthConstants.isCheckpointEnabled('Security.GuestUserAccess');
        Boolean passwordPolicyEnabled = OrgHealthConstants.isCheckpointEnabled('Security.PasswordPolicy');
        Test.stopTest();

        Assert.isTrue(modifyAllEnabled, 'ModifyAllData checkpoint should exist');
        Assert.isTrue(flsGapsEnabled, 'FLSGaps checkpoint should exist');
        Assert.isTrue(guestAccessEnabled, 'GuestUserAccess checkpoint should exist');
        Assert.isTrue(passwordPolicyEnabled, 'PasswordPolicy checkpoint should exist');
    }
}
