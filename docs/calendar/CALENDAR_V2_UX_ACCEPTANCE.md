# Main Orbit Calendar v2 — UX acceptance contract

**Version:** 1.1
**Owner-approved structure:** 2026-11-05
**Owner amendment:** 2026-11-05 (CAL-119-01/02/03/05)
**Scope:** Main Orbit Calendar UI behavior and layout; this contract records acceptance criteria and is not a pixel mockup.

## Accepted structure

1. Open on the current Monday-first week. Support month expand/collapse and month navigation.
2. Show an explicit selected non-today date section only when that selection applies.
3. Show today's actual events once in one Today section. Do not render a separate Today preview/hero card. Apply a legible ROUTES 05 yellow treatment to the full Today section, including its heading, container and every event card. A manually selected non-today date remains a separate section.
4. **This Week** contains eligible occurrences strictly after local Today through the current Sunday, in chronological order. Exclude past weekdays and Today duplicates. Keep Monday-first week boundaries and the existing local timezone/date model. Order upcoming sections as **This Week**, **Next Week**, then **Later**; an occurrence appears in at most one section.
5. Show up to five earliest distinct events in **Later**, within the previously agreed bounded local one-month query beyond Next Week. Report incomplete coverage truthfully.
6. Qualify event and recurrence identity by source.
7. A view opened from More has a working Back action; the root view has no redundant Back action.
8. Keep the existing ROUTES 05 visual language, light/dark appearance, and small-iPhone safe-area/NovaDock behavior.
9. The five planned named calendars and family/event-level access requirements in [Issue #21](https://github.com/wink2003/orbit-voice-ios/issues/21) remain separate work. This acceptance does not implement ACLs, invitees, or backend access changes.
10. Event cards use a clear title, date/time and source hierarchy. Secondary metadata remains truthful and readable without repeating decorative information; navigation and NovaDock reachability remain available.
11. The collapsed week card uses a compact readable date range and tighter spacing, reducing its vertical footprint by approximately half where feasible without a fixed brittle height or clipped content. Keep all seven weekdays, event dots, week arrows, Today/selected-day indicators, and the month expand control. Keep interactive targets at least 44pt. On a normal-size iPhone 12 viewport with a Today event, the first real event card should begin above the vertical midpoint where feasible. Expanded-month layout, Dynamic Type, VoiceOver, light/dark and safe areas remain supported.

**Superseded criterion:** the original v1.0 item 3, “For Today, preview the nearest upcoming eligible event,” is explicitly replaced by item 3 above. The separate yellow Today preview/hero is removed; actual Today events are rendered once in their normal section.

## Evidence limits

The owner accepted this reconstructed structure on 2026-11-05. That acceptance does **not** verify pixel-level fidelity to the original Calendar v2 concept; that remains **NOT_VERIFIED**. The Oct 24 ROUTES 05 HTML is not the final Calendar v2 reference.

Simulator screenshots and CI establish **CODE_OR_CI_VERIFIED** behavior only for the named simulator, commit, and captured states. They do not establish `PHYSICAL_DEVICE_VERIFIED`, runtime VoiceOver/Dynamic Type acceptance, or production release. Physical iPhone review remains a separate acceptance step.
