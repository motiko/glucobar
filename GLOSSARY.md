# GlucoBar

A macOS app that shows the user's own current glucose next to the menu bar clock, using data from Abbott's LibreLinkUp follower service, and raises alerts when it goes out of range.

## Language

**Patient**:
The single person whose sensor data the app shows: the user themself. There is exactly one Patient.
_Avoid_: User (when meaning the data subject), connection

**Follower account**:
The LibreLinkUp account the app signs in with to read the Patient's data.
_Avoid_: LibreLink account (that is the Patient's own app account), login

**Glucose Source**:
Where Readings come from. Today the only Source is LibreLinkUp; others (e.g. Nightscout) may be added.
_Avoid_: provider, backend, API

**Reading**:
One glucose value from the Patient's sensor, with its timestamp and trend.
_Avoid_: BG, measurement, value

**Stale**:
A Reading older than the stale threshold (default 15 minutes); it is still shown but is not trusted as current.
_Avoid_: old, outdated, expired

**Trend**:
The direction and speed the Patient's glucose is moving, as reported by the Source (falling fast, falling, flat, rising, rising fast).
_Avoid_: arrow, direction

**Delta**:
The change in glucose over the last 5 minutes: the latest Reading minus the Reading closest to 5 minutes earlier.
_Avoid_: change, diff

## Alerting

**Alert**:
A condition on the Patient's glucose that GlucoBar watches for: Low, High, Urgent Low, or Signal Loss. A fast Trend on its own is never an Alert.
_Avoid_: alarm, warning, rule

**Trend gate**:
An option on Low or High that lets it fire only while the Trend is falling fast (Low) or rising fast (High), so glucose hovering just past a threshold stays quiet. Urgent Low is never gated.
_Avoid_: filter, fast-trend alert

**Signal Loss**:
The Alert raised as soon as the latest Reading becomes Stale (including when the Glucose Source is unavailable long enough for that to happen).
_Avoid_: no data, disconnect

**Action**:
Something GlucoBar does when an Alert fires: play a sound, send a message, or call an API.
_Avoid_: notification (ambiguous), channel, handler

**Snooze**:
A user-chosen pause (e.g. 15/30/60 minutes) during which an Alert does not repeat its Actions, even though its condition still holds.
_Avoid_: mute, silence, dismiss

**Webhook Action**:
An Action that sends the Alert to a user-configured HTTP endpoint.
_Avoid_: API call, callback

**ntfy Action**:
An Action that pushes the Alert to every phone or computer subscribed to the user's ntfy topic. Urgent Low is sent at the highest priority.
_Avoid_: push, phone alert

**Telegram Action**:
An Action that sends an Alert message to a Telegram chat via the user's own bot.
_Avoid_: messenger, chat notification

**Notification sound** / **Urgent sound**:
The two sound Actions: a normal attention sound, and an insistent one for situations that need immediate response.
_Avoid_: ping, alarm
