# Privacy Notice

Last updated: 2026-06-17

What Happened Last Night is designed as an offline-first face matching tool. This notice documents the privacy behavior implemented in this repository; it is not a substitute for legal review before public release.

## Data processed

The native macOS app may process:

- A selfie selected or captured by the user.
- Image files from a folder selected by the user.
- Temporary face detections, face crops, FaceNet embeddings, similarity scores, and local match results.
- Local file paths for matched images so the app can show thumbnails and reveal files in Finder.

The React prototype may process:

- Demo face selections and demo event selections.
- Custom images selected by the user as temporary browser object URLs for preview only.

## Purpose

The app processes the above data only to compare a user-selected reference selfie against user-selected photos and display possible local matches.

## Local processing and transfers

The native macOS app performs matching locally with Vision/CoreML. Its Xcode entitlements disable incoming and outgoing network connections. The app does not upload selfies, selected photos, face embeddings, or match results.

The React prototype no longer sends custom selfies or photos to `/api/match`. Custom photo matching is disabled in the browser prototype to avoid uploading personal images without an audited backend and data processing agreement.

## Storage and retention

The native macOS app keeps selfies, embeddings, and match results in memory during the session. It does not write selfies, source photos, embeddings, or match results to app storage. The Clear Session control removes in-memory state.

The React prototype keeps custom image previews as temporary object URLs and revokes them when the browser session is cleared or custom files are removed.

## User control

Users can:

- Choose whether to provide a selfie or source folder.
- Confirm consent before native face matching runs.
- Cancel a native scan while it is running.
- Clear the native session state.
- Clear browser prototype session state.

## Logging

The native app no longer logs personal photo filenames or similarity scores during matching. Debug-only errors may report that one selected file was skipped without naming the file.

## Third parties

The React prototype does not import Google Fonts or other third-party tracking scripts. Production builds should keep fonts self-hosted or system-based unless a separate disclosure and legal basis are added.

## Before public release

Before App Store, TestFlight, or public web release, complete a legal GDPR review covering controller identity, lawful basis, explicit consent requirements for biometric processing, data subject rights, DPIA requirements, age restrictions if relevant, security controls, and any processor agreements.