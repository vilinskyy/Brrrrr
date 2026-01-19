## Publishing / Distribution Checklist (macOS)

This document explains what you need to ship **Brrrrr** to Apple (Mac App Store) or distribute it outside the App Store (signed + notarized). It also marks what **AI can do** in this repo vs what **you must do** in Apple portals / Xcode accounts.

### Assumptions

- Target: **macOS 26+**
- Data policy: **camera only**, **no microphone**, **no network**, **no recording** (live processing only)
- Sandbox: **enabled**

### Current project defaults (in this repo)

- **Bundle ID (current)**: `superclear.Brrrrr` (change it in Xcode → Target → Signing & Capabilities)
- **Developer site**: [vilinskyy.com](https://vilinskyy.com)

---

## Step-by-step walkthrough (publish to BOTH Mac App Store + direct)

You can ship **Brrrrr** in two channels at the same time:

- **Mac App Store**: upload to App Store Connect and release through Apple
- **Direct distribution**: export a separate build signed with **Developer ID**, **notarized**, then share (ZIP/DMG/PKG)

> Note: The App Store build and the direct build typically **cannot both be installed side-by-side** on the same Mac because they are the same bundle id (`superclear.Brrrrr`). In practice you ship both channels, but users install **one**.

### 0) Add your Apple account to Xcode (one-time)

- Open **Xcode**
- Menu: **Xcode** → **Settings…** (or **Preferences…**)
- Click **Accounts**
- Click **+** (bottom-left)
- Choose **Apple ID**
- Sign in
- Select your **Team** (confirm you see your Team in the list)

### 1) Create certificates (one-time)

You need BOTH certificates if you want both channels:

- **Apple Distribution** (for Mac App Store uploads)
- **Developer ID Application** (for direct distribution + notarization)

#### Option A (recommended): create certificates in Xcode

- Xcode → **Settings…** → **Accounts**
- Select your **Apple ID**
- Select your **Team**
- Click **Manage Certificates…**
- Click **+** and create:
  - **Apple Distribution**
  - **Developer ID Application**

Then verify they exist:
- Open **Keychain Access**
- Search for:
  - `Apple Distribution`
  - `Developer ID Application`

#### Option B: create certificates in the browser (Apple Developer)

- Browser → open [Apple Developer Account](https://developer.apple.com/account)
- Click **Certificates, IDs & Profiles**
- Click **Certificates**
- Click **+** (Add)
- Create BOTH (repeat twice):
  - **Apple Distribution**
  - **Developer ID Application**
- Download each `.cer` and double-click to install into Keychain Access

### 2) Configure the Xcode target signing (one-time)

- Open `Brrrr.xcodeproj`
- Click the **Brrrr** project (blue icon) in the left sidebar
- Select **TARGETS** → **Brrrr**
- Click **Signing & Capabilities**
- Set:
  - **Bundle Identifier**: `superclear.Brrrrr`
  - **Team**: your Team
  - **Automatically manage signing**: ON

### 3) Create the App Store Connect app record (one-time)

- Browser → open [App Store Connect](https://appstoreconnect.apple.com)
- Click **Apps**
- Click **+** → **New App**
- Fill:
  - **Platform**: **macOS**
  - **Name**: `Brrrrr` (final store name)
  - **Primary Language**: (pick one)
  - **Bundle ID**: select `superclear.Brrrrr`
  - **SKU**: any unique string, e.g. `brrrr-macos-001`
- Click **Create**

If `superclear.Brrrrr` is missing from the Bundle ID dropdown:

- Browser → open [Certificates, IDs & Profiles (Identifiers)](https://developer.apple.com/account/resources/identifiers/list)
- Click **Identifiers**
- Click **+**
- Choose **App IDs** → **App**
- Choose **Explicit**
- Enter **Bundle ID**: `superclear.Brrrrr`
- Save
- Return to App Store Connect → **New App** and try again

### 4) Archive once, export twice (the “both channels” workflow)

- Xcode → menu **Product** → **Archive**
- In the **Organizer** window, you’ll use the same archive for:
  - **App Store Connect upload** (Mac App Store)
  - **Developer ID export** (direct distribution)

## App identity (Bundle ID, name, versioning)

- [ ] **(You)** Confirm the final **Bundle Identifier** is `superclear.Brrrrr` and set the final **Team** in Xcode → Target → Signing & Capabilities.
- [ ] **(You)** Set a release **Version** + **Build** number (Xcode target → General).
- [ ] **(You / MAS only)** Set the **Application Category** (required for App Store validation):
  - Xcode → Target **Brrrrr** → **Info** → **Application Category**
  - Pick a valid category (UTI), e.g. **Healthcare & Fitness** (`public.app-category.healthcare-fitness`)
- [ ] **(AI)** If you tell me your final Bundle ID / product name, I can update build settings + any strings that reference them.

---

## Signing & entitlements

### Current state in this repo

- App Sandbox + camera access entitlements live in `Brrrr/Brrrr.entitlements`
- Camera usage message is set via `INFOPLIST_KEY_NSCameraUsageDescription`

### What you need

#### For Mac App Store

- [ ] **(You / MAS only)** Ensure “Automatically manage signing” works or create provisioning profiles in the Apple Developer portal.
- [ ] **(You / MAS only)** Ensure an **Apple Distribution** certificate exists.
  - Xcode → **Settings…** → **Accounts** → (Apple ID) → (Team) → **Manage Certificates…** → **+** → **Apple Distribution**
  - Verify in **Keychain Access**: “Apple Distribution: …”
  - If you’re distributing **both** (Mac App Store + direct), complete **both** subsections (“For Mac App Store” and “For direct distribution”).
- [ ] **(AI)** Keep entitlements minimal + correct (sandbox + camera, no mic) and keep the Info.plist privacy message accurate.

#### For direct distribution (outside App Store)

- [ ] **(You)** Create/enable a **Developer ID Application** certificate.
  - Apple Developer → Certificates → **Developer ID Application**
  - Install it in Keychain Access
- [ ] **(You)** Ensure Hardened Runtime is enabled.
  - In this repo it’s already enabled (`ENABLE_HARDENED_RUNTIME = YES`).
- [ ] **(You)** In Xcode → Target → Signing & Capabilities:
  - Pick your **Team**
  - Keep **Automatically manage signing** enabled
  - When exporting, choose **Developer ID** (Xcode will sign the export with your **Developer ID Application** certificate)
- [ ] **(AI)** Provide exact `notarytool` + `stapler` commands (see “Notarization” below).

---

## Privacy requirements (App Store / review readiness)

- [ ] **(You)** Prepare a short, consistent privacy explanation for App Store review and your app listing:
  - Camera is used to detect hand-to-face touches.
  - Processing is on-device.
  - No video is stored/recorded.
  - No microphone access.
  - No network requests.
- [ ] **(You)** If distributing publicly, prepare a simple Privacy Policy page (even “no data collected” apps often provide one).
- [ ] **(AI)** I can draft the Privacy Policy and in-app “Privacy” text if you want.

---

## Build + Archive (Release)

- [ ] **(You)** In Xcode: Product → **Archive** (Release).
- [ ] **(You)** Validate the archive.
- [ ] **(You)** Distribute:
  - **App Store Connect** (MAS)
  - **Developer ID** export (direct distribution)
  - Tip: you can **archive once** and then **export twice** (App Store + Developer ID) from the same archive.

### Click-by-click: upload to Mac App Store (from Xcode)

- Xcode → menu **Product** → **Archive**
- When **Organizer** opens:
  - Click **Archives**
  - Select your latest **Brrrrr** archive
  - Click **Distribute App**
  - Choose **App Store Connect**
  - Choose **Upload**
  - Choose your **Team** when prompted
  - Click through the defaults → **Upload**

Then confirm the build appears:
- Browser → open [App Store Connect](https://appstoreconnect.apple.com)
- Click **Apps** → **Brrrrr**
- Open **TestFlight** (or **Builds**) and wait for processing to complete

### Click-by-click: export a direct build (Developer ID)

- In Xcode **Organizer** → **Archives**:
  - Select the same archive
  - Click **Distribute App**
  - Choose **Developer ID**
  - Choose **Export**
  - Choose an export folder (example: `~/Desktop/Brrrrr-Direct`)
  - After export, you should have `Brrrrr.app` inside that folder (example: `~/Desktop/Brrrrr-Direct/Brrrrr.app`)

### Command-line (optional)

- [ ] **(AI)** I can add a “Release build” command snippet tailored to your exact scheme/setup if you want, e.g.:
  - `xcodebuild archive …`
  - `xcodebuild -exportArchive …`

#### Included templates (AI-provided)

- `ExportOptions-AppStore.plist`
- `ExportOptions-DeveloperID.plist`

#### Example: archive + export (copy/paste)

```bash
set -euo pipefail

PROJECT="/Users/vilinskyy/Brrrr/Brrrr.xcodeproj"
SCHEME="Brrrrr"
OUT="/Users/vilinskyy/Brrrr/build"

rm -rf "$OUT"
mkdir -p "$OUT"

# 1) Archive (Release)
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$OUT/${SCHEME}.xcarchive" \
  archive

# 2a) Export for Mac App Store
xcodebuild \
  -exportArchive \
  -archivePath "$OUT/${SCHEME}.xcarchive" \
  -exportPath "$OUT/export-appstore" \
  -exportOptionsPlist "/Users/vilinskyy/Brrrr/ExportOptions-AppStore.plist"

# 2b) Export for direct distribution (Developer ID)
xcodebuild \
  -exportArchive \
  -archivePath "$OUT/${SCHEME}.xcarchive" \
  -exportPath "$OUT/export-developerid" \
  -exportOptionsPlist "/Users/vilinskyy/Brrrr/ExportOptions-DeveloperID.plist"
```

---

## Notarization (direct distribution only)

You only need this if you distribute outside the App Store.

- [ ] **(You)** Create notarization credentials (choose ONE):
  - **Option A (simplest)**: Apple ID + **app-specific password**
    - Create the password at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords
  - **Option B (best for CI / no app-specific password)**: **App Store Connect API key**
    - Create it in [App Store Connect](https://appstoreconnect.apple.com) → Users and Access → Integrations → App Store Connect API
    - Download the `.p8` key and note **Key ID** + **Issuer ID**
- [ ] **(You)** Notarize:
  - `xcrun notarytool submit <zip-or-dmg> --wait --key <...>`
- [ ] **(You)** Staple:
  - `xcrun stapler staple <YourApp.app | YourDMG.dmg>`
- [ ] **(AI)** I can generate a full “copy/paste” notarization section once you pick ZIP vs DMG vs PKG.

### Example: notarize a ZIP (copy/paste template)

```bash
set -euo pipefail

APP="/Users/vilinskyy/Brrrr/build/export-developerid/Brrrrr.app"
ZIP="/Users/vilinskyy/Brrrr/build/Brrrrr.zip"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# One-time setup (you do ONE of these):
# Option A) Apple ID + app-specific password:
# xcrun notarytool store-credentials "AC_NOTARY" --apple-id "<APPLE_ID>" --team-id "<TEAM_ID>" --password "<APP_SPECIFIC_PASSWORD>"
#
# Option B) App Store Connect API key:
# xcrun notarytool store-credentials "AC_NOTARY" --key "/path/to/AuthKey_<KEY_ID>.p8" --key-id "<KEY_ID>" --issuer "<ISSUER_ID>"

xcrun notarytool submit "$ZIP" --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple "$APP"
```

### Click-by-click: where to create notarization credentials (exact)

You can use **either** Apple ID credentials or an App Store Connect API key.

#### Option A (simplest): Apple ID + app-specific password

- Browser → open [Apple ID](https://appleid.apple.com)
- Sign in
- Click **Sign-In and Security**
- Click **App-Specific Passwords**
- Click **Generate an app-specific password**
- Label: `Brrrrr Notary`
- Copy the generated password (store it somewhere safe)

To find your **TEAM_ID**:
- Xcode → **Settings…** → **Accounts** → select your Team → copy the **Team ID** (10-character id)

#### Option B (best for CI): App Store Connect API key (.p8)

- Browser → open [App Store Connect](https://appstoreconnect.apple.com)
- Click **Users and Access**
- Click **Integrations**
- Click **App Store Connect API**
- Click **Generate API Key**
- Name: `Brrrrr Notary`
- Access: **Developer** (or higher)
- Download the `.p8` key (you can’t download it again later)
- Note:
  - **Key ID**
  - **Issuer ID**

### Manual notarization (Terminal, copy/paste)

1) Store credentials (one-time)

Option A (Apple ID):

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "<APPLE_ID_EMAIL>" \
  --team-id "<TEAM_ID>" \
  --password "<APP_SPECIFIC_PASSWORD>"
```

Option B (API key):

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --key "/absolute/path/to/AuthKey_<KEY_ID>.p8" \
  --key-id "<KEY_ID>" \
  --issuer "<ISSUER_ID>"
```

2) Notarize the app (recommended, even if you ship a DMG)

```bash
set -euo pipefail

APP="/absolute/path/to/Brrrrr.app"
ZIP="/absolute/path/to/Brrrrr.zip"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple "$APP"
```

3) Quick verification (Gatekeeper)

```bash
spctl -a -vv "$APP"
```

### DMG (recommended): build + notarize + staple

If you prefer a DMG (common for website downloads), do this after you’ve stapled the **app** above. This makes:

- the **app** stapled (works offline)
- the **DMG** stapled (opens cleanly in Gatekeeper)

```bash
set -euo pipefail

APP="/absolute/path/to/Brrrrr.app"
WORK="/tmp/Brrrrr-dmg"
STAGING="$WORK/staging"
DMG="/absolute/path/to/Brrrrr.dmg"

rm -rf "$WORK" "$DMG"
mkdir -p "$STAGING"

# Copy the app into a folder that will become the DMG contents
ditto "$APP" "$STAGING/Brrrrr.app"

# Add an /Applications shortcut (so users can drag-drop install)
ln -s /Applications "$STAGING/Applications"

# Create a compressed DMG
hdiutil create -volname "Brrrrr" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

# Notarize + staple the DMG container
xcrun notarytool submit "$DMG" --keychain-profile "AC_NOTARY" --wait
xcrun stapler staple "$DMG"

# Verify DMG is accepted by Gatekeeper
spctl -a -vv --type open "$DMG"
```

---

## App Store Connect submission (Mac App Store)

- [ ] **(You)** In App Store Connect, finish the listing and submit for review (click-by-click below).

### Click-by-click: attach the uploaded build to a version

- Browser → open [App Store Connect](https://appstoreconnect.apple.com)
- Click **Apps** → **Brrrrr**
- Open the **App Store** section (left sidebar)
- If you don’t have a version yet:
  - Click **+ Version** (or **Add Version**) and create the first version
- In the version page, find the **Build** section:
  - Click **Select a build** (or **+**)
  - Choose the build you uploaded from Xcode
  - Save

If you don’t see the build yet:
- Go to **TestFlight** / **Builds** and wait for processing to finish

### Click-by-click: App Privacy (“nutrition label”)

- In your app → open **App Privacy**
- Answer:
  - **Data Collection**: **No, we do not collect data**
  - **Tracking**: **No**
- Save

### Click-by-click: App Review Information

- Open **App Review Information**
- Fill your review contact info
- In **Notes**, paste something like:
  - “Brrrrr uses the camera to detect hand-to-face touches. Processing is on-device. No video is recorded/stored. No microphone access. No network requests.”

### Click-by-click: metadata + screenshots

- Open the version page again and fill the required fields (names vary slightly):
  - **Description**, **Keywords**
  - **Support URL** (example: `https://vilinskyy.com`)
  - **Privacy Policy URL** (publish `PrivacyPolicy.md` on your site and paste that URL here)
  - **Screenshots** (upload the required macOS sizes)

### Click-by-click: submit

- Return to the version page
- Fix any red “Missing Information” warnings
- Click **Submit for Review**
- [ ] **(AI)** I can draft:
  - Description
  - Review notes
  - “What’s New” text
  - FAQ

### Included drafts (AI-provided)

- `AppStoreCopy.md` (description, review notes, FAQ, “What’s New” template)
- `PrivacyPolicy.md` (no-data-collected policy draft)

---

## Pre-flight checks (before shipping)

- [ ] **(You)** Test on a clean machine / new macOS user profile:
  - First-run camera permission flow
  - Menu bar icon + popover UX
  - Settings changes persist
  - Alerts behave (sound/screen modes, cooldown)
- [ ] **(You)** Confirm no microphone permissions are requested and no mic entitlements exist.
- [ ] **(AI)** I can add lightweight runtime logging flags (debug-only) and a small troubleshooting section in docs if useful.

### Included troubleshooting (AI-provided)

- `TROUBLESHOOTING.md`

