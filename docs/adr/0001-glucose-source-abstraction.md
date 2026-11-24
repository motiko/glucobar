# Read glucose through a swappable Glucose Source, ship only LibreLinkUp

GlucoBar depends on the unofficial LibreLinkUp 4.x API (version header `4.16.0`). Since LibreLinkUp 5.0 (April 2026), Abbott's own app uses an encrypted API, so the 4.x API may be switched off without notice, and breaking the 5.x encryption is not an option. We therefore put readings behind a small Glucose Source interface that the menu bar display and alerting depend on, even though LibreLinkUp is the only implementation today. When the API disappears, adding another Source (e.g. Nightscout) must not touch the display or alert logic.

## Consequences

- "Source unavailable" is an expected, user-visible state, not a crash or a silent stale value.
- The LibreLinkUp version header is configurable, not a constant.
