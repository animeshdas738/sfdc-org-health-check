public class OrgHealthModuleFactory {

    public static OrgHealthBaseModule create(String moduleName, Id scanId) {
        switch on moduleName {
            when 'Security'       { return new SecurityScannerModule(scanId);   }
            when 'Automation'     { return new AutomationAuditorModule(scanId); }
            when 'CodeQuality'    { return new CodeQualityModule(scanId);       }
            when 'Metadata'       { return new MetadataAnalyserModule(scanId);  }
            when 'DataQuality'    { return new DataQualityModule(scanId);       }
            when 'GovernorLimits' { return new GovernorLimitsModule(scanId);    }
            when else {
                throw new OrgHealthBaseModule.OrgHealthException(
                    'Unknown module: ' + moduleName
                );
            }
        }
    }
}
