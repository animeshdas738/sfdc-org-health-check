import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getLatestScan    from '@salesforce/apex/OrgHealthDashboardController.getLatestScan';
import getScoreTrend    from '@salesforce/apex/OrgHealthDashboardController.getScoreTrend';
import getModuleScores  from '@salesforce/apex/OrgHealthDashboardController.getModuleScores';
import getFindings      from '@salesforce/apex/OrgHealthDashboardController.getFindings';
import triggerScan      from '@salesforce/apex/OrgHealthDashboardController.triggerScan';
import getScanStatus    from '@salesforce/apex/OrgHealthDashboardController.getScanStatus';

const POLL_MS = 3000;

export default class OrgHealthDashboard extends LightningElement {
    // Reactive props that drive wire parameters
    @track latestScanId;
    @track activeScanId;

    // UI state
    @track isScanning = false;
    @track isLoading  = true;
    @track errorMessage;

    // Stored wire result objects (needed for refreshApex)
    _wiredScan;
    _wiredModuleScores;
    _wiredTrend;
    _wiredFindings;
    _pollTimer;

    // ── Wire adapters ──────────────────────────────────────────────────────

    @wire(getLatestScan)
    handleScanWire(result) {
        this._wiredScan = result;
        this.isLoading  = false;
        if (result.data) {
            this.latestScanId = result.data.Id;
            // Resume polling when page loads into an already-running scan
            if (result.data.Status__c === 'In Progress' && !this._pollTimer) {
                this.activeScanId = result.data.Id;
                this.isScanning   = true;
                this._startPolling();
            }
        }
    }

    @wire(getModuleScores, { scanId: '$latestScanId' })
    handleModuleScoresWire(result) {
        this._wiredModuleScores = result;
    }

    @wire(getScoreTrend, { numScans: 10 })
    handleTrendWire(result) {
        this._wiredTrend = result;
    }

    // Wire fires only when latestScanId is set (null suppresses the call)
    // severity: '' → controller returns all findings
    @wire(getFindings, { scanId: '$latestScanId', severity: '' })
    handleFindingsWire(result) {
        this._wiredFindings = result;
    }

    // ── Computed getters ───────────────────────────────────────────────────

    get scan()              { return this._wiredScan?.data; }
    get hasScan()           { return !!this.scan; }
    get moduleScores()      { return this._wiredModuleScores?.data || []; }
    get trendData()         { return this._wiredTrend?.data || []; }
    get hasTrend()          { return this.trendData.length >= 2; }
    get findings()          { return this._wiredFindings?.data || []; }
    get isFindingsLoading() {
        return !!(this.latestScanId && !this._wiredFindings?.data && !this._wiredFindings?.error);
    }

    get scanStatus() { return this.scan?.Status__c || ''; }

    get orgName() { return this.scan?.OrgName__c || ''; }

    get scanButtonLabel() { return this.isScanning ? 'Scanning...' : 'Run New Scan'; }

    get lastScanInfo() {
        if (!this.scan?.ScanStartTime__c) return null;
        const d = new Date(this.scan.ScanStartTime__c);
        return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) +
               ' at ' + d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
    }

    get scanDuration() {
        const s = Math.round(this.scan?.ScanDuration__c || 0);
        if (s === 0) return '--';
        return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`;
    }

    get statusBadgeClass() {
        const st = this.scan?.Status__c;
        if (st === 'Complete')    return 'status-pill status-pill_complete';
        if (st === 'Failed')      return 'status-pill status-pill_failed';
        if (st === 'In Progress') return 'status-pill status-pill_progress';
        return 'status-pill';
    }

    // ── Event handlers ─────────────────────────────────────────────────────

    async handleRunScan() {
        this.isScanning   = true;
        this.errorMessage = null;
        try {
            this.activeScanId = await triggerScan();
            this._startPolling();
        } catch (e) {
            this.errorMessage = e?.body?.message || e?.message || 'Failed to start scan.';
            this.isScanning   = false;
        }
    }

    clearError() {
        this.errorMessage = null;
    }

    // ── Polling ────────────────────────────────────────────────────────────

    _startPolling() {
        this._pollTimer = setInterval(async () => {
            try {
                const status = await getScanStatus({ scanId: this.activeScanId });
                if (status.Status__c !== 'In Progress') {
                    this._stopPolling();
                    this.isScanning = false;
                    // Refresh all cached wire data now that the scan is done
                    await Promise.all([
                        refreshApex(this._wiredScan),
                        refreshApex(this._wiredModuleScores),
                        refreshApex(this._wiredTrend),
                        refreshApex(this._wiredFindings)
                    ]);
                    if (status.Status__c === 'Failed') {
                        this.errorMessage = status.ErrorMessage__c || 'Scan completed with errors.';
                    }
                }
            } catch (e) {
                this._stopPolling();
                this.isScanning   = false;
                this.errorMessage = 'Could not retrieve scan status.';
            }
        }, POLL_MS);
    }

    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    disconnectedCallback() {
        this._stopPolling();
    }
}
