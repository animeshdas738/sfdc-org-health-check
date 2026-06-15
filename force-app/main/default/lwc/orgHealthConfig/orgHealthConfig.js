import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getConfig  from '@salesforce/apex/OrgHealthConfigController.getConfig';
import saveConfig from '@salesforce/apex/OrgHealthConfigController.saveConfig';

export default class OrgHealthConfig extends LightningElement {

    @track modules          = [];
    @track selectedModuleKey = null;
    @track isLoading        = true;

    _pendingChanges = {};   // configKey → Boolean

    connectedCallback() {
        this._loadConfig();
    }

    // ── Data load ────────────────────────────────────────────────────────────

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

    handleModuleSelect(evt) {
        this.selectedModuleKey = evt.currentTarget.dataset.moduleKey;
        this.modules = this.modules.map(m => ({
            ...m,
            listItemClass: 'module-item' + (m.moduleKey === this.selectedModuleKey ? ' module-item_selected' : '')
        }));
    }

    handleToggle(evt) {
        const configKey = evt.target.dataset.configKey;
        const isEnabled = evt.target.checked;
        this._pendingChanges[configKey] = isEnabled;
        this.modules = this.modules.map(m => this._decorateModule(m));
    }

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

    stopPropagation(evt) {
        evt.stopPropagation();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _errorMessage(e) {
        return (e && e.body && e.body.message) ? e.body.message : 'An unexpected error occurred.';
    }
}
