# GlucoBar

A macOS menu bar app that shows your current glucose next to the clock, using Abbott's
LibreLinkUp follower service, and raises Alerts (sounds, Webhook, Telegram) when it goes out of range.

> **Not a medical device.** GlucoBar uses an unofficial, undocumented API that may stop
> working at any time, and it only runs while your Mac is awake. Keep your phone's CGM app as
> your primary alarm.

## Install

```sh
brew install motiko/tap/glucobar
```

Requires macOS 14+ (Apple Silicon or Intel). Open GlucoBar, choose **Settings…** in its menu, and
sign in with the LibreLinkUp account your Libre app shares its data with.

## Release (maintainers)

`scripts/release.sh <version>` builds a universal app, signs it, publishes a GitHub release and
updates the cask in `motiko/homebrew-tap`. With a Developer ID certificate it also notarizes the
app; without one it signs with Apple Development and the cask clears the quarantine flag on
install. See the script header for the one-time setup. `DRY_RUN=1` builds without publishing.

## Layout

| Path | What |
|---|---|
| `GlucoBarCore/` | SwiftPM library: Glucose Source, Readings, Alerts, Actions, config. Must build on Linux ([ADR 0003](docs/adr/0003-platform-independent-core-package.md)). |
| `App/` | The macOS app (SwiftUI `MenuBarExtra`, Settings, Keychain, sounds). |
| `project.yml` | XcodeGen spec for `GlucoBar.xcodeproj` (generated, not committed). |
| `GLOSSARY.md`, `docs/adr/` | Domain language and decisions. |

## Build

Requires macOS 14+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
swift test --package-path GlucoBarCore   # core tests
xcodegen generate                         # create GlucoBar.xcodeproj
open GlucoBar.xcodeproj                   # or: xcodebuild -scheme GlucoBar build
```

Run with the `-demo` launch argument to see fake Readings without signing in.

## Config

`~/.config/glucobar/config.json` (or `$XDG_CONFIG_HOME/glucobar/config.json`) is the source of
truth; the Settings window edits the same file. Secrets (LibreLinkUp password, bot tokens) live in
the Keychain and the file refers to them by name.

**Sync between Macs:** Settings → General → *Sync settings via iCloud Drive* moves the file to
`iCloud Drive/GlucoBar/config.json` and leaves a symlink at the usual path. Passwords and tokens sync
separately through iCloud Keychain (release builds; turn on iCloud Keychain in System Settings →
your name → iCloud → Passwords). Ad-hoc local builds can't use iCloud Keychain and keep secrets in
the login keychain, so with those sign in once on each Mac.

Glucose values are redacted in the system log unless `"debugLogging": true` (Settings → General →
Debug logging). Watch the log with
`/usr/bin/log stream --level info --predicate 'subsystem == "dev.moti.glucobar"'`.

### Alerts on your phone (ntfy)

[ntfy](https://ntfy.sh) pushes Alerts to the ntfy app on your phone. Pick a long, random topic
name: on the public server anyone who knows it can read your Alerts. Subscribe to it in the ntfy
app. In Settings → Actions choose **Add Action → Phone push (ntfy)** (it suggests a random topic),
tick it under the Alerts that should use it, and press **Send test**. Or in the config file:

```json
"actions": {
  "phone": { "type": "ntfy", "topic": "glucobar-<something-random>" }
},
"alerts": {
  "urgentLow": { "actions": ["urgentSound", "phone"], ... }
}
```

Urgent Low is sent at priority 5 (can break through Do Not Disturb), Low/High at 4, Signal Loss at
3. For a self-hosted server or a protected topic add `"server": "https://ntfy.example.com"` and
`"tokenSecret": "ntfy.token"`, and store the access token in the Keychain:
`security add-generic-password -s dev.moti.glucobar -a ntfy.token -w` (macOS asks once whether
GlucoBar may read it; choose Always Allow). GlucoBar then moves it to iCloud Keychain.
