# AGENTS.md — orbit-voice-ios (Orbit Voice / Main Orbit / Mini iOS apps)

Thin entrypoint for Codex and other agents. The shared policy, release routes and runbooks live in `wink2003/orbit-family-ai`:

- Policy: `docs/ORBIT_AGENT_POLICY.md` and the operations map `docs/ORBIT_AGENT_OPERATIONS_MAP.md` (branch `main`).
- Release tooling, golden path and the **Main IPA quickstart** (`docs/runbooks/MAIN_IPA_RELEASE_QUICKSTART.md`) are on branch **`feat/mini-ipa-route`** of that repository. Do not call `orbit-release ipa-plan` / `ipa-plan --target`; the Main IPA route is `orbit_release_flow.py ios-intent` → `pipeline-start`.

## Rules for this repository
- **Merges need an exact owner approval** naming the PR number and head SHA (`merge #N on <SHA>`). General consent ("full release", "publish", "yes after the checks") is not an approval. If the interactive question is not displayed, ask in plain text: "Reply exactly: `merge #N on <SHA>`".
- To keep confirmations to a minimum ask **one combined question** that states the exact PR+SHA **and** "start the release" (generate it with `scripts/release/approval_question.py` from `wink2003/orbit-family-ai`, branch `feat/mini-ipa-route`; guide: `docs/runbooks/MERGE_AND_RELEASE_APPROVAL.md`). One "Yes" is the exact merge approval and the go for the A1 chain; every Passkey ceremony and the device acceptance stay separate steps.
- `release/main-orbit` is linear (squash merges). Its **push CI builds the IPA artifact** (PR CI builds unsigned and skips packaging); the build number is derived from the published SideStore build (+1). Do not bump `project.pbxproj` for release.
- Batch your pushes: each push starts a full macOS build (≈ 8 min). Builds on feature branches are cancelled when a newer push arrives; builds on `release/main-orbit` are never cancelled.
- Never commit private photos, signing material or secrets.
