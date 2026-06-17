# WhatHappendLastNight

**GGG 2026** — an offline, privacy-first face matcher for finding yourself across a folder of party / event photos.

You take a selfie, point the app at a folder of photos, and it returns the ones that look like you — ranked by similarity. Everything runs locally on your Mac. No uploads, no accounts, no telemetry.

## How it works

1. The app captures a selfie from your webcam (or you drop in an image file).
2. Apple's **Vision** framework detects faces in each photo in the selected folder.
3. A bundled **FaceNet** CoreML model (`Facenet6.mlmodel`) produces a 512-d embedding for each detected face.
4. Cosine similarity against the selfie embedding decides which photos are a match.
5. Results show up in a grid with a similarity score; nothing is written to disk.

## Requirements

- macOS 26.4 or later
- Xcode 26.4 or later (Swift 5.0, project format v77)
- A Mac with a camera (or a selfie image file to drop in)

## Run the app

```bash
git clone <repo-url>
cd WhatHappendLastNight
open WhatHappendLastNight.xcodeproj
```

In Xcode:

1. Select the **My Mac** run destination.
2. Press **⌘R** to build and run.
3. On first launch, accept the in-app privacy notice.
4. Capture a selfie, pick a folder of photos, then press **Find Me**.

Use **View → Appearance** (or **⌘⌥0 / ⌘⌥1 / ⌘⌥2**) to switch between System, Light, and Dark.

## Permissions

The app needs **camera access** to capture your reference selfie. macOS will prompt you the first time you try to take one. If you decline, you can re-enable it later in **System Settings → Privacy & Security → Camera**.

The justification string is already configured in the Xcode target (`INFOPLIST_KEY_NSCameraUsageDescription`). If you ever need to add or change it manually:

1. Open the project in **Xcode**.
2. In the **Project Navigator** (left sidebar), click the top-level project file (blue project icon).
3. Select the target, then the **Info** tab.
4. Under **Custom macOS Application Target Properties**, hover the last row and click the small **`+`** button.
5. Add the key **`Privacy - Camera Usage Description`** (`NSCameraUsageDescription`).
6. In the **Value** column, enter a clear, user-facing message, e.g.:
   *"Camera access is used to capture a selfie for local face matching. Images and biometric embeddings are not uploaded or stored by the app."*

No other system permissions are requested. Folder access uses the standard macOS file picker, so no Full Disk Access entitlement is needed.

## Privacy baseline

- Native matching runs locally with Vision and CoreML.
- The Xcode target disables incoming and outgoing network access.
- Camera access is used only to capture a selfie reference for local matching.
- Selfies, source photos, embeddings, and match results are **not** written to app storage.
- Users must confirm the in-app privacy notice before matching and can clear session state with a single button.

See [PRIVACY.md](PRIVACY.md) before changing data flows, adding analytics, or adding any backend processing.
See [DESIGN_GUIDE.md](DESIGN_GUIDE.md) for the visual system (palette, typography, spacing, accessibility targets).

## Project layout

```
WhatHappendLastNight/
├── WhatHappendLastNightApp.swift   # App entry, menu commands, theme wiring
├── ContentView.swift               # All SwiftUI screens (setup, results, lightbox, sheets)
├── FaceMatcher.swift               # Vision face detection + FaceNet embedding + cosine matching
├── Theme.swift                     # Design tokens (colors, typography, spacing, ScoreTier)
├── Facenet6.mlmodel                # Bundled FaceNet CoreML model
├── PrivacyInfo.xcprivacy           # Apple privacy manifest (no tracking, no collection)
└── Assets.xcassets/                # App icon, accent color
```

## Troubleshooting

- **"FACENET MODEL MISSING"** — `Facenet6.mlmodel` was removed from the target. Re-add it to the app target's *Copy Bundle Resources* phase.
- **"ERROR: CAPTURE CLEAR FRONT SELFIE FACE"** — your selfie didn't have a usable front-facing face. Retake with better light and the face roughly centered.
- **Camera preview is black** — macOS hasn't granted camera permission. Open **System Settings → Privacy & Security → Camera** and enable it for the app.
- **No matches found** — try lowering the strictness slider; the default leans conservative to reduce false positives.
