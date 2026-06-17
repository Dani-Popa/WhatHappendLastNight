# WhatHappendLastNight

GGG 2026 - WhatHappendLastNight

Offline-first local face matching for user-selected photos.

## Privacy baseline

- Native matching runs locally with Vision/CoreML.
- The Xcode target disables incoming and outgoing network access.
- Camera access is used only to capture a selfie reference for local matching.
- Selfies, source photos, embeddings, and match results are not written to app storage.
- Users must confirm the in-app privacy notice before matching and can clear session state.
- The React prototype does not upload custom images for matching; custom files remain browser-local previews.

See [PRIVACY.md](PRIVACY.md) before changing data flows, adding analytics, or adding any backend processing.
