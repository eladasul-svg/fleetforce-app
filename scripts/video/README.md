# Screen videos

How `docs/media/fleetforce-data-trust-teaser.mp4` was made (2026-11-02). Playwright drives headless Chromium at
1920x1080 and saves Chrome screencast frames (page loads are cut out); a Swift script encodes them to H.264 MP4 with
AVFoundation, since Playwright's bundled ffmpeg only writes VP8/WebM. The caption bar, cursor and closing card are
injected into the page.

```bash
mkdir -p /tmp/rec && cd /tmp/rec && npm init -y && npm install playwright@1.58.2
swiftc -O <repo>/scripts/video/encode_frames.swift -o encode
URL=$(sf org open -o fleetforce-dev-12 --url-only --json | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['url'])")
node <repo>/scripts/video/record_data_trust_teaser.mjs "$URL" /tmp/rec/frames   # writes frames + manifest.json
./encode /tmp/rec/frames <repo>/docs/media/fleetforce-data-trust-teaser.mp4 2000000
```

Before recording: re-run `scripts/apex/data_trust_seed.apex` if the seed is more than a day old, and set the user's
Locale to en_US (dev-12's user is iw_IL, which shows Hebrew dates). The reference vehicle ids are hard-coded at the
top of the recorder; the seed prints the current ones. The recorder never clicks Acknowledge or Create task.
