/**
 * Factory for instantiating health check module executors by name.
 * Maps module keys (e.g., 'Security', 'CodeQuality') to their corresponding Queueable implementations.
 */
public class OrgHealthModuleFactory {

    /**
     * Creates a module executor instance.
     * @param moduleName The module key (e.g., 'Security', 'Automation', 'CodeQuality')
     * @param scanId The ID of the HealthScan__c being executed
     * @return A new OrgHealthBaseModule subclass instance
     * @throws OrgHealthBaseModule.OrgHealthException if moduleName is not recognized
     */
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
