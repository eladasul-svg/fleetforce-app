import { LightningElement } from 'lwc';
import BRAND from '@salesforce/resourceUrl/FleetForceBrand';
import getDrivers from '@salesforce/apex/DriverAppController.getDrivers';
import getDashboard from '@salesforce/apex/DriverAppController.getDashboard';
import startTrip from '@salesforce/apex/DriverAppController.startTrip';
import endTrip from '@salesforce/apex/DriverAppController.endTrip';
import reportIssue from '@salesforce/apex/DriverAppController.reportIssue';
import logFuel from '@salesforce/apex/DriverAppController.logFuel';
import attachPhoto from '@salesforce/apex/DriverAppController.attachPhoto';

const CHECKS = [
    { key: 'tires', label: 'Tires and wheels' },
    { key: 'lights', label: 'Lights and indicators' },
    { key: 'fluids', label: 'Fluids / charge port' },
    { key: 'brakes', label: 'Brakes feel normal' },
    { key: 'glass', label: 'Windshield and mirrors' },
    { key: 'clean', label: 'Interior clean and tidy' }
];
const PRIORITIES = ['Low', 'Medium', 'High', 'Critical'];
const ISSUE_CATEGORIES = [
    { value: 'Corrective Repair', label: 'Something is broken' },
    { value: 'Inspection', label: 'Needs an inspection' },
    { value: 'Warranty', label: 'Warranty / recall' },
    { value: 'Other', label: 'Something else' }
];
const MAX_PHOTOS = 3;
// Demo build: these drivers have a story in the seed data (scripts/apex/seed_driver_app.apex), so they lead the picker.
const FEATURED_DRIVERS = ['Chloe Bennett', 'Hannah Lindqvist', 'Carlos Gomez'];

const WEEKDAY = new Intl.DateTimeFormat('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
const WHEN = new Intl.DateTimeFormat('en-GB', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
const CLOCK = new Intl.DateTimeFormat('en-GB', { hour: '2-digit', minute: '2-digit' });
const dateText = (v) => (v ? WEEKDAY.format(new Date(v.length === 10 ? `${v}T12:00:00` : v)) : '');
const whenText = (v) => (v ? WHEN.format(new Date(v)) : '');
const number = (n) => (n == null ? '–' : Math.round(n).toLocaleString('en-US'));
const money = (n) => (n == null ? '' : `$${Number(n).toFixed(2)}`);

function daysText(days) {
    if (days == null) return '';
    if (days < 0) return `expired ${-days} d ago`;
    if (days === 0) return 'expires today';
    return `${days} d left`;
}
function daysClass(days, warnAt = 30) {
    if (days == null) return 'chip';
    if (days < 0) return 'chip chip--bad';
    return days <= warnAt ? 'chip chip--warn' : 'chip chip--ok';
}

/** Resize a photo on the device before upload (long edge 1280 px, JPEG) so uploads stay small on mobile data. */
function shrinkImage(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onerror = reject;
        reader.onload = () => {
            const img = new Image();
            img.onerror = reject;
            img.onload = () => {
                const scale = Math.min(1, 1280 / Math.max(img.width, img.height));
                const canvas = document.createElement('canvas');
                canvas.width = Math.round(img.width * scale);
                canvas.height = Math.round(img.height * scale);
                canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
                const dataUrl = canvas.toDataURL('image/jpeg', 0.72);
                resolve({ dataUrl, base64: dataUrl.split(',')[1] });
            };
            img.src = reader.result;
        };
        reader.readAsDataURL(file);
    });
}

export default class DriverApp extends LightningElement {
    drivers = [];
    driverId;
    dash;
    loading = true;
    error;
    view = 'home';
    sheet; // pretrip | endtrip | issue | fuel | notices
    busy = false;
    sheetError;
    toast;

    // forms
    checks = {};
    odometer = '';
    energy = 50;
    notes = '';
    damage = false;
    issueCategory = 'Corrective Repair';
    issuePriority = 'Medium';
    fuelVolume = '';
    fuelCost = '';
    fuelStation = '';
    fuelFull = true;
    photos = [];

    _toastTimer;

    connectedCallback() {
        this.init();
    }

    disconnectedCallback() {
        clearTimeout(this._toastTimer);
    }

    async init() {
        try {
            const all = await getDrivers();
            const rank = (d) => {
                const i = FEATURED_DRIVERS.indexOf(d.name);
                return i === -1 ? FEATURED_DRIVERS.length : i;
            };
            this.drivers = all.map((d, i) => ({ d, i })).sort((a, b) => rank(a.d) - rank(b.d) || a.i - b.i).map((x) => x.d);
            if (this.drivers.length) {
                this.driverId = this.drivers[0].id;
                await this.load();
            } else {
                this.loading = false;
            }
        } catch (e) {
            this.fail(e);
        }
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            this.dash = await getDashboard({ driverId: this.driverId });
        } catch (e) {
            this.fail(e);
        } finally {
            this.loading = false;
        }
    }

    fail(e) {
        this.loading = false;
        this.error = (e && e.body && e.body.message) || 'Something went wrong. Please try again.';
    }

    showToast(message) {
        this.toast = message;
        clearTimeout(this._toastTimer);
        this._toastTimer = setTimeout(() => {
            this.toast = undefined;
        }, 3500);
    }

    // ---------- header / navigation ----------
    get wordmarkUrl() {
        return `${BRAND}/wordmark-on-dark.png`;
    }

    get driverOptions() {
        return this.drivers.map((d) => ({
            value: d.id,
            label: d.vehicle ? `${d.name} · ${d.vehicle}` : `${d.name} · no vehicle`,
            selected: d.id === this.driverId
        }));
    }

    async handleDriver(event) {
        this.driverId = event.target.value;
        this.view = 'home';
        await this.load();
    }

    get navItems() {
        return [
            { key: 'home', label: 'Home', icon: 'M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10' },
            { key: 'vehicle', label: 'Vehicle', icon: 'M5 16l1.5-5a2 2 0 0 1 1.9-1.4h7.2a2 2 0 0 1 1.9 1.4L19 16M4 16h16v3H4zM7 19v1.5M17 19v1.5' },
            { key: 'trips', label: 'Trips', icon: 'M5 4v16M5 5h11l-2 4 2 4H5' },
            { key: 'me', label: 'Me', icon: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0' }
        ].map((n) => ({
            ...n,
            cls: `nav__btn${this.view === n.key ? ' nav__btn--on' : ''}`,
            current: this.view === n.key ? 'page' : 'false'
        }));
    }

    handleNav(event) {
        this.view = event.currentTarget.dataset.view;
        this.scrollTop();
    }

    scrollTop() {
        const body = this.template.querySelector('.body');
        if (body) body.scrollTop = 0;
    }

    get isHome() { return this.view === 'home'; }
    get isVehicle() { return this.view === 'vehicle'; }
    get isTrips() { return this.view === 'trips'; }
    get isMe() { return this.view === 'me'; }
    get ready() { return !this.loading && this.dash; }

    // ---------- home ----------
    get greeting() {
        const h = new Date().getHours();
        const part = h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening';
        return `${part}, ${this.dash.driver.firstName || this.dash.driver.name}`;
    }

    get hasVehicle() { return !!(this.dash && this.dash.vehicle); }
    get onTrip() { return !!(this.dash && this.dash.openTrip); }

    get tripBanner() {
        const t = this.dash.openTrip;
        if (!t) return null;
        const mins = Math.max(0, Math.round((Date.now() - new Date(t.checkOut).getTime()) / 60000));
        const dur = mins >= 60 ? `${Math.floor(mins / 60)} h ${mins % 60} min` : `${mins} min`;
        return { title: 'You are on a trip', detail: `Started ${CLOCK.format(new Date(t.checkOut))} · ${dur} · odometer ${number(t.odometerStart)} mi` };
    }

    get vehicle() {
        const v = this.dash.vehicle;
        const electric = v.fuelType === 'Electric';
        const level = v.energyLevel == null ? null : Math.max(0, Math.min(100, Math.round(v.energyLevel)));
        return {
            ...v,
            energyLabel: electric ? 'Charge' : 'Fuel',
            energyText: level == null ? '–' : `${level}%`,
            energyBar: `width:${level == null ? 0 : level}%`,
            energyCls: `bar__fill${level != null && level < 20 ? ' bar__fill--low' : ''}`,
            odometerText: number(v.odometer),
            rangeText: v.epaRated ? (v.evRangeMiles != null ? `${Math.round(v.evRangeMiles)} mi range` : `${Math.round(v.mpgCombined)} MPG`) : '',
            seatsText: v.seats ? `${v.seats} seats` : ''
        };
    }

    get vehicleChips() {
        const v = this.dash.vehicle;
        return [v.fuelType, v.branch, this.vehicle.seatsText, this.vehicle.rangeText, v.authorizationType ? `${v.authorizationType} driver` : '']
            .filter(Boolean)
            .map((t, i) => ({ key: `c${i}`, text: t }));
    }

    get quickActions() {
        const trip = this.onTrip
            ? { key: 'endtrip', label: 'End trip', hint: 'Return the vehicle', icon: 'M5 4v16M5 5h11l-2 4 2 4H5' }
            : { key: 'pretrip', label: 'Pre-trip check', hint: 'Start your trip', icon: 'M9 12l2 2 4-4M12 3l8 3v6c0 4.5-3.2 7.7-8 9-4.8-1.3-8-4.5-8-9V6z' };
        return [
            trip,
            { key: 'navigate', label: 'Navigate to car', hint: 'Open in maps', icon: 'M12 21s-6-5.6-6-10a6 6 0 0 1 12 0c0 4.4-6 10-6 10zM12 13a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z' },
            { key: 'issue', label: 'Report an issue', hint: 'Tell the workshop', icon: 'M12 3l10 18H2zM12 10v5M12 18v.01' },
            { key: 'fuel', label: this.vehicle.fuelType === 'Electric' ? 'Log charging' : 'Log fuel', hint: 'Fill-up or charge', icon: 'M6 20V5a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v15M5 20h10M14 9h2.5a1.5 1.5 0 0 1 1.5 1.5V16a1.5 1.5 0 0 0 3 0V9l-3-3' }
        ].map((a) => ({ ...a, cls: `action${a.key === 'endtrip' || a.key === 'pretrip' ? ' action--primary' : ''}` }));
    }

    handleAction(event) {
        const key = event.currentTarget.dataset.key;
        if (key === 'navigate') {
            this.navigate();
        } else {
            this.openSheet(key);
        }
    }

    get notices() {
        return (this.dash.notices || []).map((n, i) => ({ ...n, key: `n${i}`, cls: `notice notice--${n.level}` }));
    }

    get topNotices() { return this.notices.slice(0, 3); }
    get noticeCount() { return this.notices.length; }
    get hasNotices() { return this.notices.length > 0; }
    get noticeBadge() { return this.noticeCount > 9 ? '9+' : String(this.noticeCount); }

    get nextBooking() {
        const r = (this.dash.reservations || [])[0];
        return r ? { ...r, when: whenText(r.startTime), until: whenText(r.endTime) } : null;
    }

    handleBook() {
        // the booking page is the site's home page
        window.location.assign(window.location.pathname.replace(/driver\/?$/, ''));
    }

    // ---------- vehicle ----------
    get hasLocation() {
        const v = this.dash && this.dash.vehicle;
        return !!(v && v.latitude != null && v.longitude != null);
    }

    get mapMarkers() {
        const v = this.dash.vehicle;
        return [{
            location: { Latitude: v.latitude, Longitude: v.longitude },
            title: v.name,
            description: v.plate || ''
        }];
    }

    get mapCenter() {
        const v = this.dash.vehicle;
        return { location: { Latitude: v.latitude, Longitude: v.longitude } };
    }

    get isIos() {
        return /iPad|iPhone|iPod/.test(navigator.userAgent);
    }

    get navigateUrl() {
        const v = this.dash.vehicle;
        return this.isIos
            ? `https://maps.apple.com/?daddr=${v.latitude},${v.longitude}&dirflg=d`
            : `https://www.google.com/maps/dir/?api=1&destination=${v.latitude},${v.longitude}&travelmode=driving`;
    }

    get navigateLabel() {
        return this.isIos ? 'Open in Apple Maps' : 'Open in Google Maps';
    }

    navigate() {
        if (this.hasLocation) {
            window.open(this.navigateUrl, '_blank', 'noopener');
        } else {
            this.view = 'vehicle';
        }
    }

    get locationText() {
        const v = this.dash.vehicle;
        return 'Last known location';
    }

    get authorized() {
        return (this.dash.authorized || []).map((a) => ({
            ...a,
            key: a.assetId,
            sub: [a.plate, a.authType].filter(Boolean).join(' · '),
            until: a.endDate ? `until ${dateText(a.endDate)}` : '',
            keyText: a.hasKey ? 'Key issued' : ''
        }));
    }

    get documents() {
        return (this.dash.documents || []).map((d) => ({
            ...d,
            sub: [d.docNumber, d.validUntil ? `valid until ${dateText(d.validUntil)}` : 'no expiry'].filter(Boolean).join(' · '),
            chipText: daysText(d.daysLeft),
            chipCls: daysClass(d.daysLeft),
            hasLink: !!d.link
        }));
    }

    get tickets() {
        return (this.dash.tickets || []).map((t) => ({
            ...t,
            title: t.summary || t.category || t.name,
            sub: [t.name, t.status === 'In-Shop' ? 'In the workshop' : 'Reported', t.scheduledStart ? `scheduled ${dateText(t.scheduledStart)}` : ''].filter(Boolean).join(' · '),
            chipCls: `chip chip--${t.priority === 'Critical' || t.priority === 'High' ? 'bad' : t.priority === 'Medium' ? 'warn' : 'ok'}`
        }));
    }

    // ---------- trips ----------
    get reservations() {
        return (this.dash.reservations || []).map((r) => ({
            ...r,
            when: whenText(r.startTime),
            until: whenText(r.endTime),
            chipCls: `chip chip--${r.status === 'Approved' || r.status === 'Active' ? 'ok' : 'warn'}`
        }));
    }

    get hasReservations() { return this.reservations.length > 0; }

    get recentTrips() {
        return (this.dash.recentTrips || []).map((t) => ({
            ...t,
            when: whenText(t.checkOut),
            distanceText: t.distance != null ? `${number(t.distance)} mi` : '',
            damageText: t.newDamage ? 'Damage reported' : ''
        }));
    }

    get hasTrips() { return this.recentTrips.length > 0; }

    // ---------- me ----------
    get driver() {
        const d = this.dash.driver;
        const score = d.safetyScore == null ? null : Math.max(0, Math.min(100, Math.round(d.safetyScore)));
        const circumference = 2 * Math.PI * 34;
        return {
            ...d,
            score: score == null ? '–' : String(score),
            ringStyle: `stroke-dasharray:${score == null ? 0 : (circumference * score) / 100} ${circumference}`,
            ringCls: `ring__value${score != null && score < 70 ? ' ring__value--low' : ''}`,
            licenseSub: [d.licenseClass ? `Class ${d.licenseClass}` : '', d.licenseState, d.licenseNumber].filter(Boolean).join(' · '),
            licenseChip: d.licenseExpiry ? daysText(d.licenseDaysLeft) : '',
            licenseCls: daysClass(d.licenseDaysLeft, 60),
            medicalSub: d.medicalCert ? `valid until ${dateText(d.medicalCert)}` : 'not on file',
            medicalChip: d.medicalCert ? daysText(d.medicalDaysLeft) : '',
            medicalCls: daysClass(d.medicalDaysLeft, 60)
        };
    }

    get qualifications() {
        return (this.dash.qualifications || []).map((q) => ({
            ...q,
            title: q.authority ? `${q.qualType} · ${q.authority}` : q.qualType,
            sub: q.validUntil ? `valid until ${dateText(q.validUntil)}` : 'does not expire',
            chipText: q.validUntil ? daysText(q.daysLeft) : '',
            chipCls: daysClass(q.daysLeft, 60)
        }));
    }

    get violations() {
        return (this.dash.violations || []).map((v) => ({
            ...v,
            sub: [whenText(v.occurredAt), v.vehicle, v.value].filter(Boolean).join(' · '),
            chipCls: `chip chip--${v.severity === 'Critical' || v.severity === 'High' ? 'bad' : v.severity === 'Medium' ? 'warn' : 'ok'}`
        }));
    }

    get citations() {
        return (this.dash.citations || []).map((c) => ({
            ...c,
            title: c.violationType || 'Citation',
            sub: [c.ticketNumber, c.citationDate ? dateText(c.citationDate) : '', c.courtDate ? `court ${dateText(c.courtDate)}` : ''].filter(Boolean).join(' · '),
            amountText: money(c.amount),
            chipCls: `chip chip--${c.status === 'New' ? 'bad' : c.status === 'Contested' ? 'warn' : 'ok'}`
        }));
    }

    get hasViolations() { return this.violations.length > 0; }
    get hasCitations() { return this.citations.length > 0; }
    get hasQualifications() { return this.qualifications.length > 0; }

    get fuelCard() {
        const f = this.dash.fuelCard;
        return f ? { ...f, number: f.lastDigits ? `•••• ${f.lastDigits}` : '', limitText: f.dailyLimit ? `${money(f.dailyLimit)} / day` : '', expiryText: f.expiry ? `expires ${dateText(f.expiry)}` : '' } : null;
    }

    // ---------- sheets ----------
    openSheet(key) {
        this.sheetError = undefined;
        this.photos = [];
        this.notes = '';
        this.damage = false;
        if (key === 'pretrip' || key === 'endtrip') {
            const v = this.dash.vehicle;
            this.odometer = v && v.odometer != null ? String(Math.round(v.odometer)) : '';
            this.energy = v && v.energyLevel != null ? Math.round(v.energyLevel) : 50;
            this.checks = CHECKS.reduce((m, c) => ({ ...m, [c.key]: true }), {});
        }
        if (key === 'issue') {
            this.issueCategory = 'Corrective Repair';
            this.issuePriority = 'Medium';
        }
        if (key === 'fuel') {
            this.fuelVolume = '';
            this.fuelCost = '';
            this.fuelStation = '';
            this.fuelFull = true;
            const v = this.dash.vehicle;
            this.odometer = v && v.odometer != null ? String(Math.round(v.odometer)) : '';
        }
        this.sheet = key;
    }

    closeSheet() {
        if (!this.busy) this.sheet = undefined;
    }

    get sheetOpen() { return !!this.sheet; }
    get isPretrip() { return this.sheet === 'pretrip'; }
    get isEndtrip() { return this.sheet === 'endtrip'; }
    get isTripSheet() { return this.sheet === 'pretrip' || this.sheet === 'endtrip'; }
    get isIssue() { return this.sheet === 'issue'; }
    get isFuel() { return this.sheet === 'fuel'; }
    get isNotices() { return this.sheet === 'notices'; }

    get sheetTitle() {
        return { pretrip: 'Pre-trip check', endtrip: 'End your trip', issue: 'Report an issue', fuel: this.vehicle && this.vehicle.fuelType === 'Electric' ? 'Log charging' : 'Log fuel', notices: 'Notifications' }[this.sheet] || '';
    }

    handleBell() {
        this.sheet = 'notices';
    }

    handleInput(event) {
        this[event.currentTarget.dataset.field] = event.target.value;
        this.sheetError = undefined;
    }

    handleEnergy(event) {
        this.energy = Number(event.target.value);
    }

    handleCheckbox(event) {
        this[event.currentTarget.dataset.field] = event.target.checked;
    }

    get checkRows() {
        return CHECKS.map((c) => {
            const ok = this.checks[c.key] !== false;
            return { ...c, okCls: `seg__btn${ok ? ' seg__btn--ok' : ''}`, issueCls: `seg__btn${ok ? '' : ' seg__btn--issue'}` };
        });
    }

    handleCheck(event) {
        const { key, ok } = event.currentTarget.dataset;
        this.checks = { ...this.checks, [key]: ok === 'true' };
    }

    get issueCount() {
        return CHECKS.filter((c) => this.checks[c.key] === false).length;
    }

    get anyIssue() {
        return this.issueCount > 0 || this.damage;
    }

    get notesLabel() {
        return this.anyIssue ? 'Notes (required)' : 'Notes (optional)';
    }

    get issueSummary() {
        return this.issueCount > 0 ? `${this.issueCount} item${this.issueCount > 1 ? 's' : ''} flagged. A service ticket will be raised.` : 'Everything looks fine.';
    }

    get energyLabel() {
        return this.vehicle && this.vehicle.fuelType === 'Electric' ? 'Charge level' : 'Fuel level';
    }

    get energyValueText() { return `${this.energy}%`; }

    get categoryOptions() {
        return ISSUE_CATEGORIES.map((c) => ({ ...c, cls: `pill${c.value === this.issueCategory ? ' pill--on' : ''}` }));
    }

    get priorityOptions() {
        return PRIORITIES.map((p) => ({ value: p, cls: `pill${p === this.issuePriority ? ' pill--on' : ''}` }));
    }

    handleCategory(event) { this.issueCategory = event.currentTarget.dataset.value; }
    handlePriority(event) { this.issuePriority = event.currentTarget.dataset.value; }

    get fuelUnit() { return this.vehicle && this.vehicle.fuelType === 'Electric' ? 'kWh' : 'Gallons (US)'; }
    get fuelUnitLabel() { return this.vehicle && this.vehicle.fuelType === 'Electric' ? 'kWh' : 'gallons'; }

    // photos
    get isPhotoSheet() { return this.sheet === 'pretrip' || this.sheet === 'endtrip' || this.sheet === 'issue'; }
    get canAddPhoto() { return this.photos.length < MAX_PHOTOS; }
    get hasPhotos() { return this.photos.length > 0; }

    async handlePhoto(event) {
        const file = event.target.files && event.target.files[0];
        event.target.value = '';
        if (!file) return;
        try {
            const img = await shrinkImage(file);
            this.photos = [...this.photos, { key: `p${Date.now()}`, name: `photo-${this.photos.length + 1}`, dataUrl: img.dataUrl, base64: img.base64 }];
        } catch (e) {
            this.sheetError = 'That photo could not be read.';
        }
    }

    handleRemovePhoto(event) {
        this.photos = this.photos.filter((p) => p.key !== event.currentTarget.dataset.key);
    }

    async uploadPhotos(parentId) {
        for (const p of this.photos) {
            await attachPhoto({ parentId, fileName: p.name, base64: p.base64 });
        }
    }

    // submit
    async submit() {
        this.busy = true;
        this.sheetError = undefined;
        try {
            const v = this.dash.vehicle;
            const odo = this.odometer === '' ? null : Number(this.odometer);
            if (this.isTripSheet) {
                const flagged = CHECKS.filter((c) => this.checks[c.key] === false).map((c) => c.label);
                const report = [flagged.length ? `Flagged: ${flagged.join(', ')}.` : '', this.notes].filter(Boolean).join(' ');
                if (this.anyIssue && !report.trim()) {
                    this.sheetError = 'Please describe what you found.';
                    this.busy = false;
                    return;
                }
                if (this.isPretrip) {
                    const tripId = await startTrip({
                        driverId: this.driverId, assetId: v.id, odometer: odo, energyPercent: this.energy,
                        conditionNotes: report, newDamage: this.anyIssue
                    });
                    await this.uploadPhotos(tripId);
                    this.showToast('Trip started. Drive safe!');
                } else {
                    await endTrip({
                        allocationId: this.dash.openTrip.id, odometer: odo, energyPercent: this.energy,
                        conditionNotes: report, newDamage: this.anyIssue
                    });
                    await this.uploadPhotos(this.dash.openTrip.id);
                    this.showToast('Trip ended. Thank you!');
                }
            } else if (this.isIssue) {
                if (!this.notes.trim()) {
                    this.sheetError = 'Please describe the issue.';
                    this.busy = false;
                    return;
                }
                const ticketId = await reportIssue({
                    driverId: this.driverId, assetId: v.id, category: this.issueCategory, priority: this.issuePriority, description: this.notes
                });
                await this.uploadPhotos(ticketId);
                this.showToast('Report sent to the workshop.');
            } else if (this.isFuel) {
                await logFuel({
                    driverId: this.driverId, assetId: v.id, volume: Number(this.fuelVolume), unit: this.fuelUnit,
                    totalCost: this.fuelCost === '' ? null : Number(this.fuelCost), odometer: odo, fullTank: this.fuelFull, stationName: this.fuelStation
                });
                this.showToast(this.vehicle.fuelType === 'Electric' ? 'Charging session saved.' : 'Fuel entry saved.');
            }
            this.sheet = undefined;
            await this.load();
        } catch (e) {
            this.sheetError = (e && e.body && e.body.message) || 'Something went wrong. Please try again.';
        } finally {
            this.busy = false;
        }
    }

    get submitLabel() {
        if (this.busy) return 'Saving…';
        return { pretrip: 'Start trip', endtrip: 'End trip', issue: 'Send report', fuel: 'Save' }[this.sheet] || 'Save';
    }
}
