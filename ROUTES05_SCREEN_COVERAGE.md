# ROUTES 05 — Main Orbit screen coverage audit

Audit target: `release/main-orbit` at `f7d32e4` in `/tmp/ios105/repo`.
The publish repository/worktree was not changed or inferred from this checkout.

## Active shell

`VoiceAgentApp` → pairing or app lock → `AppView` → `NovaShellView`.
The single app-level dock exposes Today (`.home`), Orbit (`.orbit`), School
(`.school`) and Family (`.family`). School owns its own `NavigationStack` and
does not add a nested dock.

## Coverage matrix

| Runtime screen/workflow | Source | Data/authorization boundary | ROUTES 05 mapping | Status in this batch |
|---|---|---|---|---|
| Today | `OrbitTodayView` | calendar, School items/tasks; profile-scoped | 01 Today | ROUTES shell applied |
| Orbit conversation list | `OrbitChatsView` | authenticated Core Agent/chat API | 02 Chats | ROUTES shell applied |
| Orbit conversation | `OrbitConversationView` | streaming/polling, selection/copy/share, sources, confirmation | 03 Conversation | existing behavior retained |
| School home/command center | `SchoolHubView` / `SchoolCommandCenter` | Schulmanager read-only + Orbit-owned task actions | 04 School | ROUTES shell applied |
| Family home | `MainOrbit3FamilyView` | server-authoritative family profiles/messages | 05 Family | ROUTES shell applied |
| Family calendar | `OrbitCalendarView` | calendar integrations; editor and confirmation | 06 Calendar | existing Nova styling |
| Contacts | `OrbitContactsView` | profile-scoped contacts and identity links | 07 Contacts | existing Nova styling |
| Memory center | `MemoryCenterView` | provenance/temporal memory; correction permissions | 08 Memory | existing Nova styling |
| School inbox | `SchoolInboxView` | authorized, read-only School source | 09 Inbox | existing route |
| School letter/detail | `SchoolDetailView` / loader | German original, Ukrainian translation, AI interpretation, source refs | 10 Letter | existing route |
| School tasks | `SchoolTaskListView`, detail/checklist | Orbit-owned action capability; source task is not mutated | 11 Tasks | existing route |
| Timetable | `SchoolHubV2View` | verified School week coverage | 12 Timetable | existing route |
| Exams | `SchoolHubV2View` | verified School week coverage | 13 Exams | existing route |
| School Brain | `SchoolBrainView` | Core Agent with source refs | 14 School Brain | existing route |
| School calendar | `SchoolWeekCalendarView`, `SchoolCalendarView` | read-only source; calendar proposal/confirmation | 15 School Calendar | existing route |
| Unified School Search | `SchoolUnifiedSearchView` | authorized letters/events/tasks | 16 School Search | existing route |
| Main Voice | `MainVoiceHomeView`, `OrbitVoiceSheet`, `StartView` | explicit LiveKit lifecycle, mute/cleanup | 17 Voice | existing route |
| Family Messenger | `FamilyMessengerView` | server-authoritative family visibility | 18 Family Chat | existing route |
| Settings | `OrbitSettingsView` | device preferences, account/profile, App Lock | 19 Settings | existing route |
| Integrations/tools | `OrbitToolsView`, `CalendarSettingsView` | verified capability/integration state | 20 Integrations | existing route |
| Memory fact detail/correction | nested `MemoryCenterView` routes + editor | temporal provenance and permissions | 21 Memory Detail | existing route |
| Contact detail/editor/archive | nested contact routes | identity isolation and gated archive | 22 Contact Detail | existing route |
| Canonical action confirmation | chat and School calendar/task flows | resolver → proposal → confirmation → idempotent execution → server result | 23 Action Confirm | existing behavior retained |
| Owner admin/diagnostics | `OrbitDashboardView` and detail sheets | owner-only server health/cache actions | 24 Admin | existing route |
| School timeline | `SchoolTimelineView` | chronological source/action ordering | 25 Timeline | existing route |
| School briefing | `SchoolTasksView` | source-aware summary; no invented records | 26 Briefing | existing route |
| School notes/editor | `SchoolNotesView`, `SchoolNoteEditor` | Orbit-owned private notes | 27 Notes | existing route |
| School action history | `SchoolActionHistoryView` | authorized audit history | 28 History | existing route |
| Profile/access | settings/account sheets + profile switching | server identity and access | 29 Profile | existing route |
| Notifications/deep links | `SchoolNotificationCoordinator`, notification selection | active profile/source scope | 30 Notifications | conditional/deep-link route; no standalone view found |
| Memory imports | memory routes/API | verified import lifecycle and authorization | 31 Imports | existing route/API; no dedicated root view found |
| Unknown archetype | none | not a live app screen | 32 Archetype | reference only |
| Pairing/login | `PairingView`, `OrbitAuthentication` | activation code or authenticated login | system/auth extension | existing, not in 32 |
| App Lock | `OrbitAppLockView`, `OrbitAppLock` | Face ID/Touch ID/device passcode | system/security extension | existing, not in 32 |
| Account login sheet | `OrbitAccountLoginSheet` | authenticated account session | profile/access extension | existing, not in 32 |
| Audio options | `AudioOptionsSheet` | local voice/device preferences | voice/settings extension | existing, not in 32 |
| Calendar editor/settings | calendar sheets | resolver/proposal and calendar scope | calendar/action extension | existing, not in 32 |
| School task calendar sheet | `SchoolTaskCalendarSheet` | confirmed event result and capability | task/action extension | existing, not in 32 |
| School family-task editor | `SchoolFamilyTaskEditorView` | Orbit-owned action task API | task/action extension | existing, not in 32 |
| School unavailable/forbidden/stale/empty | `SchoolV2StateView`, store phases, notices | authorization/capability/source freshness | state variants | existing, not in 32 |
| Generic API error/loading/empty states | shared view branches and alerts | truthful source state | state variants | existing, not in 32 |
| DEBUG Interpreter Lab/diagnostics | `InterpreterLabView` | DEBUG-only fixture/capture diagnostics | system diagnostic variant | DEBUG-only, excluded from production route inventory |

## First-batch design changes

Added `Routes05DesignSystem.swift` with dynamic light/dark tokens and native
masthead, chapter, hero, ticket and rail primitives. The four root destinations
now use the wayfinding visual language while retaining their current stores and
navigation. The dock remains the only app-level navigation bar.

Native iOS screenshots, simulator builds and physical-device checks remain
unverified in this Linux environment: `[U]`.
