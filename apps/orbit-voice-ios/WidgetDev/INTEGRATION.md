# Issue #119 — WidgetKit integration and validation

The `VoiceAgent` app now embeds the `SchoolTasksWidgetExtension` target. The widget is a
read-only checklist for **overdue unfinished tasks** and **all current-week tasks**. It
supports only `systemSmall` and `systemMedium`; it does not show later tasks, calendar
events, or Gymnasium events.

## Target membership

- `VoiceAgent/App/SchoolTasksWidgetProjection.swift` and `SchoolTasksWidgetSnapshot.swift`
  belong to the Main Orbit app. The projection calls the canonical
  `SchoolHubLogic.taskSections` and `effectiveTaskDay` logic.
- `WidgetDev/SchoolTasksWidget.swift` and the shared snapshot DTO belong to the extension.
- `WidgetDev/SchoolTasksWidgetPublisher.swift` belongs only to the Main Orbit app.
- The widget extension has no network client, app credentials, device token, or task-write
  path. Row checkboxes are display-only; opening a task uses the authorized app route.

## Shared data and identity

Both targets declare `group.net.opik.orbit.voice`. The app writes only a minimized task
snapshot after successful School Hub reads for a resolved profile scope. It clears the
snapshot on scope reset, logout, pairing removal, profile/impersonation changes, denied
school read permission, or failed authorization. A failed/incomplete refresh does not
publish cached task rows. The extension accepts snapshots no older than 12 hours and
rejects a snapshot after the Monday school-week rollover.

CI builds do **not** prove that SideStore preserves the App Group entitlement or that the
signed extension can read the app's value. The owner will verify that on a physical
iPhone after the normal guarded Main Orbit publication. Keep App Group sharing marked
unverified until that test has actually passed.

The focused layout contract uses the iPhone 12 medium-family size of 338×158 pt from
[Apple's Widget HIG](https://developer.apple.com/design/human-interface-guidelines/widgets)
and the widget's 11 pt vertical inset, leaving 136 pt for content. Its standard text
budget fits the reference fixture's one overdue plus four current-week rows; larger
accessibility text intentionally reduces the row budget and exposes overflow.

## CI coverage and limits

The macOS workflow runs focused projection and route tests, builds the Main Orbit app plus
extension for iPhone 12 Simulator, and builds/packages the normal Release IPA. Simulator/
native build evidence is not physical-device or SideStore-signing acceptance. No Mini
target, backend, ACL, or DB change is part of this integration.
