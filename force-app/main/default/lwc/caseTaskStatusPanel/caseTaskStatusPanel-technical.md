# caseTaskStatusPanel — Technical Description

## Overview

`caseTaskStatusPanel` is a Lightning Web Component designed to be embedded on the Case Lightning Record Page via App Builder. It displays a visual summary of task statuses associated with a case, giving agents an at-a-glance view of workload distribution and SLA health.

The component is **demo-only**: all data is hardcoded in JavaScript. There are no Apex calls, wire adapters, or SOQL queries.

---

## Files

| File | Purpose |
|---|---|
| `caseTaskStatusPanel.js` | Component logic, mock data, computed properties |
| `caseTaskStatusPanel.html` | Template — layout, SVG donut, tiles, task rows |
| `caseTaskStatusPanel.css` | Component-scoped styles |
| `caseTaskStatusPanel.js-meta.xml` | Metadata config — exposed on `lightning__RecordPage`, scoped to `Case` |

---

## Layout Structure (RTL)

The root element carries `dir="rtl"` to support Hebrew text. The component is wrapped in an `slds-card` and structured as follows, top to bottom:

1. **Header row** — lightning icon (`standard:task`) + title "סטטוס משימות בפנייה" on the right; total task count ("8 משימות") muted on the left.
2. **Donut chart + traffic light row** — SVG donut on the left third, traffic-light pill + summary text on the right two-thirds.
3. **Four count tiles** — one per status, displayed in a responsive SLDS grid (2-up on small screens, 4-up on large).
4. **Three sample task rows** — each row has a colored right border, a status icon, the task name, and a colored status badge.

---

## Donut Chart

Built as a pure SVG — no Chart.js or static resource dependency. The component is fully self-contained.

**Technique:** four `<circle>` elements sharing the same `cx/cy/r`, each using `stroke-dasharray` and `stroke-dashoffset` to paint an arc segment proportional to its count. The SVG is rotated −90° in CSS so segments start at the 12 o'clock position.

**Math (computed in `donutSegments` getter):**
- `radius = 15.9155`, `circumference = 2π × r ≈ 100`
- For each status: `dash = (count / total) × circumference`, `gap = circumference − dash`
- `dashoffset` accumulates the prior segments' dash lengths to position each arc correctly

Segment order: Completed → In Progress → Planned → Overdue.

---

## Mock Data

Defined as class properties in the JS — no `@track` needed (LWC tracks object mutations automatically).

**Status counts:**

| Status | Count |
|---|---|
| Completed | 4 |
| In Progress | 2 |
| Planned | 1 |
| Overdue | 1 |
| **Total** | **8** |

**Sample task rows:**

| Name | Status |
|---|---|
| בדיקת מסמכי הכנסה ואישורים | Completed |
| בחינת מסמכים והערכת זכאות עקרונית | In Progress |
| אבחון תקלת מים בשטח | Overdue |

---

## Status Color and Icon Map

| Status | Color | Icon |
|---|---|---|
| Completed | `#0ca30c` | `utility:success` |
| In Progress | `#199e70` | `utility:spinner` |
| Planned | `#888780` | `utility:date_input` |
| Overdue | `#d03b3b` | `utility:warning` |

Colors are applied as inline styles (border, badge background, icon CSS variable `--sds-c-icon-color-foreground-default`).

---

## Computed Properties (Getters)

| Getter | Returns |
|---|---|
| `totalTasks` | Sum of all status counts |
| `totalTasksLabel` | `"8 משימות"` |
| `tiles` | Array of `{ key, label, count, color, style }` — one per status, drives the four count tiles |
| `tasks` | Array of sample tasks enriched with `statusLabel`, `color`, `icon`, `rowStyle`, `iconStyle`, `badgeStyle` |
| `donutSegments` | Array of `{ key, color, dasharray, dashoffset }` — one per status, drives the SVG circles |
| `trafficLightSummary` | Hardcoded Hebrew summary string |

---

## Traffic Light

Three colored `<span>` dots rendered in CSS:

| Dot | Color |
|---|---|
| Green | `#0ca30c` |
| Amber | `#ffb75d` |
| Red | `#d03b3b` |

Followed by the one-line summary: `"רמזור כללי: בטיפול — קיימת משימה אחת בחריגת SLA"`.

---

## Metadata Config

```xml
<targets>
    <target>lightning__RecordPage</target>
</targets>
<targetConfigs>
    <targetConfig targets="lightning__RecordPage">
        <objects>
            <object>Case</object>
        </objects>
    </targetConfig>
</targetConfigs>
```

`isExposed = true` — the component appears in App Builder's custom component list when editing a Case record page.

---

## Deployment

```bash
sf project deploy start \
  --source-dir force-app/main/default/lwc/caseTaskStatusPanel \
  --target-org <alias>
```

After deploying, add to the Case record page via Setup → Object Manager → Case → Lightning Record Pages → Edit Page → drag `caseTaskStatusPanel` onto the canvas → Save → Activate.

---

## What this component intentionally does NOT do

- No Apex, wire adapters, or live data — all values are hardcoded for demo purposes.
- No Chart.js or external static resource dependency.
- No user interaction or navigation — display only.
- No real SLA calculation — the traffic light and summary are static strings.
