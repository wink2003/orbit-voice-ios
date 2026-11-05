# Main Orbit Calendar v2 — UX acceptance contract

**Version:** 1.0
**Owner-approved structure:** 2026-11-05
**Scope:** Main Orbit Calendar UI behavior and layout; this contract records acceptance criteria and is not a pixel mockup.

## Accepted structure

1. Open on the current Monday-first week. Support month expand/collapse and month navigation.
2. Show an explicit selected non-today date section only when that selection applies.
3. For Today, preview the nearest upcoming eligible event.
4. Order upcoming sections as **This Week**, **Next Week**, then **Later**; an occurrence appears in at most one section.
5. Show up to five earliest distinct events in **Later**, within the previously agreed bounded local one-month query beyond Next Week. Report incomplete coverage truthfully.
6. Qualify event and recurrence identity by source.
7. A view opened from More has a working Back action; the root view has no redundant Back action.
8. Keep the existing ROUTES 05 visual language, light/dark appearance, and small-iPhone safe-area/NovaDock behavior.
9. The five planned named calendars and family/event-level access requirements in [Issue #21](https://github.com/wink2003/orbit-voice-ios/issues/21) remain separate work. This acceptance does not implement ACLs, invitees, or backend access changes.

## Evidence limits

The owner accepted this reconstructed structure on 2026-11-05. That acceptance does **not** verify pixel-level fidelity to the original Calendar v2 concept; that remains **NOT_VERIFIED**. The Oct 24 ROUTES 05 HTML is not the final Calendar v2 reference.

Simulator screenshots and CI establish **CODE_OR_CI_VERIFIED** behavior only for the named simulator, commit, and captured states. They do not establish `PHYSICAL_DEVICE_VERIFIED`, runtime VoiceOver/Dynamic Type acceptance, or production release. Physical iPhone review remains a separate acceptance step.
