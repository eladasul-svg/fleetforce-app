import { LightningElement, api } from 'lwc';
import getContext from '@salesforce/apex/AssistantController.getContext';
import startSession from '@salesforce/apex/AssistantController.startSession';
import getSession from '@salesforce/apex/AssistantController.getSession';
import sendMessage from '@salesforce/apex/AssistantController.sendMessage';
import continueTurn from '@salesforce/apex/AssistantController.continueTurn';
import resolveProposal from '@salesforce/apex/AssistantController.resolveProposal';
import saveApiKey from '@salesforce/apex/AssistantController.saveApiKey';
import clearUserKey from '@salesforce/apex/AssistantController.clearUserKey';

const MAX_AUTO_STEPS = 12;
const SUGGESTIONS = [
    'Which fleet assets are overdue for service?',
    'How many vehicles are available at each branch?',
    'Summarize the open reservations for this week',
    'Show the most recent high-severity telemetry violations'
];

export default class FleetforceAssistant extends LightningElement {
    @api recordId;
    @api objectApiName;

    view = 'loading';
    context;
    sessionId;
    sessionTitle;
    messages = [];
    draft = '';
    busy = false;
    statusText = '';
    error;
    keyNotice;
    userKey = '';
    orgKey = '';
    savingKey = false;

    _keyCounter = 0;
    _scrollPending = false;

    connectedCallback() {
        this.loadContext();
    }

    renderedCallback() {
        if (this._scrollPending) {
            const list = this.template.querySelector('.messages');
            if (list) {
                list.scrollTop = list.scrollHeight;
            }
            this._scrollPending = false;
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Derived state
    // ---------------------------------------------------------------------------------------------

    get connected() {
        return !!(this.context && (this.context.orgConfigured || this.context.userConfigured));
    }
    get isLoading() {
        return this.view === 'loading';
    }
    get isConnectView() {
        return this.view === 'connect';
    }
    get isChatView() {
        return this.view === 'chat';
    }
    get userConfigured() {
        return !!(this.context && this.context.userConfigured);
    }
    get canManageOrg() {
        return !!(this.context && this.context.canManageOrg);
    }
    get orgBadge() {
        return this.context && this.context.orgConfigured ? 'Connected' : 'Not configured';
    }
    get orgBadgeClass() {
        return this.context && this.context.orgConfigured ? 'badge on' : 'badge';
    }
    get userBadge() {
        return this.context && this.context.userConfigured ? 'Connected' : 'Not set';
    }
    get userBadgeClass() {
        return this.context && this.context.userConfigured ? 'badge on' : 'badge';
    }
    get orgSaveLabel() {
        return this.context && this.context.orgConfigured ? 'Replace organization key' : 'Save organization key';
    }
    get userSaveLabel() {
        return this.context && this.context.userConfigured ? 'Replace my key' : 'Save my key';
    }
    get firstName() {
        return (this.context && this.context.userName) || 'there';
    }
    get headerTitle() {
        return this.sessionTitle || 'FleetForce Assistant';
    }
    get contextLabel() {
        if (!this.recordId || !this.objectApiName) {
            return '';
        }
        const label = this.objectApiName.replace(/^[a-z0-9]+__/i, '').replace(/__c$/i, '').replace(/_/g, ' ');
        return `About this ${label} record`;
    }
    get hasSessions() {
        return !!(this.context && this.context.sessions && this.context.sessions.length);
    }
    get sessionMenuItems() {
        return ((this.context && this.context.sessions) || []).map((s) => ({ label: s.title, value: s.id }));
    }
    get suggestions() {
        return SUGGESTIONS.map((text, key) => ({ key, text }));
    }
    get showSuggestions() {
        return this.messages.length === 0 && !this.busy;
    }
    get sendDisabled() {
        return this.busy || !this.draft.trim();
    }
    get renderedMessages() {
        return this.messages.map((m) => ({
            ...m,
            isUser: m.role === 'user',
            isAssistant: m.role === 'assistant',
            isSteps: m.role === 'steps',
            isProposal: m.role === 'proposal',
            isOutcome: m.role === 'outcome',
            isError: m.role === 'error',
            rowClass: `row ${m.role}`
        }));
    }

    // ---------------------------------------------------------------------------------------------
    // Connection
    // ---------------------------------------------------------------------------------------------

    async loadContext() {
        try {
            this.context = await getContext();
            this.error = undefined;
            if (this.view === 'loading') {
                this.view = this.connected ? 'chat' : 'connect';
            }
        } catch (e) {
            this.error = this.messageOf(e);
            if (this.view === 'loading') {
                this.view = 'connect';
            }
        }
    }

    handleOpenConnection() {
        this.keyNotice = undefined;
        this.view = 'connect';
    }
    handleBackToChat() {
        if (this.connected) {
            this.view = 'chat';
        }
    }
    handleUserKey(event) {
        this.userKey = event.target.value;
    }
    handleOrgKey(event) {
        this.orgKey = event.target.value;
    }
    handleSaveUserKey() {
        this.saveKey('user', this.userKey);
    }
    handleSaveOrgKey() {
        this.saveKey('org', this.orgKey);
    }

    async handleClearUserKey() {
        this.savingKey = true;
        this.error = undefined;
        this.keyNotice = undefined;
        try {
            await clearUserKey();
            this.keyNotice = 'Your key was removed.';
            await this.loadContext();
        } catch (e) {
            this.error = this.messageOf(e);
        } finally {
            this.savingKey = false;
        }
    }

    async saveKey(scope, apiKey) {
        if (!apiKey || !apiKey.trim()) {
            this.error = 'Paste an API key first.';
            return;
        }
        this.savingKey = true;
        this.error = undefined;
        this.keyNotice = undefined;
        try {
            await saveApiKey({ scope, apiKey: apiKey.trim() });
            this.userKey = '';
            this.orgKey = '';
            this.keyNotice = scope === 'org' ? 'Organization key saved.' : 'Your key is saved.';
            await this.loadContext();
        } catch (e) {
            this.error = this.messageOf(e);
        } finally {
            this.savingKey = false;
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Sessions
    // ---------------------------------------------------------------------------------------------

    handleNewChat() {
        this.sessionId = undefined;
        this.sessionTitle = undefined;
        this.messages = [];
        this.error = undefined;
    }

    async handleSessionSelect(event) {
        const id = event.detail.value;
        if (!id || id === this.sessionId || this.busy) {
            return;
        }
        this.busy = true;
        this.statusText = 'Loading conversation…';
        try {
            const d = await getSession({ sessionId: id });
            this.sessionId = d.id;
            this.sessionTitle = d.title;
            this.messages = [];
            (d.messages || []).forEach((m) => {
                if (m.role === 'user') {
                    this.push({ role: 'user', text: m.text });
                } else {
                    this.push({ role: 'assistant', html: mdToHtml(m.text) });
                }
            });
            if (d.proposal) {
                this.push({ role: 'proposal', proposal: this.viewProposal(d.proposal) });
            } else if (d.awaitingContinue) {
                this.statusText = 'Working…';
                const r = await continueTurn({ sessionId: this.sessionId });
                await this.handleTurn(r, 0);
            }
        } catch (e) {
            this.push({ role: 'error', text: this.messageOf(e) });
        } finally {
            this.busy = false;
            this.statusText = '';
        }
    }

    async ensureSession() {
        if (!this.sessionId) {
            this.sessionId = await startSession({ recordId: this.recordId, objectApiName: this.objectApiName });
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Chat
    // ---------------------------------------------------------------------------------------------

    handleDraft(event) {
        this.draft = event.target.value;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.send();
        }
    }

    handleSuggestion(event) {
        this.draft = event.currentTarget.dataset.text;
        this.send();
    }

    async send() {
        const text = this.draft.trim();
        if (!text || this.busy) {
            return;
        }
        this.draft = '';
        const composer = this.template.querySelector('textarea.input');
        if (composer) {
            composer.value = '';
        }
        this.error = undefined;
        this.push({ role: 'user', text });
        this.busy = true;
        this.statusText = 'Thinking…';
        try {
            await this.ensureSession();
            const r = await sendMessage({ sessionId: this.sessionId, text });
            if (!this.sessionTitle) {
                this.sessionTitle = text.length > 80 ? `${text.slice(0, 77)}…` : text;
            }
            await this.handleTurn(r, 0);
        } catch (e) {
            this.push({ role: 'error', text: this.messageOf(e) });
        } finally {
            this.busy = false;
            this.statusText = '';
            this.loadContext();
        }
    }

    async handleTurn(r, depth) {
        if (r.steps && r.steps.length) {
            this.push({ role: 'steps', steps: r.steps.map((text, key) => ({ key, text })) });
        }
        if (r.outcome && r.outcome.success && r.outcome.recordId) {
            this.push({
                role: 'outcome',
                text: `${r.outcome.action === 'create' ? 'Created' : 'Updated'} ${r.outcome.objectLabel} — open record`,
                url: `/${r.outcome.recordId}`
            });
        }
        if (r.text) {
            const text = r.truncated ? `${r.text}\n\n*(The answer was cut off — ask me to continue.)*` : r.text;
            this.push({ role: 'assistant', html: mdToHtml(text) });
        }
        if (r.kind === 'proposal') {
            this.push({ role: 'proposal', proposal: this.viewProposal(r.proposal) });
            return;
        }
        if (r.kind === 'tool_step') {
            if (depth >= MAX_AUTO_STEPS) {
                this.push({ role: 'error', text: 'I stopped after many steps. Ask me to continue if you want me to keep going.' });
                return;
            }
            this.statusText = 'Working…';
            const next = await continueTurn({ sessionId: this.sessionId });
            await this.handleTurn(next, depth + 1);
        }
    }

    viewProposal(p) {
        const isUpdate = p.action === 'update';
        const name = p.recordName ? ` "${p.recordName}"` : '';
        return {
            title: `${isUpdate ? 'Update' : 'Create'} ${p.objectLabel}${name}`,
            reason: p.reason,
            isUpdate,
            changes: (p.changes || []).map((c, key) => ({
                key,
                label: c.label,
                current: formatValue(c.current),
                proposed: formatValue(c.proposed)
            })),
            decided: false,
            decisionLabel: ''
        };
    }

    async handleDecision(event) {
        const approved = event.currentTarget.dataset.decision === 'approve';
        const key = Number(event.currentTarget.dataset.key);
        if (this.busy) {
            return;
        }
        this.messages = this.messages.map((m) =>
            m.key === key
                ? { ...m, proposal: { ...m.proposal, decided: true, decisionLabel: approved ? 'Approved' : 'Declined' } }
                : m
        );
        this.busy = true;
        this.statusText = approved ? 'Applying the change…' : 'Letting the assistant know…';
        try {
            const r = await resolveProposal({ sessionId: this.sessionId, approved, comment: '' });
            await this.handleTurn(r, 0);
        } catch (e) {
            this.push({ role: 'error', text: this.messageOf(e) });
        } finally {
            this.busy = false;
            this.statusText = '';
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    push(message) {
        this._keyCounter += 1;
        this.messages = [...this.messages, { key: this._keyCounter, ...message }];
        this._scrollPending = true;
    }

    messageOf(e) {
        if (e && e.body && e.body.message) {
            return e.body.message;
        }
        if (e && e.message) {
            return e.message;
        }
        return 'Something went wrong. Please try again.';
    }
}

function formatValue(v) {
    if (v === null || v === undefined || v === '') {
        return '—';
    }
    if (typeof v === 'boolean') {
        return v ? 'Yes' : 'No';
    }
    if (typeof v === 'object') {
        return JSON.stringify(v);
    }
    return String(v);
}

// ---------------------------------------------------------------------------------------------
// Minimal markdown -> HTML for lightning-formatted-rich-text (which sanitizes the result).
// ---------------------------------------------------------------------------------------------

function escapeHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function inline(s) {
    return s
        .replace(/`([^`]+)`/g, '<code>$1</code>')
        .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
        .replace(/(^|[^*\w])\*([^*\n]+)\*(?!\w)/g, '$1<em>$2</em>')
        .replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+|\/[^)\s]*)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
}

function mdToHtml(md) {
    const lines = escapeHtml(md || '').split('\n');
    const out = [];
    let para = [];
    let listTag = null;
    let inCode = false;
    let code = [];
    let table = [];

    const flushPara = () => {
        if (para.length) {
            out.push(`<p>${para.map(inline).join('<br/>')}</p>`);
            para = [];
        }
    };
    const closeList = () => {
        if (listTag) {
            out.push(`</${listTag}>`);
            listTag = null;
        }
    };
    const flushTable = () => {
        if (!table.length) {
            return;
        }
        const rows = table
            .map((l) => l.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => inline(c.trim())))
            .filter((cells) => !cells.every((c) => /^:?-{2,}:?$/.test(c)));
        if (rows.length) {
            const head = `<thead><tr>${rows[0].map((c) => `<th>${c}</th>`).join('')}</tr></thead>`;
            const body = rows
                .slice(1)
                .map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join('')}</tr>`)
                .join('');
            out.push(`<table>${head}<tbody>${body}</tbody></table>`);
        }
        table = [];
    };

    lines.forEach((line) => {
        if (line.trim().startsWith('```')) {
            flushPara();
            closeList();
            flushTable();
            if (inCode) {
                out.push(`<pre>${code.join('\n')}</pre>`);
                code = [];
            }
            inCode = !inCode;
            return;
        }
        if (inCode) {
            code.push(line);
            return;
        }
        if (/^\s*\|/.test(line)) {
            flushPara();
            closeList();
            table.push(line);
            return;
        }
        flushTable();

        const heading = line.match(/^(#{1,6})\s+(.*)$/);
        if (heading) {
            flushPara();
            closeList();
            const level = Math.min(heading[1].length + 2, 6);
            out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
            return;
        }
        const bullet = line.match(/^\s*[-*•]\s+(.*)$/);
        const numbered = line.match(/^\s*\d+[.)]\s+(.*)$/);
        if (bullet || numbered) {
            flushPara();
            const tag = bullet ? 'ul' : 'ol';
            if (listTag !== tag) {
                closeList();
                out.push(`<${tag}>`);
                listTag = tag;
            }
            out.push(`<li>${inline((bullet || numbered)[1])}</li>`);
            return;
        }
        if (!line.trim()) {
            flushPara();
            closeList();
            return;
        }
        closeList();
        para.push(line);
    });

    flushPara();
    closeList();
    flushTable();
    if (inCode && code.length) {
        out.push(`<pre>${code.join('\n')}</pre>`);
    }
    return out.join('');
}
