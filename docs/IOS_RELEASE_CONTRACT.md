# Canonical Main Orbit iOS release contract

**Scope:** documentation and Codex orchestration guidance. **No change to production, Guard/Passkey, CI policy, signing, SideStore publisher or release branch.** This contract is subordinate to the **actual installed** `release-intent-policy.json`, canonical `IOS_IPA` validator, production journal, and Guard policy. Reconfirm the trusted branch/workflow/artifact/target before each release.

## Three separate evidence dimensions

| Dimension | When | Authority | Release gate? |
| --- | --- | --- | --- |
| Source/build/CI acceptance | **Before** publication | GitHub eligible release-branch commit, successful canonical CI, exact IPA digest/bundle/version, root-owned intent, recovery and staged-feed checks | **Yes** |
| Release action authorization | **Before** publication | Exact operation and manifest → canonical Guard request → real human **Passkey on iPhone** → valid authorization evidence | **Yes** |
| Physical **application** acceptance | **After** publication and installation | User tests the new installed build on a real iPhone (UX/voice/routes/behavior) | **Postpublication acceptance; not a prerequisite to SideStore publication** |

All three matter, but no circular requirement is valid. An unpublished IPA cannot require an already-installed published app as a publication gate in the proven process. Postpublication failure means **a failed product acceptance requiring triage**, not permission to falsify release receipts.

`checkpointRequired: true` requires prepublication checkpoint/backup/restore/rollback evidence, not physical-app acceptance. `IOS_PUBLICATION` labels the existing approval kind. `SUPPORTED_OFFLINE_ONLY` describes the Unified Releases operator's offline adapter/limits, not an independent effective Guard denial; canonical production tools retain authority.

## Expected canonical sequence

1. Implement and test on a **development** branch, separate from the protected release branch.
2. Review the candidate and current **protected `release/main-orbit`** history. Promote explicitly with reviewed merge/cherry-pick/rebase as appropriate; **never overwrite or discard release-only commits**. Do not infer an ineligible development CI run authorizes publication.
3. Trigger/verify **fresh eligible-branch CI** on the exact promoted commit. Check trusted repository, branch, workflow **`Build Orbit Voice IPA`**, artifact **`Orbit-Voice-IPA`**, source SHA, IPA SHA256, unsigned/resign contract, bundle **`net.opik.orbit.voice`** and increasing build.
4. Create **root-owned canonical release intent** using permitted authorizer and allowed target `sidestore-main`; prepare by existing canonical tools.
5. Obtain exact candidate and prior-artifact **backup, readback, isolated restore, rollback, staged SideStore feed** and checkpoint evidence. Protect the correct publication resource and journal.
6. Initiate exact **Guard request**. Operator confirms the consequential publication with **Passkey** on iPhone. Verify authorization scope/expiry/replay and locked resources; human approval is never simulated.
7. Use the existing canonical **`IOS_IPA` executor and publisher**. No direct publisher, signer, exception, or feed mutation outside established route.
8. Verify public feed, download URL, SHA256/build/bundle, old artifact retained, journal terminal state and rollback evidence.
9. **Only now:** install/update on physical iPhone and test actual app behavior (ROUTES 05, Inbox/School, chat, copy/select, navigation, light/dark). Record build-specific **PHYSICAL_DEVICE_VERIFIED** or detailed defect; do not backdate acceptance.

This order is **Main Orbit** specific. For Mini or backend/worker, inspect the actual target-specific policy and test requirements. No historical device fact or old Guard receipt is transferrable to a new candidate.

## Distinguish reasons a release has not started

| Diagnostic (informational) | Observation | Correct recovery |
| --- | --- | --- |
| `BRANCH_NOT_ELIGIBLE` | Candidate from development branch, not accepted by *actual* allowlist | Inspect protected branch, reviewed promotion, new eligible CI. **Not a Guard refusal.** |
| `CI_NOT_READY` | Eligible-branch CI or artifact absent/mismatched | Build/verify exact source and artifact |
| `INTENT_NOT_CREATED` | No canonical root-owned intent | Prepare valid intent; **Guard has not rejected anything** |
| `PREPARATION_INCOMPLETE` | Recovery, feed, rollback, checkpoint or admission evidence missing | Finish canonical evidence and validation |
| `GUARD_APPROVAL_REQUIRED` | Valid prepared operation not yet approved / Passkey pending | Initiate or await actual ceremony; never fake it |
| `PUBLICATION_BLOCKED` | Authoritative Guard rejection, publisher refusal or actual execution blocker | Show exact refusal; do not bypass |
| `POST_PUBLICATION_DEVICE_ACCEPTANCE_PENDING` | SideStore publication verified; actual installed build not checked | Complete user device testing **after** publication |
| `*_NOT_VERIFIED` | Source/current state is not available | Read authoritative status; do not label generic `POLICY_BLOCKED` |

These are **diagnostic concepts**, not newly authorized API error codes. Don't promote speculative classifications to a real Guard decision.

## Evidence baseline / independent checks, dated 2026-10-25

- GitHub Actions [CI 110](https://github.com/wink2003/orbit-voice-ios/actions/runs/40141644484): `success`, source `2a746c55f15bdda9f8dbc09a73bdd2850cf68d03`, branch `release/main-orbit`.
- GitHub Actions [CI 111](https://github.com/wink2003/orbit-voice-ios/actions/runs/40174599359): `success`, source `018cc09189529c1e272894b0adea6439ba462409`, branch `release/main-orbit`.
- GitHub Actions [CI 112 development](https://github.com/wink2003/orbit-voice-ios/actions/runs/40191553331): `success`, source `4705ed1357dd6a82e352debf823e1ab213a777a2`, branch `codex/routes05-batch2-school-chat`; successful dev CI did **not** establish eligibility for `release/main-orbit`.
- Forensic operator report: releases **110**/**111** completed canonical Guard/Passkey/SideStore flow without separate prepublication physical app acceptance. **Passkey timestamps/receipts reported, not independently read here**; CI metadata independently checked.
- Read-only production feed observed at **2026-10-25 13:51 UTC**: Main **111**, Mini **29**; **the separate active 112 release is not touched by this document**. The state can change after this observation.


## Missed or expired Guard Passkey — canonical recovery

A missed Passkey window is **not an authorization denial** and is not a reason to change Guard policy, sign the IPA another way, rebuild automatically, or create a preview exception.

**Always first read the authoritative status for the existing operation** using the canonical `pipeline-status` / `ceremony-status` read-only commands, then confirm journal/locks, running process, prior publication kind-state, Guard/Broker restoration and exact request expiry through legitimate operator access.

- **`IN_PROGRESS` / `WAITING_FOR_PASSKEY`**: reconnect to the existing ceremony with bounded `ceremony-status --wait`. Never send a duplicate Guard request.
- **`COMPLETE` / publication `SUCCEEDED`**: verify existing publication and physical installation. Never republish.
- **`UNCERTAIN`, `EXECUTING`, `VERIFYING`, missing terminal proof or unverified restoration**: stop; use canonical read-only investigation and authorized reconciliation/recovery. **No blind retry.**
- **`EXPIRED` / `DECLINED`**: a **fresh attempt** may be appropriate *only after* the authoritative journal proves publication **did not happen**, Guard/Broker restoration is `VERIFIED`, no runner is active, no uncertainty exists, and original candidate/intent/preparation are still valid. New Guard request/nonce/TTL and a new human Passkey are required. **Never** reuse or extend the expired approval.
- **`FAILED_KNOWN`**: review the terminal failure; correct it and use an appropriately authorized new operation identity.

**Current pipeline gap (verified 2026-10-25):** installed `orbit_release_pipeline.start()` returns `alreadyStarted` when the pipeline record is `STARTED`, even when its ceremony has ended `EXPIRED`. Calling `pipeline-start` again **does not by itself prove a new Passkey request was sent**. The ceremony engine can create a new attempt after terminal expiry with verified restoration, but the pipeline needs a deliberate, reviewed retry transition. See [canonical retry issue #6](https://github.com/wink2003/orbit-family-ai/issues/6). Do not bypass the pipeline using an ad-hoc direct `ceremony-start` or publisher command.

The informational [operator diagnostics patch](https://github.com/wink2003/orbit-family-ai/blob/main/docs/patches/UR-IOS-RELEASE-CONTRACT-CLARITY-20261025.patch) covers classification with synthetic tests; it is not yet a deployed fix for the canonical retry state machine.

## Guardrails for Codex

A ready dev branch plus successful CI → **promote to eligible branch, rebuild and create intent**. Do not propose security-policy exceptions to evade normal branch eligibility. A missing Passkey request is **not** a Guard rejection. Do not claim that `physical-iPhone-acceptance` is a prepublication blocker; explicitly distinguish hardware Passkey from postpublication app testing.

Never mutate Guard admission, sudoers, code signing, SideStore feed or other A2 policy under this documentation task. Do not duplicate an in-flight release operation. Verify candidate state by authoritative journal before retrying. Report code/CI, production publishing, and physical device as three separate evidence categories.

**Cross-reference:** [ORBIT MASTER ROADMAP](https://github.com/wink2003/orbit-family-ai/blob/main/docs/ORBIT_MASTER_ROADMAP.md), [GitHub roadmap #1](https://github.com/wink2003/orbit-family-ai/issues/1). Operator implementation patch is staged for review separately; documentation does not silently install that patch.
