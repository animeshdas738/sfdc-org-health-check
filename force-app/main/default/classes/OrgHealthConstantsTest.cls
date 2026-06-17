/**
 * Tests for OrgHealthConstants.
 * Covers configuration merging and grade calculation.
 */
@isTest
private class OrgHealthConstantsTest {

    @isTest
    static void testGetModuleConfigs() {
        Test.startTest();
        Map<String, OrgHealthModuleConfig__mdt> configs = OrgHealthConstants.getModuleConfigs();
        Test.stopTest();

        Assert.isNotNull(configs, 'Module configs should not be null');
        // Configs are deployed with the package, so size varies by org
        Assert.isTrue(configs.size() > 0, 'Should have at least one module config');
    }

    @isTest
    static void testGetSeverityConfigs() {
        Test.startTest();
        Map<String, OrgHealthSeverityConfig__mdt> configs = OrgHealthConstants.getSeverityConfigs();
        Test.stopTest();

        Assert.isNotNull(configs, 'Severity configs should not be null');
        Assert.isTrue(configs.size() > 0, 'Should have severity configurations');
    }

    @isTest
    static void testIsEnabledReturnsCMTDefaultWhenNoOverride() {
        // Test with a config key that has no override
        Test.startTest();
        Boolean enabled = OrgHealthConstants.isEnabled('NonExistentKey', true);
        Test.stopTest();

        Assert.isTrue(enabled, 'Should return the default value when no override exists');
    }

    @isTest
    static void testIsEnabledReturnsOverrideWhenExists() {
        // Insert an override
        OrgHealthConfigOverride__c configOv = OrgHealthTestFactory.createConfigOverride('TestKey', false);
        insert configOv;

        Test.startTest();
        Boolean enabled = OrgHealthConstants.isEnabled('TestKey', true);
        Test.stopTest();

        Assert.isFalse(enabled, 'Should return the override value when it exists');
    }

    @isTest
    static void testIsEnabledRespectsCMTDefaultFalse() {
        Test.startTest();
        Boolean enabled = OrgHealthConstants.isEnabled('NonExistentKey', false);
        Test.stopTest();

        Assert.isFalse(enabled, 'Should return false when default is false');
    }

    @isTest
    static void testIsCheckpointEnabledReturnsCMTDefault() {
        // This test checks that the method returns true for unknown checkpoints (safe default)
        Test.startTest();
        Boolean enabled = OrgHealthConstants.isCheckpointEnabled('UnknownCheckpoint.Key');
        Test.stopTest();

        Assert.isTrue(enabled, 'Unknown checkpoints should default to enabled (safe default)');
    }

    @isTest
    static void testCalculateGradeA() {
        Test.startTest();
        String grade = OrgHealthConstants.calculateGrade(95);
        Test.stopTest();

        Assert.areEqual('A', grade, 'Score 95 should be grade A');
    }

    @isTest
    static void testCalculateGradeB() {
        Test.startTest();
        String grade = OrgHealthConstants.calculateGrade(80);
        Test.stopTest();

        Assert.areEqual('B', grade, 'Score 80 should be grade B');
    }

    @isTest
    static void testCalculateGradeC() {
        Test.startTest();
        String grade = OrgHealthConstants.calculateGrade(65);
        Test.stopTest();

        Assert.areEqual('C', grade, 'Score 65 should be grade C');
    }

    @isTest
    static void testCalculateGradeD() {
        Test.startTest();
        String grade = OrgHealthConstants.calculateGrade(50);
        Test.stopTest();

        Assert.areEqual('D', grade, 'Score 50 should be grade D');
    }

    @isTest
    static void testCalculateGradeF() {
        Test.startTest();
        String grade = OrgHealthConstants.calculateGrade(30);
        Test.stopTest();

        Assert.areEqual('F', grade, 'Score 30 should be grade F');
    }

    @isTest
    static void testCalculateGradeEdgeCases() {
        Test.startTest();
        String grade90 = OrgHealthConstants.calculateGrade(90);
        String grade75 = OrgHealthConstants.calculateGrade(75);
        String grade60 = OrgHealthConstants.calculateGrade(60);
        String grade40 = OrgHealthConstants.calculateGrade(40);
        Test.stopTest();

        Assert.areEqual('A', grade90, 'Score 90 should be grade A');
        Assert.areEqual('B', grade75, 'Score 75 should be grade B');
        Assert.areEqual('C', grade60, 'Score 60 should be grade C');
        Assert.areEqual('D', grade40, 'Score 40 should be grade D');
    }

    @isTest
    static void testModuleChainOrder() {
        Test.startTest();
        List<String> chain = OrgHealthConstants.MODULE_CHAIN;
        Test.stopTest();

        Assert.isTrue(chain.size() >= 6, 'Module chain should have at least 6 modules');
        Assert.areEqual('Security', chain[0], 'First module should be Security');
        Assert.areEqual('Automation', chain[1], 'Second module should be Automation');
    }

    @isTest
    static void testConstantsAreNotNull() {
        Test.startTest();
        String security = OrgHealthConstants.MODULE_SECURITY;
        String automation = OrgHealthConstants.MODULE_AUTOMATION;
        String codeQuality = OrgHealthConstants.MODULE_CODE_QUALITY;
        String metadata = OrgHealthConstants.MODULE_METADATA;
        String dataQuality = OrgHealthConstants.MODULE_DATA_QUALITY;
        String governorLimits = OrgHealthConstants.MODULE_GOVERNOR_LIMITS;
        Test.stopTest();

        Assert.isNotNull(security, 'Security constant should be defined');
        Assert.isNotNull(automation, 'Automation constant should be defined');
        Assert.isNotNull(codeQuality, 'CodeQuality constant should be defined');
        Assert.isNotNull(metadata, 'Metadata constant should be defined');
        Assert.isNotNull(dataQuality, 'DataQuality constant should be defined');
        Assert.isNotNull(governorLimits, 'GovernorLimits constant should be defined');
    }
}
