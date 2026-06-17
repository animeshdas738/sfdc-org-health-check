/**
 * Main org health dashboard.
 * Displays composite health score, module breakdown, score trend, and findings list.
 * Supports running a new scan with real-time per-module progress bars.
 */

import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getLatestScan         from '@salesforce/apex/OrgHealthDashboardController.getLatestScan';
import getScoreTrend         from '@salesforce/apex/OrgHealthDashboardController.getScoreTrend';
import getModuleScores       from '@salesforce/apex/OrgHealthDashboardController.getModuleScores';
import getFindings           from '@salesforce/apex/OrgHealthDashboardController.getFindings';
import triggerScan           from '@salesforce/apex/OrgHealthDashboardController.triggerScan';
import getScanStatus         from '@salesforce/apex/OrgHealthDashboardController.getScanStatus';
import getScanModuleProgress from '@salesforce/apex/OrgHealthDashboardController.getScanModuleProgress';

/** Poll interval (milliseconds) during scan execution. */
const POLL_MS = 3000;

const MODULE_CHAIN = ['Security', 'Automation', 'CodeQuality', 'Metadata', 'DataQuality', 'GovernorLimits'];
const MODULE_LABELS = {
    Security:       'Security Scanner',
    Automation:     'Automation Audit',
    CodeQuality:    'Code Quality',
    Metadata:       'Metadata Analysis',
    DataQuality:    'Data Quality',
    GovernorLimits: 'Governor Limits'
};

export default class OrgHealthDashboard extends LightningElement {
    @track latestScanId;
    @track activeScanId;
    @track isScanning   = false;
    @track isLoading    = true;
    @track errorMessage;
    @track scanModules  = [];

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

    get scanStatus()        { return this.scan?.Status__c || ''; }
    get orgName()           { return this.scan?.OrgName__c || ''; }
    get scanButtonLabel()   { return this.isScanning ? 'Scanning...' : 'Run New Scan'; }

    get showProgressView()  { return this.isScanning; }
    get showDashboard()     { return !this.isScanning && this.hasScan; }
    get showEmptyState()    { return !this.isScanning && !this.hasScan; }

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

    get completedModuleCount() {
        return this.scanModules.filter(m => m.Status__c === 'Complete' || m.Status__c === 'Failed').length;
    }

    get totalModuleCount() { return MODULE_CHAIN.length; }

    get scanModuleRows() {
        const doneMap = new Map();
        for (const m of this.scanModules) {
            doneMap.set(m.Module__c, m.Status__c);
        }
        let inProgressAssigned = false;
        return MODULE_CHAIN.map(name => {
            const doneStatus = doneMap.get(name);
            let rowStatus;
            if (doneStatus) {
                rowStatus = doneStatus;
            } else if (!inProgressAssigned) {
                rowStatus = 'In Progress';
                inProgressAssigned = true;
            } else {
                rowStatus = 'Pending';
            }
            const isComplete   = rowStatus === 'Complete';
            const isFailed     = rowStatus === 'Failed';
            const isInProgress = rowStatus === 'In Progress';
            return {
                key:             name,
                label:           MODULE_LABELS[name] || name,
                statusLabel:     isInProgress ? 'Running' : rowStatus === 'Pending' ? 'Queued' : rowStatus,
                barClass:        'progress-bar' + (
                                     isComplete   ? ' progress-bar_complete'
                                   : isFailed     ? ' progress-bar_failed'
                                   : isInProgress ? ' progress-bar_active'
                                   :                ' progress-bar_pending'
                                 ),
                statusPillClass: 'module-status-pill' + (
                                     isComplete   ? ' pill_complete'
                                   : isFailed     ? ' pill_failed'
                                   : isInProgress ? ' pill_running'
                                   :                ' pill_pending'
                                 )
            };
        });
    }

    // ── Event handlers ─────────────────────────────────────────────────────

    /**
     * Event handler: Run New Scan button clicked.
     * Triggers a scan and starts polling for progress.
     * @async
     */
    async handleRunScan() {
        this.isScanning   = true;
        this.scanModules  = [];
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

    /**
     * Starts a polling interval to monitor scan progress.
     * Fetches status and per-module progress every POLL_MS milliseconds.
     * Stops when Status__c changes from 'In Progress' and refreshes all wired data.
     * @private
     * @async
     */
    _startPolling() {
        this._pollTimer = setInterval(async () => {
            try {
                const [status, modules] = await Promise.all([
                    getScanStatus({ scanId: this.activeScanId }),
                    getScanModuleProgress({ scanId: this.activeScanId })
                ]);
                this.scanModules = modules || [];
                if (status.Status__c !== 'In Progress') {
                    this._stopPolling();
                    this.isScanning = false;
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

    /**
     * Stops the polling interval if active.
     * @private
     */
    _stopPolling() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    /**
     * Lifecycle hook: stop polling if the component is destroyed while a scan is in flight.
     */
    disconnectedCallback() {
        this._stopPolling();
    }
}
