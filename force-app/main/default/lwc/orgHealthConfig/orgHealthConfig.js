/**
 * Admin configuration UI for health check modules and checkpoints.
 * Left panel: module list with enable/disable toggles.
 * Right panel: checkpoint table for selected module with individual toggles.
 * Changes are staged locally and committed in one Save call.
 */

import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getConfig  from '@salesforce/apex/OrgHealthConfigController.getConfig';
import saveConfig from '@salesforce/apex/OrgHealthConfigController.saveConfig';

export default class OrgHealthConfig extends LightningElement {

    @track modules          = [];
    @track selectedModuleKey = null;
    @track isLoading        = true;

    _pendingChanges = {};   // configKey → Boolean

    /**
     * Lifecycle hook: fetch config on component initialization.
     */
    connectedCallback() {
        this._loadConfig();
    }

    // ── Data load ────────────────────────────────────────────────────────────

    /**
     * Fetches the full config (modules + checkpoints + overrides) from the controller.
     * @private
     */
    async _loadConfig() {
        this.isLoading = true;
        try {
            const raw = await getConfig();
            this.modules = raw.map(m => this._decorateModule(m));
            if (this.modules.length > 0 && !this.selectedModuleKey) {
                this.selectedModuleKey = this.modules[0].moduleKey;
            }
        } catch (e) {
            this._toast('Error loading configuration', this._errorMessage(e), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Augments a module with UI state: applies pending changes, computes selection class,
     * counts enabled checkpoints.
     * @private
     * @param {Object} m - The module object from the controller
     * @returns {Object} Decorated module with UI properties
     */
    _decorateModule(m) {
        const checkpoints = (m.checkpoints || []).map(cp => ({
            ...cp,
            isEnabled: this._pendingChanges.hasOwnProperty(cp.checkpointKey)
                ? this._pendingChanges[cp.checkpointKey]
                : cp.isEnabled
        }));
        const isEnabled = this._pendingChanges.hasOwnProperty(m.moduleKey)
            ? this._pendingChanges[m.moduleKey]
            : m.isEnabled;
        const isSelected = m.moduleKey === this.selectedModuleKey;
        return {
            ...m,
            isEnabled,
            isDisabled: !isEnabled,
            checkpoints,
            listItemClass: 'module-item' + (isSelected ? ' module-item_selected' : ''),
            enabledCheckpointCount: checkpoints.filter(cp => cp.isEnabled).length,
            totalCheckpointCount: checkpoints.length
        };
    }

    // ── Getters ───────────────────────────────────────────────────────────────

    get selectedModule() {
        return this.modules.find(m => m.moduleKey === this.selectedModuleKey) || null;
    }

    get hasPendingChanges() {
        return Object.keys(this._pendingChanges).length > 0;
    }

    get saveDisabled() {
        return !this.hasPendingChanges;
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    /**
     * Event handler: select a module to display its checkpoints in the right panel.
     * @private
     */
    handleModuleSelect(evt) {
        this.selectedModuleKey = evt.currentTarget.dataset.moduleKey;
        this.modules = this.modules.map(m => ({
            ...m,
            listItemClass: 'module-item' + (m.moduleKey === this.selectedModuleKey ? ' module-item_selected' : '')
        }));
    }

    /**
     * Event handler: a module or checkpoint toggle was changed.
     * Stages the change in _pendingChanges (no server call yet).
     * @private
     */
    handleToggle(evt) {
        const configKey = evt.target.dataset.configKey;
        const isEnabled = evt.target.checked;
        this._pendingChanges[configKey] = isEnabled;
        this.modules = this.modules.map(m => this._decorateModule(m));
    }

    /**
     * Event handler: commit all pending changes to the server.
     * Calls saveConfig() and shows a toast notification on success/error.
     * Clears pending changes and reloads config on success.
     * @private
     */
    async handleSave() {
        if (!this.hasPendingChanges) return;
        this.isLoading = true;
        try {
            const changes = Object.entries(this._pendingChanges).map(([configKey, enabled]) => ({
                configKey,
                isEnabled: enabled
            }));
            await saveConfig({ changes });
            this._pendingChanges = {};
            this._toast('Configuration saved', 'Your changes have been applied and will take effect on the next scan.', 'success');
            await this._loadConfig();
        } catch (e) {
            this._toast('Save failed', this._errorMessage(e), 'error');
            this.isLoading = false;
        }
    }

    /**
     * Prevents an event from bubbling (used when clicking toggles in the module list).
     * @private
     */
    stopPropagation(evt) {
        evt.stopPropagation();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Dispatches a toast notification to the user.
     * @private
     * @param {string} title - Toast title
     * @param {string} message - Toast message
     * @param {string} variant - success, error, warning, or info
     */
    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    /**
     * Extracts a user-friendly error message from a Salesforce API error object.
     * @private
     * @param {Object} e - Error object (may have body.message)
     * @returns {string} Error message or fallback text
     */
    _errorMessage(e) {
        return (e && e.body && e.body.message) ? e.body.message : 'An unexpected error occurred.';
    }
}
