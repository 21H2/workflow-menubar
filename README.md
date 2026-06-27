# GitHub Workflows — macOS Menu Bar App

---

## For end users

1. Get **`GitHub Workflows.app`** (from whoever built/shipped it) and drag it to
   `/Applications`.
2. Launch it — a **gear icon** appears in the menu bar.
3. Click it → **Sign in with GitHub**. A code is copied to your clipboard and
   `github.com/login/device` opens. Paste the code, authorize, done.
4. Your running workflows show up with progress bars. Click one to open it on GitHub.

Use the **`…` menu** (bottom-right) for Preferences (launch at login, refresh
interval, repo scan depth), Sign out, or Quit.

> First launch on another Mac: because the app is ad-hoc signed (not notarized),
> macOS Gatekeeper may warn. Right-click the app → **Open** → **Open**, once.
> For wide distribution, sign & notarize with a Developer ID (see below).

---

## For whoever ships it (you)

The app needs **one** thing baked in: your GitHub OAuth App's **Client ID**.
A device-flow Client ID is **not a secret**, so it's safe to embed.

### 1. Create the OAuth App (one-time, ~1 min)

At **https://github.com/settings/developers** → **New OAuth App**:

| Field | Value |
|-------|-------|
| Application name | `GitHub Workflows` (shown on the authorize screen) |
| Homepage URL | your repo/site, e.g. `https://github.com/you/workflows-menubar` |
| Application description | `Menu bar app to monitor your running GitHub Actions workflows.` |
| Authorization callback URL | `https://github.com` (required field, unused by device flow) |

Register it, then **check “Enable Device Flow”** and save. Copy the **Client ID**.

### 2. Bake in the Client ID — pick one:

**Option A — build-time env var (recommended, no file edits):**
```bash
GH_CLIENT_ID=Iv1.your_client_id ./build-app.sh
```

**Option B — edit the source:** set `bakedInClientID` in
`Sources/WorkflowsMenuBar/Config.swift`, then `./build-app.sh`.

> If no Client ID is baked in, the app falls back to an in-app "enter Client ID"
> screen (handy for development).

### 3. Build

```bash
./build-app.sh        # → build/GitHub Workflows.app  (icon auto-generated)
```

Ship `build/GitHub Workflows.app` (zip it, or wrap in a DMG).

### Sign & notarize for real distribution (optional)

Ad-hoc signing works locally but triggers Gatekeeper on other Macs. With an Apple
Developer ID:
```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" "build/GitHub Workflows.app"
xcrun notarytool submit "GitHub Workflows.app.zip" --apple-id you@x.com \
  --team-id TEAMID --password APP_SPECIFIC_PW --wait
xcrun stapler staple "build/GitHub Workflows.app"
```

---

## How it works

| File | Role |
|------|------|
| `WorkflowsApp.swift` | `MenuBarExtra` entry point + menu bar label/count |
| `ContentView.swift` | Popover UI: sign-in, device-code, run list, Preferences |
| `AppState.swift` | Auth/polling state machine, launch-at-login, repo scan |
| `GitHubAPI.swift` / `GitHubModels.swift` | Device flow + REST calls |
| `Config.swift` | Baked-in Client ID + OAuth scope |
| `Keychain.swift` | Access token storage (login keychain) |
| `build-app.sh` / `make-icon.sh` | Build/bundle + icon generation |

GitHub has no single "all my running workflows" endpoint, so the app lists your
most-recently-pushed repos (default 40, adjustable in Preferences) and queries each
for `in_progress`/`queued` runs (max 6 concurrent requests), then reads each run's
jobs for progress.

## Requirements

- macOS 13+ (Ventura or later)
- Swift toolchain — Xcode or Command Line Tools (`xcode-select --install`)
