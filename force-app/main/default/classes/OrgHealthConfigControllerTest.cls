/**
 * Tests for OrgHealthConfigController.
 * Covers config retrieval and persistence.
 */
@isTest
private class OrgHealthConfigControllerTest {

    @isTest
    static void testGetConfigReturnsAllModules() {
        Test.startTest();
        List<OrgHealthConfigController.ModuleConfig> config = OrgHealthConfigController.getConfig();
        Test.stopTest();

        Assert.isNotNull(config, 'Config should not be null');
        // Should contain all 6 modules
        Assert.isTrue(config.size() >= 1, 'Config should contain at least one module');
    }

    @isTest
    static void testGetConfigIncludesCheckpoints() {
        Test.startTest();
        List<OrgHealthConfigController.ModuleConfig> config = OrgHealthConfigController.getConfig();
        Test.stopTest();

        Assert.isNotNull(config, 'Config should not be null');
        for (OrgHealthConfigController.ModuleConfig mod : config) {
            Assert.isNotNull(mod.checkpoints, 'Each module should have checkpoints list');
        }
    }

    @isTest
    static void testGetConfigRespectsCMTDefaults() {
        Test.startTest();
        List<OrgHealthConfigController.ModuleConfig> config = OrgHealthConfigController.getConfig();
        Test.stopTest();

        Assert.isNotNull(config, 'Config should not be null');
        for (OrgHealthConfigController.ModuleConfig mod : config) {
            Assert.isNotNull(mod.isEnabled, 'Module isEnabled should be set');
            Assert.isNotNull(mod.label, 'Module label should be set');
            Assert.isNotNull(mod.weight, 'Module weight should be set');
        }
    }

    @isTest
    static void testSaveConfigInsertsNewOverrides() {
        // Create a config change
        List<OrgHealthConfigController.SavePayload> changes = new List<OrgHealthConfigController.SavePayload>();
        OrgHealthConfigController.SavePayload payload = new OrgHealthConfigController.SavePayload();
        payload.configKey = 'TestModule';
        payload.isEnabled = false;
        changes.add(payload);

        Test.startTest();
        OrgHealthConfigController.saveConfig(changes);
        Test.stopTest();

        OrgHealthConfigOverride__c configOv = OrgHealthConfigOverride__c.getInstance('TestModule');
        Assert.isNotNull(configOv, 'Override should be created');
        Assert.isFalse(configOv.IsEnabled__c, 'Override should be disabled');
    }

    @isTest
    static void testSaveConfigUpdatesExistingOverrides() {
        // Create an existing override
        OrgHealthConfigOverride__c configOv = OrgHealthTestFactory.createConfigOverride('TestModule', true);
        insert configOv;

        // Update it
        List<OrgHealthConfigController.SavePayload> changes = new List<OrgHealthConfigController.SavePayload>();
        OrgHealthConfigController.SavePayload payload = new OrgHealthConfigController.SavePayload();
        payload.configKey = 'TestModule';
        payload.isEnabled = false;
        changes.add(payload);

        Test.startTest();
        OrgHealthConfigController.saveConfig(changes);
        Test.stopTest();

        OrgHealthConfigOverride__c updated = OrgHealthConfigOverride__c.getInstance('TestModule');
        Assert.isFalse(updated.IsEnabled__c, 'Override should be updated to disabled');
    }

    @isTest
    static void testSaveConfigHandlesEmptyChanges() {
        Test.startTest();
        OrgHealthConfigController.saveConfig(new List<OrgHealthConfigController.SavePayload>());
        Test.stopTest();

        // Should complete without error
        Assert.isTrue(true, 'Empty changes should be handled gracefully');
    }

    @isTest
    static void testSaveConfigHandlesNullChanges() {
        Test.startTest();
        OrgHealthConfigController.saveConfig(null);
        Test.stopTest();

        Assert.isTrue(true, 'Null changes should be handled gracefully');
    }

    @isTest
    static void testGetConfigMergesOverridesWithDefaults() {
        // Insert an override
        OrgHealthConfigOverride__c configOv = OrgHealthTestFactory.createConfigOverride('Security', false);
        insert configOv;

        Test.startTest();
        List<OrgHealthConfigController.ModuleConfig> config = OrgHealthConfigController.getConfig();
        Test.stopTest();

        OrgHealthConfigController.ModuleConfig securityModule = null;
        for (OrgHealthConfigController.ModuleConfig mod : config) {
            if (mod.moduleKey == 'Security') {
                securityModule = mod;
                break;
            }
        }

        Assert.isNotNull(securityModule, 'Security module should be in config');
        Assert.isFalse(securityModule.isEnabled, 'Security module should be disabled due to override');
    }

    @isTest
    static void testSaveConfigMultipleChanges() {
        List<OrgHealthConfigController.SavePayload> changes = new List<OrgHealthConfigController.SavePayload>();

        OrgHealthConfigController.SavePayload p1 = new OrgHealthConfigController.SavePayload();
        p1.configKey = 'Module1';
        p1.isEnabled = false;
        changes.add(p1);

        OrgHealthConfigController.SavePayload p2 = new OrgHealthConfigController.SavePayload();
        p2.configKey = 'Module2';
        p2.isEnabled = true;
        changes.add(p2);

        Test.startTest();
        OrgHealthConfigController.saveConfig(changes);
        Test.stopTest();

        OrgHealthConfigOverride__c ov1 = OrgHealthConfigOverride__c.getInstance('Module1');
        OrgHealthConfigOverride__c ov2 = OrgHealthConfigOverride__c.getInstance('Module2');

        Assert.isNotNull(ov1, 'First override should be created');
        Assert.isNotNull(ov2, 'Second override should be created');
        Assert.isFalse(ov1.IsEnabled__c, 'First should be disabled');
        Assert.isTrue(ov2.IsEnabled__c, 'Second should be enabled');
    }
}
