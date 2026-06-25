# Making a .dmg from Xcode

Xcode produces the `.app`. `make-dmg.sh` wraps it in a drag-to-install `.dmg`.

## One-time: archive and export the .app from Xcode

1. Open `WhatHappendLastNight.xcodeproj` in Xcode.
2. Select **Any Mac (Apple Silicon, Intel)** (or **My Mac**) as the run destination.
3. **Product → Archive**. When the build finishes, Organizer opens.
4. Select the archive → **Distribute App** → **Custom** → **Copy App** → choose a folder.
5. Xcode writes a folder like `WhatHappendLastNight 2026-06-25 22-59-19/` containing `WhatHappendLastNight.app`.

## Package the .app into a .dmg

From the repo root:

```bash
./scripts/make-dmg.sh "/path/to/WhatHappendLastNight.app"
```

Output: `dist/WhatHappendLastNight-<version>.dmg` (version comes from the app's `CFBundleShortVersionString`).

The dmg contains the app plus an `/Applications` shortcut — users drag the icon across to install.

## Optional: auto-run after every Archive

Wire `make-dmg.sh` into the Archive scheme so each Archive emits a dmg without leaving Xcode.

1. **Product → Scheme → Edit Scheme…**
2. Expand **Archive** in the left sidebar → click **Post-actions**.
3. Click **+** → **New Run Script Action**.
4. **Provide build settings from:** WhatHappendLastNight.
5. Shell: `/bin/bash`. Script:

   ```bash
   "${PROJECT_DIR}/scripts/make-dmg.sh" "${ARCHIVE_PATH}/Products/Applications/WhatHappendLastNight.app"
   ```

6. Close. Now `Product → Archive` drops the dmg in `dist/`.

## Signing notes

The dmg inherits whatever signing the `.app` had:

- **Ad-hoc / unsigned** — runs on the build machine. On other Macs, users right-click → **Open**, or run `xattr -dr com.apple.quarantine /Applications/WhatHappendLastNight.app`.
- **Developer ID** — distributable. For Gatekeeper-clean delivery, notarize the dmg too:

  ```bash
  xcrun notarytool submit dist/WhatHappendLastNight-1.0.dmg \
      --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD --wait
  xcrun stapler staple dist/WhatHappendLastNight-1.0.dmg
  ```

## Where the dmg lands

- `dist/` is **gitignored** — local builds stay out of the repo.
- To version a dmg in git, copy it into `releases/` (whitelisted in `.gitignore`).
- For distribution, prefer GitHub Releases: `./scripts/release.sh v1.0.0` (requires `gh`).

## Requirements

- macOS with Xcode installed (uses built-in `hdiutil` and `PlistBuddy`).
- No third-party tools needed.
