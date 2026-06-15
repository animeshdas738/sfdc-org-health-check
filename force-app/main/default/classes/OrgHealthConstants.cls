public class OrgHealthConstants {

    public static final String MODULE_SECURITY       = 'Security';
    public static final String MODULE_AUTOMATION     = 'Automation';
    public static final String MODULE_CODE_QUALITY   = 'CodeQuality';
    public static final String MODULE_METADATA       = 'Metadata';
    public static final String MODULE_DATA_QUALITY   = 'DataQuality';
    public static final String MODULE_GOVERNOR_LIMITS = 'GovernorLimits';

    public static final List<String> MODULE_CHAIN = new List<String>{
        MODULE_SECURITY,
        MODULE_AUTOMATION,
        MODULE_CODE_QUALITY,
        MODULE_METADATA,
        MODULE_DATA_QUALITY,
        MODULE_GOVERNOR_LIMITS
    };

    // Lazy-loaded so tests without deployed CMT records can stub the maps
    private static Map<String, OrgHealthModuleConfig__mdt>    moduleConfigs;
    private static Map<String, OrgHealthSeverityConfig__mdt>  severityConfigs;
    private static Map<String, OrgHealthCheckpointConfig__mdt> checkpointConfigs;

    public static Map<String, OrgHealthModuleConfig__mdt> getModuleConfigs() {
        if (moduleConfigs == null) {
            moduleConfigs = new Map<String, OrgHealthModuleConfig__mdt>();
            for (OrgHealthModuleConfig__mdt cfg : [
                SELECT Module__c, Weight__c, IsEnabled__c, DisplayOrder__c
                FROM OrgHealthModuleConfig__mdt
            ]) {
                moduleConfigs.put(cfg.Module__c, cfg);
            }
        }
        return moduleConfigs;
    }

    public static Map<String, OrgHealthSeverityConfig__mdt> getSeverityConfigs() {
        if (severityConfigs == null) {
            severityConfigs = new Map<String, OrgHealthSeverityConfig__mdt>();
            for (OrgHealthSeverityConfig__mdt cfg : [
                SELECT Severity__c, ScoreDeduction__c
                FROM OrgHealthSeverityConfig__mdt
            ]) {
                severityConfigs.put(cfg.Severity__c, cfg);
            }
        }
        return severityConfigs;
    }

    // Exposed for tests so they can inject mock CMT data without a deploy
    @TestVisible
    private static void setModuleConfigs(Map<String, OrgHealthModuleConfig__mdt> mock) {
        moduleConfigs = mock;
    }

    @TestVisible
    private static void setSeverityConfigs(Map<String, OrgHealthSeverityConfig__mdt> mock) {
        severityConfigs = mock;
    }

    public static Map<String, OrgHealthCheckpointConfig__mdt> getCheckpointConfigs() {
        if (checkpointConfigs == null) {
            checkpointConfigs = new Map<String, OrgHealthCheckpointConfig__mdt>();
            for (OrgHealthCheckpointConfig__mdt cfg : [
                SELECT CheckpointKey__c, Module__c, Label, Description__c,
                       IsEnabledByDefault__c, DisplayOrder__c
                FROM OrgHealthCheckpointConfig__mdt
            ]) {
                checkpointConfigs.put(cfg.CheckpointKey__c, cfg);
            }
        }
        return checkpointConfigs;
    }

    /**
     * Returns the effective enabled state for any config key (module name or checkpoint key).
     * Resolution order: OrgHealthConfigOverride__c (admin override) → supplied default.
     */
    public static Boolean isEnabled(String configKey, Boolean defaultValue) {
        OrgHealthConfigOverride__c ov = OrgHealthConfigOverride__c.getInstance(configKey);
        return ov != null ? ov.IsEnabled__c : defaultValue;
    }

    /**
     * Shorthand for checkpoints: looks up the CMT default, then applies any admin override.
     * Falls back to true if no CMT record exists (safe default: run the check).
     */
    public static Boolean isCheckpointEnabled(String checkpointKey) {
        OrgHealthCheckpointConfig__mdt cfg = getCheckpointConfigs().get(checkpointKey);
        Boolean defaultEnabled = cfg != null ? cfg.IsEnabledByDefault__c : true;
        return isEnabled(checkpointKey, defaultEnabled);
    }

    @TestVisible
    private static void setCheckpointConfigs(Map<String, OrgHealthCheckpointConfig__mdt> mock) {
        checkpointConfigs = mock;
    }

    public static String calculateGrade(Decimal score) {
        if (score >= 90) return 'A';
        if (score >= 75) return 'B';
        if (score >= 60) return 'C';
        if (score >= 40) return 'D';
        return 'F';
    }
}
