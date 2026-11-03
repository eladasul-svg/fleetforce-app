import { LightningElement, api } from "lwc";
import { loadScript, loadStyle } from "lightning/platformResourceLoader";
import LEAFLET from "@salesforce/resourceUrl/Leaflet";

/**
 * Route map: one coloured road line per route and numbered stops, drawn with Leaflet on OpenStreetMap tiles.
 * lightning-map cannot draw lines or labels, which is why this exists.
 *
 * routes: [{ id, name, color, geometry (encoded polyline, precision 5, may be empty),
 *            depot: { lat, lng, title } | null,
 *            stops: [{ id, lat, lng, mark, title, detail, dim }] }]
 * When a route has no geometry, its stops are joined with straight dashed lines.
 */

const TILES = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
const ATTRIBUTION =
  '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank">OpenStreetMap</a> contributors';

/** Google encoded polyline -> [[lat, lng], ...]. */
export function decodePolyline(encoded, precision = 5) {
  const out = [];
  if (!encoded) return out;
  const factor = 10 ** precision;
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    for (const which of [0, 1]) {
      let result = 0;
      let shift = 0;
      let byte;
      do {
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20 && index < encoded.length);
      const delta = result & 1 ? ~(result >> 1) : result >> 1;
      if (which === 0) lat += delta;
      else lng += delta;
    }
    out.push([lat / factor, lng / factor]);
  }
  return out;
}

function escapeHtml(value) {
  return String(value == null ? "" : value).replace(
    /[&<>"']/g,
    (c) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;"
      })[c]
  );
}

function stopIcon(L, color, mark, dim) {
  const size = 26;
  return L.divIcon({
    className: "",
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    popupAnchor: [0, -size / 2],
    html:
      `<span style="display:flex;align-items:center;justify-content:center;width:${size}px;height:${size}px;` +
      `border-radius:50%;background:${color};color:#fff;font:700 12px/1 system-ui,sans-serif;` +
      `border:2px solid #fff;box-shadow:0 1px 3px rgba(0,0,0,.45);opacity:${dim ? 0.35 : 1}">` +
      `${escapeHtml(mark)}</span>`
  });
}

function depotIcon(L) {
  const size = 28;
  return L.divIcon({
    className: "",
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2],
    popupAnchor: [0, -size / 2],
    html:
      `<span style="display:flex;align-items:center;justify-content:center;width:${size}px;height:${size}px;` +
      `border-radius:6px;background:#0f1e33;color:#fff;font:700 13px/1 system-ui,sans-serif;` +
      `border:2px solid #fff;box-shadow:0 1px 3px rgba(0,0,0,.45)">D</span>`
  });
}

export default class RouteMap extends LightningElement {
  _routes = [];
  map;
  layer;
  ready = false;
  loading = false;
  failed;
  lastFitKey;

  @api
  get routes() {
    return this._routes;
  }
  set routes(value) {
    this._routes = value || [];
    this.draw();
  }

  renderedCallback() {
    if (this.map || this.loading) return;
    this.loading = true;
    Promise.all([
      loadScript(this, `${LEAFLET}/leaflet.js`),
      loadStyle(this, `${LEAFLET}/leaflet.css`)
    ])
      .then(() => {
        const L = window.L;
        const el = this.template.querySelector(".map");
        this.map = L.map(el, { scrollWheelZoom: false });
        L.tileLayer(TILES, { maxZoom: 19, attribution: ATTRIBUTION }).addTo(
          this.map
        );
        this.layer = L.layerGroup().addTo(this.map);
        this.ready = true;
        this.draw();
      })
      .catch((e) => {
        this.failed = `The map could not load: ${e && e.message ? e.message : e}`;
      });
  }

  disconnectedCallback() {
    if (this.map) {
      this.map.remove();
      this.map = null;
      this.ready = false;
      this.loading = false;
    }
  }

  draw() {
    if (!this.ready) return;
    const L = window.L;
    this.layer.clearLayers();
    const bounds = [];
    const depots = new Set();
    this._routes.forEach((r) => {
      const stops = (r.stops || []).filter(
        (s) => s.lat != null && s.lng != null
      );
      let path = decodePolyline(r.geometry);
      const dashed = path.length < 2;
      if (dashed) {
        path = [];
        if (r.depot) path.push([r.depot.lat, r.depot.lng]);
        stops.forEach((s) => path.push([s.lat, s.lng]));
        if (r.depot) path.push([r.depot.lat, r.depot.lng]);
      }
      if (path.length > 1) {
        // A white casing under the line keeps overlapping routes readable.
        L.polyline(path, { color: "#fff", weight: 7, opacity: 0.8 }).addTo(
          this.layer
        );
        L.polyline(path, {
          color: r.color,
          weight: 4,
          opacity: 0.9,
          dashArray: dashed ? "6 6" : null
        })
          .bindTooltip(escapeHtml(r.name), { sticky: true })
          .addTo(this.layer);
        path.forEach((p) => bounds.push(p));
      }
      if (r.depot && r.depot.lat != null) {
        const key = `${r.depot.lat},${r.depot.lng}`;
        if (!depots.has(key)) {
          depots.add(key);
          L.marker([r.depot.lat, r.depot.lng], {
            icon: depotIcon(L),
            zIndexOffset: 1000
          })
            .bindPopup(
              `<strong>${escapeHtml(r.depot.title || "Depot")}</strong>`
            )
            .addTo(this.layer);
          bounds.push([r.depot.lat, r.depot.lng]);
        }
      }
      stops.forEach((s) => {
        L.marker([s.lat, s.lng], { icon: stopIcon(L, r.color, s.mark, s.dim) })
          .bindPopup(
            `<strong>${escapeHtml(s.title)}</strong>` +
              (s.detail ? `<br/>${escapeHtml(s.detail)}` : "")
          )
          .addTo(this.layer);
        bounds.push([s.lat, s.lng]);
      });
    });
    // Re-fit only when the set of routes shown changes, so a refresh does not undo the user's zoom.
    const fitKey = this._routes.map((r) => r.id).join("|");
    if (bounds.length && fitKey !== this.lastFitKey) {
      this.map.fitBounds(bounds, { padding: [24, 24] });
      this.lastFitKey = fitKey;
    }
  }
}
