# FleetForce data trust teaser video

Nov 2, 2026 · @Elad Asulin · for Code

A 45 to 60 second screen recording that gets sent by email, as a link, to a prospect (procurement lead at a pharma company) before a live demo. Purpose: show in one minute that every vehicle carries a data quality score and the reason behind it.

## Where to record

`fleetforce-dev-12` (30-day scratch org, created for the conference follow-up). First confirm the data trust layer and sample data are present (Fleet Exposure tab opens and the reference vehicles score 100 / 80 / 45). If not, run `./scripts/data_trust_setup.sh fleetforce-dev-12`. `fleetforce-dev-11` expires 2026-11-20 and is the fallback. Use the seeded sample data and the reference vehicles from `docs/data-trust/seed-README.md`. Do not use or create any real customer data.

## Before recording

1. Hand-check the Fleet Exposure screen and both reference vehicles for visual problems (empty tiles, broken icons, stale seed dates, wrong scores). Fix or report anything off before filming. Reference scores must be 100 / 80 / 45.
2. Re-run the seed first if dates look stale, so streams show as they do in the README demo script.
3. Hide anything personal: use a clean browser profile, no bookmarks bar, no notifications, no real name or email visible in the header if avoidable.

## Beats (target 50 seconds)

1. **0:00-0:10, Home screen / Fleet Ops.** Land on the Home view, then open Fleet Exposure. Caption: "One view of fleet data health".
2. **0:10-0:20, KPI tiles.** Pause on the tiles (open data gaps, recall alerts, vehicles at risk, average fleet health). Caption: "Where is the data late, missing or conflicting?".
3. **0:20-0:40, Vehicle at risk (REF-3, score 45).** Open it from the recall drill-down. Show the gauge, Freshness / Completeness / Consistency, the stale telematics streams and the alert. Click a vendor name to show the vendor account. Caption: "Each score says why".
4. **0:40-0:50, Contrast and close.** Open the 100-score vehicle briefly, then end on a held frame with the text "FleetForce · sample data" and fleetforce.info.

## Constraints

- Caption on screen at all times, bottom of frame: "Sample data". No voiceover, no music.
- 1920x1080, H.264 MP4, under 15 MB, with a poster image (same convention as `docs/media/fleetforce-driver-walkthrough.mp4`).
- Smooth cursor movement, no typing errors, no scrolling jerks. Slow clicks and one-second pauses on the key screens.
- Do not click Acknowledge or Create task (it writes data and stamps a user name).
- Do not mention any customer, prospect or partner name in the video, file name or captions.

## Output

Put the MP4 and poster in `docs/media/` (untracked on purpose) and report the exact paths and the final length. Do not publish or upload anywhere; the owner chooses the host.

## Done when

The video plays end to end with no visual glitches, the three reference scores are visible where expected, and a history entry and session file are written.
