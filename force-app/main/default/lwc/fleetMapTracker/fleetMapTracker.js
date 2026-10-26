import { LightningElement, wire } from 'lwc';
import getAssetLocations from '@salesforce/apex/FleetKpiController.getAssetLocations';
import { ROUTES } from 'c/fleetDemoRoutes';

/**
 * Real-Time Asset Tracker. Shows what the fleet is doing right now: how many vehicles are moving, idling or not
 * reporting, with a live list (speed, heading, last update) and a map of the active vehicles.
 *
 * There is no live telemetry feed connected yet, so the movement is a DEMO SIMULATION: a few vehicles are placed on
 * real Lisbon routes and advanced in the browser (time-compressed, so movement is visible on the map). The page says
 * so. When a real feed writes Telemetry_Raw__c, the vehicle state below is the part to replace with a poll.
 */

const TICK_MS = 2000;      // how often the simulation advances
const TIME_SCALE = 8;      // simulated seconds per real second, so movement is visible at city zoom
const SIM_COUNT = 8;
const FOCUS_ZOOM = 15;
const MOVING_COLOR = '#22A77C';
const IDLE_COLOR = '#E07A12';
const SELECTED_COLOR = '#0070D2';
// outer body (clockwise), then the windscreen and rear window (counter-clockwise) so they show as holes
const CAR_PATH = 'M12 1 C15.2 1 16.8 3.2 16.8 6.5 L16.8 17.5 C16.8 20.6 14.8 23 12 23 C9.2 23 7.2 20.6 7.2 17.5 L7.2 6.5 C7.2 3.2 8.8 1 12 1 Z '
    + 'M9.1 6.6 L9.7 10 L14.3 10 L14.9 6.6 C13.9 5.9 10.1 5.9 9.1 6.6 Z '
    + 'M9.5 16.2 L9.2 18.4 L14.8 18.4 L14.5 16.2 Z';
const COMPASS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

// ---------- geometry ----------
const R_EARTH = 6371000;
const rad = (d) => (d * Math.PI) / 180;
function haversine(a, b) {
    const dLat = rad(b[0] - a[0]);
    const dLon = rad(b[1] - a[1]);
    const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLon / 2) ** 2;
    return 2 * R_EARTH * Math.asin(Math.sqrt(h));
}
function bearing(a, b) {
    const y = Math.sin(rad(b[1] - a[1])) * Math.cos(rad(b[0]));
    const x = Math.cos(rad(a[0])) * Math.sin(rad(b[0])) - Math.sin(rad(a[0])) * Math.cos(rad(b[0])) * Math.cos(rad(b[1] - a[1]));
    return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
}

// cumulative distance along each route, so a distance maps to a position
const ROUTE_DATA = ROUTES.map((r) => {
    const cum = [0];
    for (let i = 1; i < r.points.length; i++) {
        cum.push(cum[i - 1] + haversine(r.points[i - 1], r.points[i]));
    }
    return { ...r, cum, length: cum[cum.length - 1] };
});

function pointAt(route, dist) {
    const d = Math.max(0, Math.min(route.length, dist));
    let lo = 0;
    let hi = route.cum.length - 1;
    while (hi - lo > 1) {
        const mid = (lo + hi) >> 1;
        if (route.cum[mid] <= d) lo = mid;
        else hi = mid;
    }
    const span = route.cum[hi] - route.cum[lo] || 1;
    const t = (d - route.cum[lo]) / span;
    const a = route.points[lo];
    const b = route.points[hi];
    return { lat: a[0] + (b[0] - a[0]) * t, lon: a[1] + (b[1] - a[1]) * t, a, b };
}

// small deterministic random generator, so the demo behaves the same every time
function seeded(seed) {
    let s = seed >>> 0;
    return () => {
        s = (s + 0x6d2b79f5) | 0;
        let t = Math.imul(s ^ (s >>> 15), 1 | s);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

export default class FleetMapTracker extends LightningElement {
    assets = [];
    sims = [];
    now = Date.now();
    selectedId;
    mapCenter;
    zoomLevel;
    error;
    started = false;

    _tickTimer;
    _clockTimer;
    _resizeObserver;

    @wire(getAssetLocations)
    wiredLocations({ error, data }) {
        if (data) {
            this.error = undefined;
            this.assets = data;
            if (!this.started) {
                this.startSimulation();
            }
        } else if (error) {
            this.error = error;
            console.error('Error fetching Asset Locations', error);
            this.assets = [];
        }
    }

    renderedCallback() {
        const map = this.template.querySelector('lightning-map');
        if (!map || this._resizeObserver) {
            return;
        }
        this._resizeObserver = new ResizeObserver(() => this.syncListHeight());
        this._resizeObserver.observe(map);
        this.syncListHeight();
        if (!this.mapCenter) {
            this.fitAll();
        }
    }

    disconnectedCallback() {
        clearInterval(this._tickTimer);
        clearInterval(this._clockTimer);
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
            this._resizeObserver = undefined;
        }
    }

    // ---------- simulation ----------
    startSimulation() {
        const pool = this.assets
            .filter((a) => ['Available', 'Assigned'].includes(a.fleetforce__Status__c))
            .sort((a, b) => a.Name.localeCompare(b.Name))
            .slice(0, SIM_COUNT);
        const stamp = Date.now();
        this.sims = pool.map((a, i) => {
            const route = ROUTE_DATA[i % ROUTE_DATA.length];
            const rand = seeded(1000 + i * 77);
            const parkedType = i === 2 || i === 5; // two vehicles that idle for long stretches (engine on, waiting)
            const v = {
                id: a.Id,
                name: a.Name,
                plate: a.fleetforce__License_Plate__c || '',
                bodyType: a.fleetforce__Body_Type__c,
                color: a.fleetforce__Color__c,
                fuelType: a.fleetforce__Fuel_Type__c,
                route,
                dist: route.length * ((i * 0.37 + 0.08) % 0.9),
                dir: i % 2 === 0 ? 1 : -1,
                baseSpeed: 30 + rand() * 28,
                phase: rand() * 6,
                rand,
                parkedType,
                state: 'moving',
                stateTicks: 0,
                untilStop: 12 + Math.floor(rand() * 30),
                speed: 0,
                heading: 0,
                lat: 0,
                lon: 0,
                lastUpdate: stamp
            };
            if (parkedType) {
                v.state = 'idle';
                v.stateTicks = 6 + Math.floor(rand() * 8);
            }
            this.place(v);
            return v;
        });
        this.started = true;
        this._tickTimer = setInterval(() => this.tick(), TICK_MS);
        this._clockTimer = setInterval(() => {
            this.now = Date.now();
        }, 1000);
    }

    place(v) {
        const p = pointAt(v.route, v.dist);
        v.lat = p.lat;
        v.lon = p.lon;
        const ahead = pointAt(v.route, v.dist + v.dir * 20);
        const from = [p.lat, p.lon];
        const to = [ahead.lat, ahead.lon];
        if (haversine(from, to) > 1) {
            v.heading = bearing(from, to);
        }
    }

    tick() {
        if (document.hidden) {
            return;
        }
        const stamp = Date.now();
        const next = this.sims.map((old) => {
            const v = { ...old };
            if (v.state === 'idle') {
                v.speed = 0;
                v.stateTicks -= 1;
                if (v.stateTicks <= 0) {
                    v.state = 'moving';
                    v.untilStop = (v.parkedType ? 50 : 22) + Math.floor(v.rand() * 40);
                }
            } else {
                v.phase += 0.35;
                v.speed = Math.max(8, v.baseSpeed + 8 * Math.sin(v.phase) + (v.rand() - 0.5) * 4);
                v.dist += ((v.speed / 3.6) * (TICK_MS / 1000) * TIME_SCALE) * v.dir;
                if (v.dist >= v.route.length) {
                    v.dist = v.route.length;
                    v.dir = -1;
                } else if (v.dist <= 0) {
                    v.dist = 0;
                    v.dir = 1;
                }
                v.untilStop -= 1;
                if (v.untilStop <= 0) {
                    v.state = 'idle';
                    v.stateTicks = v.parkedType ? 12 + Math.floor(v.rand() * 10) : 2 + Math.floor(v.rand() * 4);
                }
            }
            v.lastUpdate = stamp;
            this.place(v);
            return v;
        });
        this.sims = next;
        this.now = stamp;
        if (this.selectedId) {
            const sel = next.find((v) => v.id === this.selectedId);
            if (sel) {
                this.mapCenter = { location: { Latitude: sel.lat, Longitude: sel.lon } };
            }
        }
    }

    // ---------- derived view data ----------
    get hasData() {
        return this.sims.length > 0;
    }

    get movingCount() {
        return this.sims.filter((v) => v.state === 'moving').length;
    }

    get idleCount() {
        return this.sims.filter((v) => v.state === 'idle').length;
    }

    get offlineCount() {
        return Math.max(0, this.assets.length - this.sims.length);
    }

    get rows() {
        return this.sims.map((v) => {
            const moving = v.state === 'moving';
            const ago = Math.max(0, Math.floor((this.now - v.lastUpdate) / 1000));
            return {
                id: v.id,
                name: v.name,
                plate: v.plate,
                bodyType: v.bodyType,
                color: v.color,
                fuelType: v.fuelType,
                rowCls: `row${v.id === this.selectedId ? ' row--selected' : ''}`,
                statusText: moving ? 'Moving' : 'Idle',
                pillCls: `pill ${moving ? 'pill--moving' : 'pill--idle'}`,
                speedText: String(Math.round(v.speed)),
                arrowStyle: `transform: rotate(${Math.round(v.heading)}deg)`,
                compass: COMPASS[Math.round(v.heading / 45) % 8],
                destination: v.dir === 1 ? v.route.to : v.route.from,
                updated: ago < 2 ? 'just now' : `${ago}s ago`
            };
        });
    }

    /**
     * Top-down car glyph (nose up, 24 x 24 box, windscreen and rear window cut out), rotated to the direction of travel.
     * Moving cars are green, idle ones amber, the followed one blue and larger.
     */
    get mapMarkers() {
        return this.sims.map((v) => {
            const selected = v.id === this.selectedId;
            return {
                location: { Latitude: v.lat, Longitude: v.lon },
                value: v.id,
                mapIcon: {
                    path: CAR_PATH,
                    fillColor: selected ? SELECTED_COLOR : v.state === 'moving' ? MOVING_COLOR : IDLE_COLOR,
                    fillOpacity: 1,
                    strokeColor: '#FFFFFF',
                    strokeWeight: 1.5,
                    scale: selected ? 1.9 : 1.45,
                    rotation: Math.round(v.heading),
                    anchor: { x: 12, y: 12 }
                }
            };
        });
    }

    get followingName() {
        const v = this.sims.find((s) => s.id === this.selectedId);
        return v ? v.name : '';
    }

    get isFollowing() {
        return !!this.selectedId;
    }

    // ---------- interaction ----------
    handleRowClick(event) {
        const id = event.currentTarget.dataset.id;
        this.selectedId = this.selectedId === id ? undefined : id;
        const v = this.sims.find((s) => s.id === this.selectedId);
        if (v) {
            this.mapCenter = { location: { Latitude: v.lat, Longitude: v.lon } };
            this.zoomLevel = FOCUS_ZOOM;
        } else {
            this.fitAll();
        }
    }

    handleMarkerSelect(event) {
        const id = event.detail.selectedMarkerValue;
        if (id && id !== this.selectedId) {
            this.selectedId = id;
            const v = this.sims.find((s) => s.id === id);
            if (v) {
                this.mapCenter = { location: { Latitude: v.lat, Longitude: v.lon } };
                this.zoomLevel = FOCUS_ZOOM;
            }
        }
    }

    handleShowAll() {
        this.selectedId = undefined;
        this.fitAll();
    }

    // ---------- layout ----------
    /** Frames every route (Web Mercator maths, so it works for any map size). */
    fitAll() {
        const map = this.template.querySelector('lightning-map');
        if (!map) {
            return;
        }
        const lats = [];
        const lons = [];
        ROUTE_DATA.forEach((r) => r.points.forEach((p) => {
            lats.push(p[0]);
            lons.push(p[1]);
        }));
        const merc = (lat) => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
        const [minLat, maxLat] = [Math.min(...lats), Math.max(...lats)];
        const [minLon, maxLon] = [Math.min(...lons), Math.max(...lons)];
        const { width, height } = map.getBoundingClientRect();
        if (!width || !height) {
            return;
        }
        const lonFrac = (maxLon - minLon) / 360;
        const latFrac = (merc(maxLat) - merc(minLat)) / (2 * Math.PI);
        const zoom = Math.min(Math.log2(width / (256 * lonFrac * 1.15)), Math.log2(height / (256 * latFrac * 1.15)));
        this.mapCenter = { location: { Latitude: (minLat + maxLat) / 2, Longitude: (minLon + maxLon) / 2 } };
        this.zoomLevel = Math.max(3, Math.min(14, Math.floor(zoom)));
    }

    /** lightning-map draws at 16:9 of its width, so size the list to match the map's real height. */
    syncListHeight() {
        const map = this.template.querySelector('lightning-map');
        const side = this.template.querySelector('.side');
        if (!map || !side) {
            return;
        }
        const h = map.getBoundingClientRect().height;
        if (h > 0) {
            side.style.height = `${Math.round(h)}px`;
        }
    }
}
