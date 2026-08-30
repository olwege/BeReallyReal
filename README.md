# BeReallyReal

A private, offline-only daily photo journal for iOS. Inspired by BeReal's
"one authentic moment a day" idea, but with zero social features — no
accounts, no sharing, no server. Everything stays on your device.

## What it does

- Sends one random daily notification (within a configurable time window)
  prompting you to take a photo. If you've already taken a photo today,
  the next reminder is scheduled for tomorrow instead of re-firing today.
- Captures a front + back camera photo pair, with pinch-to-zoom on both
  previews (zoom level shown as a temporary on-screen label, e.g. "1.0x").
- Optionally lets you adjust the memory's date/time after capture, before
  saving (behind a dev flag).
- Stores photos locally, organized by date, browsable in a calendar view.
- Supports multiple captures per day if you want more than one moment.
- Browse your memories multiple ways:
  - **Calendar** — month grid with jump-to-month/year picker.
  - **Years ago** — surfaces the closest memory to "N years ago today."
  - **Time Feed** — a scrolling grid of every photo, newest first.
  - **Map** — geotagged photos clustered on a map; tap a pin to see the
    photos taken there.
- Lets you open a memory's saved location in Apple Maps, Google Maps,
  Organic Maps, or OpenStreetMap, or copy the raw coordinates.
- Lets you export a single day, month, year, or your entire archive to
  the system Photos app / share sheet.
- Lets you export a full backup (photos, captions, dates, locations) as
  a single package via the Files app, and import it back in — either
  merging with or replacing your existing data.
- Lets you wipe all stored data.

No network calls, no analytics, no third-party SDKs.

## Status

Early / actively evolving — expect the architecture, storage format, and
UI to change significantly as this gets built out. Not production-ready.

## Requirements

- Xcode (latest stable)
- A physical iPhone for testing camera features — the iOS Simulator has
  no camera, so capture flows can only be verified on-device. Calendar,
  storage, map, and UI logic can be tested in Simulator.
- Free or paid Apple Developer account (free is enough for local
  on-device testing; builds expire after 7 days and need reinstalling
  from Xcode).

## Project structure

```
BeReallyReal/
├── BeReallyRealApp.swift   # app entry point
├── Config.swift            # dev/test flags
├── PhotoMapView.swift      # Map view (clustering, pins, location sheet)
├── Camera/                 # AVFoundation capture, multi-cam preview, zoom UI
├── Notifications/          # local notification scheduling
├── Storage/                # local persistence (PhotoStore) + Settings view
└── Views/                  # SwiftUI screens (Calendar, Camera, Day detail)
icon/                       # LaTeX/TikZ source for generating the app icon
```

A shared Xcode scheme (`BeReallyReal.xcodeproj/xcshareddata/xcschemes`) is
checked in so the project builds consistently via `xcodebuild` or CI, not
just from a local, per-user Xcode configuration.

## Notes for development

- `Config.testModeFastNotifications` (in `Config.swift`) fires a repeating
  reminder every 60 seconds instead of once/day — useful for testing the
  notification flow without waiting for a random daily trigger. Flip back
  to `false` before relying on real daily behavior.
- `Config.allowCaptureDateAdjustment` (in `Config.swift`) shows a date/time
  picker after capture so you can backdate a memory. Off by default in
  production use cases.
- Camera capture requires `NSCameraUsageDescription` in Info.plist.
  Photo export requires `NSPhotoLibraryAddUsageDescription`. Location
  tagging requires `NSLocationWhenInUseUsageDescription`.
- Multi-camera (front + back simultaneous) capture requires
  `AVCaptureMultiCamSession.isMultiCamSupported` — not available on every
  device; a sequential-capture fallback may be added later for
  compatibility.
- Photos are captured with HEVC (when available) at high quality
  prioritization, and stored/thumbnailed with downsampled, cached
  renders to keep the calendar and map scrolling smooth.
- Backups are exported as a `.bereallyrealbackup` package (a manifest
  plus an images folder) via the system document picker, so they can be
  moved between devices without any network access. An older single-file
  binary plist format is also supported for import.

## License / privacy

Personal project. All data stays on-device; nothing is transmitted
anywhere.
