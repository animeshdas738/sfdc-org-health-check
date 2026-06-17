/**
 * Tests for OrgHealthModuleFactory.
 * Covers module instantiation and factory logic.
 */
@isTest
private class OrgHealthModuleFactoryTest {

    @isTest
    static void testCreateSecurityModule() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        OrgHealthBaseModule module = OrgHealthModuleFactory.create('Security', scan.Id);
        Test.stopTest();

        Assert.isNotNull(module, 'Should create a module instance');
        Assert.isInstanceOfType(module, SecurityScannerModule.class, 'Should create SecurityScannerModule');
    }

    @isTest
    static void testCreateAutomationModule() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        OrgHealthBaseModule module = OrgHealthModuleFactory.create('Automation', scan.Id);
        Test.stopTest();

        Assert.isNotNull(module, 'Should create a module instance');
        Assert.isInstanceOfType(module, AutomationAuditorModule.class, 'Should create AutomationAuditorModule');
    }

    @isTest
    static void testCreateCodeQualityModule() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        OrgHealthBaseModule module = OrgHealthModuleFactory.create('CodeQuality', scan.Id);
        Test.stopTest();

        Assert.isNotNull(module, 'Should create a module instance');
        Assert.isInstanceOfType(module, CodeQualityModule.class, 'Should create CodeQualityModule');
    }

    @isTest
    static void testCreateMetadataModule() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        OrgHealthBaseModule module = OrgHealthModuleFactory.create('Metadata', scan.Id);
        Test.stopTest();

        Assert.isNotNull(module, 'Should create a module instance');
        Assert.isInstanceOfType(module, MetadataAnalyserModule.class, 'Should create MetadataAnalyserModule');
    }

    @isTest
    static void testCreateDataQualityModule() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        OrgHealthBaseModule module = OrgHealthModuleFactory.create('DataQuality', scan.Id);
        Test.stopTest();

        Assert.isNotNull(module, 'Should create a module instance');
        Assert.isInstanceOfType(module, DataQualityModule.class, 'Should create DataQualityModule');
    }

    @isTest
    static void testCreateGovernorLimitsModule() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        OrgHealthBaseModule module = OrgHealthModuleFactory.create('GovernorLimits', scan.Id);
        Test.stopTest();

        Assert.isNotNull(module, 'Should create a module instance');
        Assert.isInstanceOfType(module, GovernorLimitsModule.class, 'Should create GovernorLimitsModule');
    }

    @isTest
    static void testCreateThrowsExceptionForUnknownModule() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        Exception ex = null;
        try {
            OrgHealthModuleFactory.create('UnknownModule', scan.Id);
        } catch (Exception e) {
            ex = e;
        }
        Test.stopTest();

        Assert.isNotNull(ex, 'Should throw exception for unknown module');
        Assert.isInstanceOfType(ex, OrgHealthBaseModule.OrgHealthException.class, 'Should throw OrgHealthException');
    }

    @isTest
    static void testCreateThrowsExceptionForNullModuleName() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        Exception ex = null;
        try {
            OrgHealthModuleFactory.create(null, scan.Id);
        } catch (Exception e) {
            ex = e;
        }
        Test.stopTest();

        Assert.isNotNull(ex, 'Should throw exception for null module name');
    }

    @isTest
    static void testAllModulesCanBeInstantiated() {
        HealthScan__c scan = OrgHealthTestFactory.createScan('In Progress', 'Manual');
        insert scan;

        Test.startTest();
        for (String moduleName : OrgHealthConstants.MODULE_CHAIN) {
            OrgHealthBaseModule module = OrgHealthModuleFactory.create(moduleName, scan.Id);
            Assert.isNotNull(module, 'Should create ' + moduleName + ' module');
        }
        Test.stopTest();
    }
}
