# Privacy Notice — What Happened Last Night

Last updated: 2026-06-18
Version: 2.1 (GDPR-aligned)

This notice describes how the **What Happened Last Night** macOS app processes personal data, including biometric data, under the EU General Data Protection Regulation (GDPR, Regulation (EU) 2016/679).

The app is designed as an offline, on-device face matcher: a user provides a selfie and points the app at a folder of their own photos, and the app shows which of those photos appear to contain that person. **No data ever leaves the device.** This notice documents that behaviour and the GDPR safeguards built into the app.

This document is provided in good faith but is not a substitute for independent legal review before any commercial distribution.

---

## 1. Data Controller

For the on-device data flow, the **end user running the app is the data controller** of their own selfie and the photos they select. The app itself acts neither as controller nor as processor in the GDPR sense, because no personal data is transmitted to or stored by any third party.

For questions about this notice or the app's design:
- **Repository:** github.com/Dani-Popa/WhatHappendLastNight
- **Context:** GGG 2026 hackathon project
- **Contact for privacy questions:** open an issue in the GitHub repository above

(If you fork or redistribute this app under your own name or organisation, replace the contact details above and review the controller assignment with a lawyer in your jurisdiction.)

---

## 2. Data we process

The native macOS app may process the following data **only in memory, only for the duration of a session**:

- A selfie captured by the user via the built-in camera, or an image file the user selects/drops in.
- The file path of that selfie.
- Image files inside a folder the user explicitly selects.
- Faces detected by Apple Vision in those images (face crops).
- 512-dimensional FaceNet embeddings derived from each detected face. These embeddings are **biometric data** within the meaning of GDPR Article 4(14) and a **special category of personal data** within the meaning of Article 9(1).
- Cosine similarity scores between the selfie embedding and each detected face embedding.
- Local file paths of matched images, used solely to render thumbnails and to "reveal in Finder".

Pictures of identifiable people that appear in the selected folder are personal data of those people.

---

## 3. Purpose

The data above is processed only to:

- Detect faces in the user's selected photos.
- Compute a similarity between the user's selfie and each detected face.
- Show the user which of their photos most likely contain the person in the selfie.

No profiling in the GDPR Art. 22 sense, no automated decision-making producing legal effects, no advertising, no enrichment, no model training.

---

## 4. Lawful basis (Articles 6 and 9)

| Data | Lawful basis |
| --- | --- |
| The user's own selfie and selected photos | Art. 6(1)(a) — consent |
| Biometric data (FaceNet embeddings) | **Art. 9(2)(a) — explicit consent** |
| Faces of third parties incidentally present in the user's photos | Art. 6(1)(f) — legitimate interest of the user to organise their own photo library, balanced against the fact that all processing is local, ephemeral, and not disclosed to any third party. The user remains controller and is responsible for any onward use. |

Explicit consent is obtained inside the app before any biometric processing begins (see §8).

---

## 5. Local processing only

- All face detection runs on-device via Apple **Vision**.
- All face embeddings run on-device via a bundled **FaceNet CoreML model** (`Facenet6.mlmodel`).
- The app target has both incoming and outgoing network connections **disabled at the macOS App Sandbox level** (`ENABLE_APP_SANDBOX=YES`, `ENABLE_INCOMING_NETWORK_CONNECTIONS=NO`, `ENABLE_OUTGOING_NETWORK_CONNECTIONS=NO`).
- The Apple Privacy Manifest (`PrivacyInfo.xcprivacy`) declares: no tracking, no tracking domains, no collected data types, no accessed-API types beyond those required for local matching.

There are therefore no cross-border transfers under Chapter V of the GDPR, because no data leaves the device.

---

## 6. Storage and retention

- Selfies, source photos, face crops, embeddings, similarity scores, and match results are held **only in process memory** for the duration of the session.
- The app does **not** write any of the above to:
  - app sandbox storage
  - `UserDefaults`
  - Keychain
  - CoreData / SQLite / any database
  - the system clipboard
- The app does **not** copy or duplicate any of the user's source photos.
- Pressing **Clear Session** immediately drops the selfie, the folder reference, the results, and resets both consent flags.
- Closing the app deallocates everything.

Retention period: **session-only.** There is no persistent retention.

---

## 7. Your rights under the GDPR

Because no personal data is stored or transmitted, all data-subject rights are effectively satisfied by the app's design:

| Right | How it is satisfied |
| --- | --- |
| Art. 15 — Access | All processed data is visible in the running app; nothing is held server-side. |
| Art. 16 — Rectification | Replace the selfie or change the source folder. |
| Art. 17 — Erasure ("right to be forgotten") | Press **Clear Session** or quit the app. |
| Art. 18 — Restriction | Press **Cancel scan** at any time. |
| Art. 20 — Portability | Not applicable — no structured personal data is stored by the app. |
| Art. 21 — Objection | Do not start a scan, or press Cancel / Clear. |
| Art. 22 — Automated decision-making | No solely-automated decision producing legal or similarly significant effects is made. |
| Art. 7(3) — Withdraw consent | Press **Clear Session**. Withdrawal stops further processing immediately and does not affect the lawfulness of processing carried out before withdrawal. |

The user has the right to lodge a complaint with the supervisory authority in their EU member state (Art. 77).

---

## 8. Consent flow inside the app

Before any biometric processing can start, the user must tick **"I give explicit consent to on-device biometric processing for this session (GDPR Art. 9(2)(a))."**

The **Find Me** button is disabled until that box is ticked and a selfie and folder are selected. If the user presses Find Me without consenting, the full Privacy Notice sheet opens automatically.

Consent is **per-session**: pressing Clear Session, or quitting the app, resets the flag. There is no "remember my consent" option.

---

## 9. Third parties

The app does **not**:

- contact any backend, API, telemetry, analytics, advertising, or attribution service;
- bundle any third-party SDK that performs network I/O;
- load any third-party fonts, scripts, or web assets;
- share data with any processor or sub-processor.

Apple Vision and CoreML are first-party macOS frameworks that run entirely on-device and are not data processors in the GDPR sense.

---

## 10. Logging

Debug logs (only emitted in `DEBUG` builds) do **not** include:

- personal photo filenames,
- similarity scores,
- embedding values,
- the user's selfie filename when image decoding fails.

The app logs the FaceNet model filename at startup and a generic "skipped one selected file" notice on per-file decoding errors.

---

## 11. Security controls

- macOS App Sandbox enabled.
- Network entitlements disabled (inbound and outbound).
- Camera entitlement (`NSCameraUsageDescription`) requested only when the user explicitly captures a selfie.
- File access limited to user-selected files/folders via the standard `NSOpenPanel`; no Full Disk Access entitlement.
- No persisted secrets, tokens, or credentials.
- Privacy Manifest (`PrivacyInfo.xcprivacy`) shipped with the app.

---

## 12. Data Protection Impact Assessment (DPIA)

Because the app processes biometric data, GDPR Art. 35(3)(b) makes a DPIA appropriate even for the on-device design. A summary of the DPIA inputs:

- **Necessity & proportionality:** the only way to compare a face against a folder of photos with the user's stated purpose is to compute and compare facial embeddings. The app uses the minimum data possible (one embedding per detected face, discarded at session end).
- **Risks identified:** unauthorised disclosure of selfie or embeddings (mitigated by no I/O outside the device); incidental processing of third-party faces in the user's photos (mitigated by ephemeral, on-device, non-disclosed processing). The app does **not** verify the age of the user; distributors that intend to make the app available to minors must add an age-gate and parental-consent flow (GDPR Art. 8(2)) before doing so.
- **Residual risk:** low for the documented on-device use case. Risk would materially increase if a future version added any network egress, cloud sync, photo upload, or shared model training — any such change requires a fresh DPIA and a fresh privacy notice.
- **Measures:** sandboxed network-off binary, explicit Art. 9(2)(a) consent, session-only retention, no third parties, no analytics, debug-only logs scrubbed of personal identifiers.

This summary is not a substitute for a formal DPIA signed off by a Data Protection Officer where one is required.

---

## 13. Changes to this notice

Material changes will bump the version number at the top of this file and the `Last updated` date. Distributors are responsible for re-surfacing the updated notice to existing users before resuming biometric processing.

---

## 14. Before any commercial or wider distribution

The on-device design above is robust, but the following items remain the **distributor's** responsibility before any non-personal release (App Store, TestFlight, public web build, paid app, employer-deployed build):

- Confirm controller identity for the relevant jurisdiction.
- Obtain a formal DPIA sign-off where required by the supervisory authority.
- Add an age-gate and, where required, a parental-consent flow (GDPR Art. 8) — this version of the app does not verify the user's age.
- Localise this notice into the languages of the user base.
- Add a clear in-app link to the published privacy notice and to contact information for the controller.
- Re-audit if **any** data leaves the device.
