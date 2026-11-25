# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

## Users

People with diabetes who wear an Abbott Libre sensor and want their own current glucose in view
while working on a Mac, without picking up their phone. The maintainer is one of them; GlucoBar is
an open-source side project for people like him, not a commercial product. In the app's language
the user is the **Patient**: exactly one person, whose own sensor data is shown.

## Product Purpose

GlucoBar puts the Patient's current Reading, Trend and Delta next to the menu bar clock and raises
Alerts (Low, High, Urgent Low, Signal Loss) through sounds, phone push (ntfy), Webhook or Telegram
when glucose goes out of range. Success: a glance at the menu bar answers "where am I and where am I
heading", and an out-of-range moment is never missed while the Mac is awake.

## Positioning

A glanceable, ambient readout that lives where the Mac already shows time, rather than another app
window or phone alarm. It reads the LibreLinkUp follower service, so it needs no extra hardware.

## Operating Context

- Menu bar only (`LSUIElement`): no Dock icon, no main window. Surfaces are the menu bar item, its
  dropdown, the Settings window (Account, Display, Alerts, Actions, General), notification banners
  and permission prompts.
- Installed with Homebrew (`brew install motiko/tap/glucobar`), released as a notarized Developer
  ID app; distributed from GitHub (`motiko/glucobar`).
- Config is a human-editable JSON file (`~/.config/glucobar/config.json`), optionally synced via
  iCloud Drive; secrets live in (iCloud) Keychain.
- Used during focused desk work, at any hour, in light or dark mode.

## Capabilities and Constraints

- Glucose Source today: LibreLinkUp only (Nightscout may come later).
- Platform-independent core (GlucoBarCore) for a planned always-on alert relay.
- Not a medical device; uses an unofficial, undocumented API; only alerts while the Mac is awake.
- Terminology is fixed in GLOSSARY.md (Patient, Reading, Trend, Delta, Stale, Alert, Action...).
- macOS 14+; the app currently ships with no icon.

## Brand Commitments

- Name: **GlucoBar**. Bundle ID `dev.moti.glucobar`.
- Must not look medical or official: nothing implying an Abbott/Libre product, a certified medical
  device, or clinical authority.
- No blood-drop, syringe or similar diabetes-category clichés.
- Icons follow current macOS (Tahoe) icon conventions: Apple's icon grid and the layered Icon
  Composer format with light, dark, tinted and clear appearances.
- Icon surfaces to serve: Finder / Applications / Spotlight / Login Items, Settings window and
  notification banners, GitHub README and release pages, and a monochrome menu bar glyph for states
  without a Reading (e.g. signed out).

## Evidence on Hand

- README.md, GLOSSARY.md and docs/adr/ describe the product and its decisions.
- No existing logo, icon, screenshots or brand assets. No users' testimonials or metrics; do not
  invent any.

## Product Principles

1. The number is the product: the Patient's current Reading is always the first thing seen.
2. Calm until it matters: ambient by default, unmistakable when an Alert fires.
3. Honest about limits: never imply medical-grade reliability or official status.
4. Plain, editable, owned by the user: config as a file, secrets in the user's own Keychain.

## Accessibility & Inclusion

Readings and Alerts must not rely on colour alone (in-range / low / high must also differ in text or
shape); glucose values are health data and are redacted from logs by default.
