# Issue #119 — precise WidgetKit integration boundary

This directory contains **ready-to-integrate SwiftUI/WidgetKit source**, NOT an active Xcode
Widget Extension target. It is intentionally kept out of the signed Main Orbit IPA until
the SideStore/App Group feasibility and identity-isolation checks pass.

Current repo baseline at implementation start: release/main-orbit
6d9f7c023fd2f18fc920587c63c88b43fb24e19f.
Task: https://github.com/wink2003/orbit-voice-ios/issues/119

## Source layout
- VoiceAgent/App/SchoolTasksWidgetSnapshot.swift: dependency-free shared Codable row/snapshot model. Add
  this exact file to both the Main Orbit app and the widget extension targets.
- VoiceAgent/App/SchoolTasksWidgetProjection.swift: compiled in Main Orbit app only;
  the only place canonical SchoolHubLogic.taskSections is called.
- WidgetDev/SchoolTasksWidget.swift: WidgetKit small/medium read-only view + TimelineProvider.
- WidgetDev/SchoolTasksWidgetPublisher.swift: app-side App Group snapshot writer, fail closed.
- Tests/SchoolTasksWidgetProjectionTests.swift: synthetic pure group/rollover/JSON tests.

## Integration by Codex (separate implementation workstream, owner-approved DEV only)
1. Verify actual developer account/SideStore extension App ID + App Group entitlement behavior.
   An extension typically needs a distinct App ID; do not infer entitlement success from
   an unsigned CI build. Known 2026 SideStore widget/App Group issue #1437.
2. Add **dedicated WidgetKit extension target** to VoiceAgent.xcodeproj; compile
   SchoolTasksWidget.swift in widget target ONLY; add shared
   SchoolTasksWidgetSnapshot.swift to both targets; compile SchoolTasksWidgetProjection.swift
   in the app target only (it depends on SchoolHubLogic).
   SchoolTasksWidgetPublisher.swift belongs to the app target ONLY.
3. Register the actual tested App Group on BOTH the app and widget entitlements.
   The proposed group name is group.net.opik.orbit.voice, not verified as provisioned.
   Don't introduce insecure files, new auth tokens, provider access or entitlement bypass.
4. Connect Publisher.publish() after already authorized SchoolHubStore task refresh/status
   update only when identity is resolved and scopeKey matches; use exact effective-day
   grouping already performed in the projection. On logout, account/person/profile
   switch, expiry, permission revocation or scope mismatch call Publisher.clear().
   Widget must never display a previous person's snapshot. Snapshot validity <=12h,
   and crossing Monday boundary fails closed. Widget has no network/token/client.
5. Register an existing/canonical deep link or a verified orbit://school/tasks route;
   verify user authorization on every open. For "?task=<id>", navigate through
   real SchoolHubView -> Routes05SchoolTasksProductionView -> detail if still in
   authorized store; otherwise fall back to the task list. No widget status mutation.
   The widget URLs are interface placeholders until the app route is registered.
6. Verify app + widget extension actually share data under the SideStore-signed IPA
   on a physical iPhone before authorizing publication. Widget must remain fail-closed
   if App Group is unavailable. Keep Main/Mini bundle/icons unchanged.
7. Native Xcode build, iPhone 12 simulator medium widget screenshot both appearances,
   1 overdue + 4 current-week rows, overflow behavior when >5, Dynamic Type,
   UI contrast and accessibility, logout/profile change and stale/empty state.
   If five distinct rows physically do not fit legibly, report design blocker,
   don't silently replace with a large widget or omit them.

No backend/API/DB/ACL changes. No merge, signing or production publication in this
source-only draft. Signed full integration must pass a separate safety gate.
