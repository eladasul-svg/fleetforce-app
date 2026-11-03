# Session: Data trust teaser video

**Date:** 2026-11-02
**Org:** `fleetforce-dev-12` (sample data only)
**Repo:** `fleetforce-app`, uncommitted (the user commits)

## Delivered

- `docs/media/fleetforce-data-trust-teaser.mp4`: 50.2 s, 1920x1080, H.264, 30 fps, 8.2 MB, no audio.
- `docs/media/fleetforce-data-trust-teaser-poster.jpg`: REF-3's Data Health tab (45, stale streams, alerts).
- Not uploaded or published; `docs/media/` stays untracked.

## Timeline

| Time      | Beat                                                                                                                                                       | Caption                                         |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| 0:00-0:10 | Home, then its Fleet Exposure tab                                                                                                                          | One view of fleet data health                   |
| 0:10-0:20 | Cursor over open data gaps, recall alerts, vehicles at risk, average fleet health                                                                          | Where is the data late, missing or conflicting? |
| 0:20-0:41 | Recall "rear axle bolt" drill-down (45 / 80 / 100 visible), REF-3 Data Health: gauge, parts, three stale Webfleet streams, alerts; Webfleet vendor account | Each score says why                             |
| 0:41-0:46 | REF-1 Data Health, 100 Healthy                                                                                                                             | Same check, healthy vehicle: 100                |
| 0:46-0:50 | Closing card "FleetForce · sample data", fleetforce.info                                                                                                   | (pill only)                                     |

"Sample data" pill at the bottom of every frame. Page loads are cut out (hard cuts at each navigation).

## Before filming

- Seed was two days old: re-ran `data_trust_seed.apex`. REF-1 / REF-2 / REF-3 = 100 / 80 / 45 (SOQL).
- Fixed, deployed to dev-12, in release notes "Next version": Data Health missing spaces (LWC strips whitespace between template nodes, now `&nbsp;`); Fleet Map Explorer list icon had zero width because `fleetVehicleImage`'s `:host` sets `container-type: inline-size` (overridden on `.row__icon`).
- Reported to the user, handled by them: REF-3's driver (Wyatt Travis) had a Deadpool image as photo; swapped in the UI.
- With the user's go: dev-12 user Locale iw_IL → en_US for the recording (Hebrew month names in the notices table, alerts and activity), then back to iw_IL.

## Method

Playwright 1.58.2 (matches the cached Chromium 1208), headless, 1920x1080. Frames from the Chrome screencast (JPEG 92), dropped while pages load; caption bar, drawn cursor with click ring and closing card are injected into the page. Encoded by a Swift AVFoundation script, since Playwright's bundled ffmpeg only has VP8/WebM and no other ffmpeg is installed. Scripts and steps in `scripts/video/`. How the October driver walkthrough was made is not recorded anywhere.

## Gotchas

- Lightning console keeps hidden workspace tabs in the DOM: scope locators with `.filter({ visible: true })`, and target the stream's vendor link with `a[data-id]`.
- Vendor links open as a console subtab.
- The dev-12 user's email is real (shown only in the profile menu, never opened). Header shows "User User".
- Small data oddities visible but not changed: REF-3's driver branch is Lisbon Central HQ while the vehicle is at Tel Aviv Satellite, with a Texas CDL.
