import { LightningElement, api } from 'lwc';

const MODULE_LABELS = {
    Security: 'Security',
    Automation: 'Automation',
    CodeQuality: 'Code Quality',
    Metadata: 'Metadata',
    DataQuality: 'Data Quality',
    GovernorLimits: 'Governor Limits'
};

export default class OrgHealthModuleScores extends LightningElement {
    @api modules = [];

    get hasModules() {
        return this.modules && this.modules.length > 0;
    }

    get formattedModules() {
        return (this.modules || []).map(m => {
            const score = m.Score__c || 0;
            const colorKey = score >= 75 ? 'green' : score >= 60 ? 'amber' : 'red';
            return {
                ...m,
                label: MODULE_LABELS[m.Module__c] || m.Module__c,
                barStyle: `width: ${Math.round(score)}%`,
                barClass: `bar-fill bar-fill_${colorKey}`,
                scoreClass: `score-pill score-pill_${colorKey}`,
                scoreDisplay: Math.round(score),
                weightDisplay: m.Weight__c != null ? Math.round(m.Weight__c) : 0
            };
        });
    }
}
