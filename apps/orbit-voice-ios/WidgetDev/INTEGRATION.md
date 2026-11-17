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

The Xcode and GitHub Actions builds prove target compilation and IPA packaging only. They
do **not** prove that SideStore preserves the App Group entitlement or that the signed
extension can read the app's value; that evidence must come from the owner's SideStore
test route on the physical iPhone.

## Fixture-only signed smoke

The Debug build recognizes `orbit://widget-smoke`. This route writes a synthetic fixture
marked `TEST ONLY` (one overdue row, four current-week rows, two of four completed) and
does not read authentication, school data, or any API. The screen offers **Очистити App
Group** after inspection. It is absent from Release builds.

After the `Orbit-Widget-AppGroup-Smoke-IPA` CI artifact is available:

1. Install that unsigned test IPA through the owner's permitted SideStore test route.
2. Open `orbit://widget-smoke` with the iOS Shortcuts **Open URLs** action.
3. Add `Справи школи` in `systemSmall` and `systemMedium`; confirm the `TEST ONLY` rows
   appear, including five medium rows and the `2/4` count. Check light/dark appearance,
   accessible text sizing, and that widget rows open Main Orbit's task screen/detail.
4. Tap **Очистити App Group**, remove the test IPA, and install/restore the intended Main
   Orbit build using the approved route.

Do not use real school data for this smoke. Record the exact SideStore version, iOS
version, iPhone model, whether the widget read the fixture, and the final small/medium
visual result. If install/signing fails or the widget cannot read the fixture, preserve
the exact SideStore error and resulting app/extension entitlement evidence.

## CI coverage and limits

The macOS workflow runs focused projection and route tests, builds the Main Orbit app plus
extension for iPhone 12 Simulator, builds/packages the Debug fixture smoke IPA, and builds
the unsigned Release IPA. Simulator/native build evidence is not physical-device or
SideStore-signing acceptance. No Mini target, backend, ACL, DB, merge, or publication is
part of this change.
