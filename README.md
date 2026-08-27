# BeReallyReal

A private, offline-only daily photo journal for iOS. Inspired by BeReal's
"one authentic moment a day" idea, but with zero social features — no
accounts, no sharing, no server. Everything stays on your device.

## What it does

- Sends one random daily notification (within a configurable time window)
  prompting you to take a photo.
- Captures a front + back camera photo pair.
- Stores photos locally, organized by date, browsable in a calendar view.
- Supports multiple captures per day if you want more than one moment.
- Lets you export a single day, month, year, or your entire archive to
  the system Photos app.
- Lets you wipe all stored data.

No network calls, no analytics, no third-party SDKs.

## Status

Early / actively evolving — expect the architecture, storage format, and
UI to change significantly as this gets built out. Not production-ready.

## Requirements

- Xcode (latest stable)
- A physical iPhone for testing camera features — the iOS Simulator has
  no camera, so capture flows can only be verified on-device. Calendar,
  storage, and UI logic can be tested in Simulator.
- Free or paid Apple Developer account (free is enough for local
  on-device testing; builds expire after 7 days and need reinstalling
  from Xcode).

## Project structure

```
BeReallyReal/
├── Models/          # data types (DailyPhoto, etc.)
├── Storage/         # local persistence (PhotoStore)
├── Views/           # SwiftUI screens
├── Camera/          # AVFoundation capture + preview
├── Notifications/   # local notification scheduling
├── Export/          # export to Photos
└── Config.swift     # dev/test flags
```


## Notes for development

- `Config.testModeFastNotifications` (in `Config.swift`) fires a repeating
  reminder every 60 seconds instead of once/day — useful for testing the
  notification flow without waiting for a random daily trigger. Flip back
  to `false` before relying on real daily behavior.
- Camera capture requires `NSCameraUsageDescription` in Info.plist.
  Photo export requires `NSPhotoLibraryAddUsageDescription`.
- Multi-camera (front + back simultaneous) capture requires
  `AVCaptureMultiCamSession.isMultiCamSupported` — not available on every
  device; a sequential-capture fallback may be added later for
  compatibility.

## License / privacy

Personal project. All data stays on-device; nothing is transmitted 
anywhere.
