public with sharing class OrgHealthConfigController {

    // ── Wrappers ───────────────────────────────────────────────────────────────

    public class ModuleConfig {
        @AuraEnabled public String            moduleKey;
        @AuraEnabled public String            label;
        @AuraEnabled public Decimal           weight;
        @AuraEnabled public Boolean           isEnabled;
        @AuraEnabled public Integer           displayOrder;
        @AuraEnabled public List<CheckpointConfig> checkpoints;
    }

    public class CheckpointConfig {
        @AuraEnabled public String  checkpointKey;
        @AuraEnabled public String  label;
        @AuraEnabled public String  description;
        @AuraEnabled public Boolean isEnabled;
        @AuraEnabled public Integer displayOrder;
    }

    public class SavePayload {
        @AuraEnabled public String  configKey;
        @AuraEnabled public Boolean isEnabled;
    }

    // ── Read ───────────────────────────────────────────────────────────────────

    /**
     * Returns the full merged config: CMT definitions for modules and checkpoints,
     * overlaid with any admin overrides from OrgHealthConfigOverride__c.
     */
    @AuraEnabled(cacheable=false)
    public static List<ModuleConfig> getConfig() {
        Map<String, OrgHealthModuleConfig__mdt> moduleCmts = new Map<String, OrgHealthModuleConfig__mdt>();
        for (OrgHealthModuleConfig__mdt m : [
            SELECT Label, Module__c, Weight__c, IsEnabled__c, DisplayOrder__c
            FROM OrgHealthModuleConfig__mdt
        ]) {
            moduleCmts.put(m.Module__c, m);
        }

        Map<String, List<OrgHealthCheckpointConfig__mdt>> cpByModule =
            new Map<String, List<OrgHealthCheckpointConfig__mdt>>();
        for (OrgHealthCheckpointConfig__mdt cp : [
            SELECT Label, CheckpointKey__c, Module__c, Description__c,
                   IsEnabledByDefault__c, DisplayOrder__c
            FROM OrgHealthCheckpointConfig__mdt
            ORDER BY Module__c, DisplayOrder__c
        ]) {
            if (!cpByModule.containsKey(cp.Module__c)) {
                cpByModule.put(cp.Module__c, new List<OrgHealthCheckpointConfig__mdt>());
            }
            cpByModule.get(cp.Module__c).add(cp);
        }

        // OrgHealthConfigOverride__c is a List Custom Setting — getAll() is cache-friendly
        Map<String, OrgHealthConfigOverride__c> overrides = OrgHealthConfigOverride__c.getAll();

        List<ModuleConfig> result = new List<ModuleConfig>();
        for (String moduleName : OrgHealthConstants.MODULE_CHAIN) {
            OrgHealthModuleConfig__mdt cfg = moduleCmts.get(moduleName);
            if (cfg == null) continue;

            ModuleConfig mc   = new ModuleConfig();
            mc.moduleKey      = moduleName;
            mc.label          = cfg.Label;
            mc.weight         = cfg.Weight__c;
            mc.displayOrder   = Integer.valueOf(cfg.DisplayOrder__c ?? 0);
            OrgHealthConfigOverride__c modOv = overrides.get(moduleName);
            mc.isEnabled      = modOv != null ? modOv.IsEnabled__c : cfg.IsEnabled__c;

            mc.checkpoints = new List<CheckpointConfig>();
            List<OrgHealthCheckpointConfig__mdt> cps = cpByModule.get(moduleName);
            if (cps != null) {
                for (OrgHealthCheckpointConfig__mdt cp : cps) {
                    CheckpointConfig cc = new CheckpointConfig();
                    cc.checkpointKey  = cp.CheckpointKey__c;
                    cc.label          = cp.Label;
                    cc.description    = cp.Description__c;
                    cc.displayOrder   = Integer.valueOf(cp.DisplayOrder__c ?? 0);
                    OrgHealthConfigOverride__c cpOv = overrides.get(cp.CheckpointKey__c);
                    cc.isEnabled = cpOv != null ? cpOv.IsEnabled__c : cp.IsEnabledByDefault__c;
                    mc.checkpoints.add(cc);
                }
            }
            result.add(mc);
        }
        return result;
    }

    // ── Write ──────────────────────────────────────────────────────────────────

    /**
     * Persists admin toggle choices as OrgHealthConfigOverride__c records.
     * Uses the Name field (= configKey) as the upsert key.
     */
    @AuraEnabled
    public static void saveConfig(List<SavePayload> changes) {
        if (changes == null || changes.isEmpty()) return;

        Map<String, OrgHealthConfigOverride__c> existing = OrgHealthConfigOverride__c.getAll();
        List<OrgHealthConfigOverride__c> toInsert = new List<OrgHealthConfigOverride__c>();
        List<OrgHealthConfigOverride__c> toUpdate = new List<OrgHealthConfigOverride__c>();

        for (SavePayload p : changes) {
            if (String.isBlank(p.configKey)) continue;
            if (existing.containsKey(p.configKey)) {
                OrgHealthConfigOverride__c rec = existing.get(p.configKey);
                rec.IsEnabled__c = p.isEnabled;
                toUpdate.add(rec);
            } else {
                toInsert.add(new OrgHealthConfigOverride__c(
                    Name         = p.configKey,
                    IsEnabled__c = p.isEnabled
                ));
            }
        }

        if (!toInsert.isEmpty()) insert toInsert;
        if (!toUpdate.isEmpty()) update toUpdate;
    }
}
