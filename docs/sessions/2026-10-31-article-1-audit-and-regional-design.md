# Session: Article 1, data model audit, regional settings design

**Date:** 2026-10-31 (planning session, no Salesforce code changed)
**Repos touched:** `fleetforce-glow-up` (site, pushed to main), `fleetforce-app` (docs only, uncommitted)

## Delivered

- Lisbon lessons learned and action plan; packaging research (core + add-ons); data model audit (Claude Docs, linked from the owner's account).
- Article 1 published to the site repo: `build-buy-or-build-on-a-platform`. Framing: FleetForce is the system, Salesforce the platform; captions are vendor-neutral with numbered footnotes. Live only after Publish in Lovable.
- Work order: `docs/Code Work Orders/FleetForce regional settings and data model foundation.md` (untracked).

## Design decisions

- Governing rule: most specific wins, blank means inherit (vehicle > branch > org default `Fleet_Display_Setting__c`). No inherit/override toggles.
- Branch holds Country (ISO), IANA time zone, Currency, Distance/Volume/Weight units; Country Profile custom metadata pre-fills them.
- Vehicle `Country__c` = registered in (regulations). Operating settings follow the branch. Overrides on vehicle: registration country, distance unit.
- Units stored as entered; `Odometer_Km__c` formula for cross-fleet totals.
- Multi-currency is org-level, cannot be enabled by a package: no static `CurrencyIsoCode` in packaged code; demo org only.
- Per-user display preference is P1.

## Audit findings still open (P1, after the discovery call)

First registration date and emissions, insurance/disposal/cost roll-ups, legal entity and cost center, EU driver licence categories.

## Gotchas

- Source deploy is not package install: the data trust layer exists only on `fleetforce-dev-11` (expires 2026-11-20) until packaged.
- Site: Security and Privacy pages claim "SOC 2, ISO 27001"; reword to "built on certified infrastructure" before a security team reads them.
- Do not name the prospect or her company publicly without consent.
- History: append-only except Queued Work Orders.
