import { LightningElement, api, track } from 'lwc';

const SEVERITIES = ['Critical', 'High', 'Medium', 'Low', 'Info'];
const SEVERITY_ORDER = { Critical: 0, High: 1, Medium: 2, Low: 3, Info: 4 };

export default class OrgHealthFindingsList extends LightningElement {
    @api findings = [];
    @api isLoading = false;
    @track activeFilter = 'All';
    @track expandedIds = {};

    get totalCount() {
        return this.findings?.length || 0;
    }

    get filterOptions() {
        const counts = {};
        (this.findings || []).forEach(f => {
            counts[f.Severity__c] = (counts[f.Severity__c] || 0) + 1;
        });
        const options = [{ value: 'All', label: `All (${this.totalCount})` }];
        SEVERITIES.forEach(sev => {
            if (counts[sev]) {
                options.push({ value: sev, label: `${sev} (${counts[sev]})` });
            }
        });
        return options.map(opt => ({
            ...opt,
            btnClass: `filter-btn filter-btn_${opt.value.toLowerCase()}${this.activeFilter === opt.value ? ' filter-btn_active' : ''}`
        }));
    }

    get filteredFindings() {
        const all = this.findings || [];
        if (this.activeFilter === 'All') return all;
        return all.filter(f => f.Severity__c === this.activeFilter);
    }

    get displayFindings() {
        const sorted = [...this.filteredFindings].sort(
            (a, b) => (SEVERITY_ORDER[a.Severity__c] || 99) - (SEVERITY_ORDER[b.Severity__c] || 99)
        );
        return sorted.map(f => ({
            ...f,
            isExpanded: !!this.expandedIds[f.Id],
            badgeClass: `severity-badge severity-badge_${(f.Severity__c || '').toLowerCase()}`,
            chevronIcon: this.expandedIds[f.Id] ? 'utility:chevronup' : 'utility:chevrondown'
        }));
    }

    get hasFindings() {
        return this.filteredFindings.length > 0;
    }

    get emptyMessage() {
        return this.activeFilter === 'All'
            ? 'No findings — your org looks clean!'
            : `No ${this.activeFilter} findings.`;
    }

    handleFilterClick(event) {
        this.activeFilter = event.currentTarget.dataset.severity;
    }

    handleFindingClick(event) {
        // Stop clicks on the detail panel from toggling collapse
        const id = event.currentTarget.dataset.id;
        this.expandedIds = { ...this.expandedIds, [id]: !this.expandedIds[id] };
    }

    handleDetailClick(event) {
        event.stopPropagation();
    }
}
