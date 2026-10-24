# AGENTS.md — Orbit iOS Codex session policy

**REPO:** `wink2003/orbit-voice-ios` (Main Orbit and Orbit Mini). These instructions apply to **new Codex sessions using a checkout containing this file**.

## Required first action — ROADMAP_READ

1. Retrieve the current [ORBIT MASTER ROADMAP](https://github.com/wink2003/orbit-family-ai/blob/main/docs/ORBIT_MASTER_ROADMAP.md) from the **canonical** `wink2003/orbit-family-ai` GitHub repository. Read its linked issue for the relevant workstream; do not treat a cached excerpt or chat history as the latest version.
2. Verify actual repository, branch, HEAD and local state; distinguish this iOS repo from production `/opt/projects/family-ai`, Codex development trees, and separate release operator/tooling repos.
3. Before implementation, write a **short preflight statement** such as `ROADMAP_READ: GitHub main @ <commit/time>; stream: Main iOS / Mini; source HEAD: <sha>; evidence: <type>; blockers: <none/list>`. This is **a report, not permission** to perform anything. If GitHub cannot be fetched, use `ROADMAP_STALE`, say exactly what could not be verified, and verify necessary facts by authoritative sources. Do not invent current statuses.
4. Preserve proven behavior. Choose minimal diff, targeted tests/CI/build, and device acceptance only with actual user/device evidence. Record roadmap updates **after** completed, independently verified milestones (never auto-claim release success).

## App-specific boundaries

**Main Orbit:** bundle `net.opik.orbit.voice`; family AI control center. Preserve current device-accepted baseline and navigation/UX unless user specifically requests changes. Prioritize copy/select text, readable hierarchy, fast flows, iOS-appropriate interaction, light/dark themes and existing app icons.

**Orbit Mini:** bundle `net.opik.orbit.mini`; **minimal voice client**. Preserve established `Siri/AppIntent → foregroundActive → Session.start() → mic/first PCM → LiveKit → realtime agent → background continuation`, Live Activity cleanup, and user command to end session. Return to previous app/home uses **external iOS Shortcuts and Personal Automation**. Do not reintroduce blocking Wait for Ready, standalone ADM probes, internal app-return state machines or app-driven scene destruction. Never turn Mini into another Main Orbit.

**SideStore:** both apps are separate entries in `Orbit Family`. Updates must preserve the respective exact bundle ID. **Do not publish IPA directly**, edit production feed or bypass Guard/Passkey; iOS publishing uses canonical, target-scoped release tooling, authorized operations, recovery and actual human Passkey when required. Historical v108 direct publication is **not** a precedent for bypass.

## Trust and reporting

- A0 normal source/UI/tests/build/read-only diagnostics. A1 family/action/identity/isolation, real memory and additive API/DB changes with appropriate gates. A2 destructive production/DB, secrets, auth/Guard/security/sudo/firewall/billing, mass deletion/backup removal **only by explicit scoped authorization and canonical safeguards**.
- No speculative success, no fake approvals, no private data/secrets in logs or docs.
- Final report: exact repo/commit, code/tests/CI verified, production runtime verified, **physical iPhone verified separately**, uncertainties, changes and one next action.
- Roadmap updates must be minimal, dated, evidence-linked, and performed through an authorized writable checkout of the **documentation repo**, not by editing unrelated production trees.

Other ChatGPT/Codex conversations are **not automatically synced** with GitHub. Fetch the source at each new session.
