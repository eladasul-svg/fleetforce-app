import { LightningElement } from 'lwc';
import BRAND from '@salesforce/resourceUrl/FleetForceBrand';
import search from '@salesforce/apex/MotorpoolBookingController.search';
import book from '@salesforce/apex/MotorpoolBookingController.book';

const TYPES = ['Any', 'Sedan', 'SUV', 'Pickup', 'Van', 'Electric or hybrid'];
const TYPE_LABELS = { Any: 'Any type', 'Electric or hybrid': 'Electric / hybrid' };

const pad = (n) => String(n).padStart(2, '0');
const toLocalInput = (d) =>
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
const dayTime = (iso) =>
    new Intl.DateTimeFormat('en-GB', {
        weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit'
    }).format(new Date(iso));

function defaultWindow() {
    const start = new Date();
    start.setDate(start.getDate() + 3);
    start.setHours(9, 0, 0, 0);
    const end = new Date(start);
    end.setDate(end.getDate() + 1);
    end.setHours(17, 0, 0, 0);
    return { start: toLocalInput(start), end: toLocalInput(end) };
}

export default class MotorpoolBooking extends LightningElement {
    pickup = defaultWindow().start;
    dropoff = defaultWindow().end;
    seats = 2;
    vehicleType = 'Any';

    step = 'search'; // search | results | details | done
    loading = false;
    error;
    result;
    selected;
    form = { firstName: '', lastName: '', email: '', phone: '' };
    confirmation;

    get wordmarkUrl() {
        return `${BRAND}/wordmark-on-dark.png`;
    }

    // ---------- search form ----------
    get typeChips() {
        return TYPES.map((t) => ({
            value: t,
            label: TYPE_LABELS[t] || t,
            cls: `chip${t === this.vehicleType ? ' chip--on' : ''}`,
            pressed: String(t === this.vehicleType)
        }));
    }

    handleField(event) {
        const field = event.currentTarget.dataset.field;
        this[field] = event.target.value;
        this.error = undefined;
    }

    handleSeats(event) {
        const delta = Number(event.currentTarget.dataset.delta);
        this.seats = Math.max(1, Math.min(9, this.seats + delta));
    }

    handleType(event) {
        this.vehicleType = event.currentTarget.dataset.value;
    }

    async handleSearch() {
        if (!this.pickup || !this.dropoff) {
            this.error = 'Please choose pick-up and return times.';
            return;
        }
        const start = new Date(this.pickup);
        const end = new Date(this.dropoff);
        if (end <= start) {
            this.error = 'The return time must be after the pick-up time.';
            return;
        }
        this.loading = true;
        this.error = undefined;
        try {
            this.result = await search({
                startTime: start.toISOString(),
                endTime: end.toISOString(),
                minSeats: this.seats,
                vehicleType: this.vehicleType,
                tzOffsetMinutes: -start.getTimezoneOffset()
            });
            this.step = 'results';
        } catch (e) {
            this.error = this.messageOf(e);
        } finally {
            this.loading = false;
        }
    }

    messageOf(e) {
        return (e && e.body && e.body.message) || 'Something went wrong. Please try again.';
    }

    // ---------- results ----------
    get windowLabel() {
        return `${dayTime(this.pickup)}  →  ${dayTime(this.dropoff)}`;
    }

    get windowLabelStart() {
        return dayTime(this.pickup);
    }

    get windowLabelEnd() {
        return dayTime(this.dropoff);
    }

    get durationLabel() {
        const ms = new Date(this.dropoff) - new Date(this.pickup);
        const hours = Math.round(ms / 36e5);
        const days = Math.floor(hours / 24);
        const rest = hours % 24;
        const parts = [];
        if (days) parts.push(`${days} day${days > 1 ? 's' : ''}`);
        if (rest) parts.push(`${rest} h`);
        return parts.join(' ') || '0 h';
    }

    get showSearch() {
        return this.step === 'search' || this.step === 'results';
    }

    get showResults() {
        return this.step === 'results' && this.result;
    }

    get showDetails() {
        return this.step === 'details' && this.selected;
    }

    get showDone() {
        return this.step === 'done' && this.confirmation;
    }

    get hasOptions() {
        return this.result && this.result.options.length > 0;
    }

    get summaryLine() {
        if (!this.result) return '';
        const a = this.result.availableCount;
        const u = this.result.unavailableCount;
        return `${a} vehicle${a === 1 ? '' : 's'} available` + (u ? ` · ${u} unavailable for these dates` : '');
    }

    get cards() {
        if (!this.result) return [];
        return this.result.options.map((o) => ({
            ...o,
            cardCls: `vcard${o.available ? '' : ' vcard--off'}`,
            statusCls: `pill ${o.available ? 'pill--ok' : 'pill--off'}`,
            statusText: o.available ? 'Available for your dates' : o.reason,
            days: o.days.map((d, i) => ({
                ...d,
                key: `${o.id}-${i}`,
                cls: `day day--${d.status}${d.inWindow ? ' day--window' : ''}`,
                title: `${d.dayName} ${d.dayNumber}: ${d.status === 'free' ? 'free' : d.status === 'booked' ? 'booked' : 'maintenance'}`
            })),
            specs: this.specsOf(o),
            seatLabel: `${o.seats || '?'} seats`
        }));
    }

    specsOf(o) {
        const specs = [];
        if (o.plate) specs.push(`Plate ${o.plate}`);
        if (o.epaRated) {
            specs.push(
                o.evRangeMiles != null
                    ? `${Math.round(o.mpgCombined)} MPGe · ${Math.round(o.evRangeMiles)} mi range`
                    : `${Math.round(o.mpgCombined)} MPG`
            );
        }
        if (o.fuelType) specs.push(o.fuelType);
        if (o.branch) specs.push(o.branch);
        return specs.map((s, i) => ({ key: `s${i}`, text: s }));
    }

    handleSelect(event) {
        const id = event.currentTarget.dataset.id;
        this.selected = this.cards.find((c) => c.id === id);
        this.step = 'details';
        this.error = undefined;
    }

    // ---------- details ----------
    handleForm(event) {
        this.form = { ...this.form, [event.currentTarget.dataset.field]: event.target.value };
        this.error = undefined;
    }

    handleBack() {
        this.step = 'results';
        this.error = undefined;
    }

    async handleSubmit() {
        const { firstName, lastName, email } = this.form;
        if (!firstName.trim() || !lastName.trim() || !/^\S+@\S+\.\S+$/.test(email.trim())) {
            this.error = 'Please enter your name and a valid email address.';
            return;
        }
        this.loading = true;
        this.error = undefined;
        try {
            this.confirmation = await book({
                assetId: this.selected.id,
                startTime: new Date(this.pickup).toISOString(),
                endTime: new Date(this.dropoff).toISOString(),
                firstName: firstName.trim(),
                lastName: lastName.trim(),
                email: email.trim(),
                phone: this.form.phone
            });
            this.step = 'done';
        } catch (e) {
            this.error = this.messageOf(e);
        } finally {
            this.loading = false;
        }
    }

    // ---------- confirmation ----------
    get confirmedWindow() {
        return this.confirmation
            ? `${dayTime(this.confirmation.startTime)}  →  ${dayTime(this.confirmation.endTime)}`
            : '';
    }

    handleReset() {
        const w = defaultWindow();
        this.pickup = w.start;
        this.dropoff = w.end;
        this.seats = 2;
        this.vehicleType = 'Any';
        this.form = { firstName: '', lastName: '', email: '', phone: '' };
        this.result = undefined;
        this.selected = undefined;
        this.confirmation = undefined;
        this.error = undefined;
        this.step = 'search';
    }
}
