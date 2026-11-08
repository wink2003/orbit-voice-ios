#!/usr/bin/env python3
"""Advisory classifier that prevents FALSE "BLOCKED" decisions in Main Orbit iOS releases (issue #57).

It only turns already-collected read-only facts into a decision label.  It never calls GitHub, Guard, the host or the
release tooling, never publishes, approves or changes anything, and it is NOT an authority: the canonical `ipa-plan`,
the installed ceremony and the owner's real Passkey remain the only gates.  Unknown inputs yield UNCERTAIN (fail closed),
never a fabricated requirement and never READY.

Distinct facts that must not be conflated:
  code/diff review  !=  GitHub approving review  !=  scoped owner authorization  !=  Guard/Passkey approval.

Usage:  classify_release_blockers.py review|guard|observer|readiness --input facts.json
Exit codes:  0 NO_BLOCKER / informational   1 BLOCKED (an actual enforced condition)   2 UNCERTAIN / NOT_CHECKED
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Mapping, Sequence

EXIT_OK, EXIT_BLOCKED, EXIT_UNCERTAIN = 0, 1, 2
ALWAYS = ("diff/code review is still required", "scoped owner authorization is still required",
          "Guard/Passkey approval is still required for any consequential publication")


def _count(value: Any) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else None


def review_requirement(effective: Mapping[str, Any] | None, rulesets: Sequence[Mapping[str, Any]] | None,
                       rest_required_count: Any = None) -> dict[str, Any]:
    """Is a GitHub *approving review* required to merge into the release branch?

    `effective` is the GraphQL branch-protection rule that actually applies (requiresApprovingReviews / requiredApprovingReviewCount).
    `rulesets` is the list of repository rulesets targeting the branch (None = could not be read).
    `rest_required_count` is the legacy REST `required_pull_request_reviews` value: informational only, it may be stale or inapplicable.
    """
    out: dict[str, Any] = {"check": "github_approving_review", "alsoRequired": list(ALWAYS)}
    if rulesets is None or not isinstance(rulesets, (list, tuple)):
        return dict(out, result="UNCERTAIN", githubApprovalRequired=None, basis="RULESETS_UNREADABLE",
                    action="read the rulesets for the branch; do not infer an approval requirement from REST or protected=true")
    for rs in rulesets:
        n = _count((rs or {}).get("requiredApprovingReviewCount"))
        if n:
            return dict(out, result="BLOCKED", githubApprovalRequired=True, basis="RULESET_REQUIRES_APPROVAL", requiredCount=n)
    if not isinstance(effective, Mapping) or "requiresApprovingReviews" not in effective:
        return dict(out, result="UNCERTAIN", githubApprovalRequired=None, basis="EFFECTIVE_POLICY_UNAVAILABLE",
                    action="read the effective GraphQL branch protection; a single REST endpoint is not authoritative")
    flag, count = effective.get("requiresApprovingReviews"), _count(effective.get("requiredApprovingReviewCount"))
    if flag is True and count:
        return dict(out, result="BLOCKED", githubApprovalRequired=True, basis="EFFECTIVE_POLICY_REQUIRES_APPROVAL", requiredCount=count)
    if flag is True:
        return dict(out, result="UNCERTAIN", githubApprovalRequired=None, basis="EFFECTIVE_POLICY_COUNT_UNKNOWN",
                    action="requiresApprovingReviews is true but the count is not a positive integer; reconcile before declaring BLOCKED")
    if flag is False:
        contradicted = _count(rest_required_count) not in (None, 0)
        return dict(out, result="NO_BLOCKER", githubApprovalRequired=False,
                    basis="EFFECTIVE_POLICY_DOES_NOT_REQUIRE_APPROVAL_REST_CONTRADICTS" if contradicted else "EFFECTIVE_POLICY_DOES_NOT_REQUIRE_APPROVAL",
                    restRequiredCount=rest_required_count if contradicted else None)
    return dict(out, result="UNCERTAIN", githubApprovalRequired=None, basis="EFFECTIVE_POLICY_AMBIGUOUS")


def guard_state(health: Mapping[str, Any] | None, baseline_ok: Any, ceremony: str | None,
                admission_failure: Mapping[str, Any] | None = None) -> dict[str, Any]:
    """Classify the Guard state.  Idle `production-synthetic-only` / `productionAccess=false` is the REQUIRED safe baseline.

    `ceremony`: None/"NOT_STARTED" before the scoped ceremony; "STARTED" once started.
    `admission_failure`: kind-specific failure reported by the AUTHORIZED executor (not an observer), else None.
    """
    out: dict[str, Any] = {"check": "guard_state"}
    if admission_failure:
        if admission_failure.get("reporter") in ("authorized-executor", "ceremony") and admission_failure.get("kind") and admission_failure.get("gate"):
            return dict(out, result="BLOCKED", state="ADMISSION_FAILED", gate=admission_failure["gate"], kind=admission_failure["kind"])
        return dict(out, result="UNCERTAIN", state="FAILURE_NOT_AUTHORITATIVE",
                    action="a failure needs an authoritative reporter, kind and gate; otherwise report UNCERTAIN, not a Guard repair")
    if not isinstance(health, Mapping):
        return dict(out, result="UNCERTAIN", state="HEALTH_UNAVAILABLE")
    idle = health.get("mode") == "production-synthetic-only" and health.get("productionAccess") is False
    if idle and baseline_ok is True and ceremony in (None, "NOT_STARTED"):
        return dict(out, result="NO_BLOCKER", state="SAFE_IDLE_NOT_REQUESTED",
                    note="idle synthetic-only is the required baseline; the ceremony enables exact-scope admission and restores it. No Guard repair is indicated")
    if idle and baseline_ok is False:
        return dict(out, result="BLOCKED", state="BASELINE_NOT_OK", action="baseline_ok is false in the installed ceremony check: STOP")
    if ceremony == "STARTED":
        return dict(out, result="UNCERTAIN", state="CEREMONY_IN_PROGRESS", action="read ceremony-status; never start a second ceremony")
    return dict(out, result="UNCERTAIN", state="NOT_CLASSIFIED")


def observer_access(context: str | None, error: str | None) -> dict[str, Any]:
    """A PermissionError seen by a restricted observer is an access limit, not a failed publisher."""
    out: dict[str, Any] = {"check": "observer_access", "context": context, "error": error}
    if context not in ("root-authoritative", "restricted-observer", "authorized-executor"):
        return dict(out, result="UNCERTAIN", state="CONTEXT_UNKNOWN")
    if not error:
        return dict(out, result="NO_BLOCKER", state="OK")
    if context == "restricted-observer" and "PermissionError" in error:
        return dict(out, result="UNCERTAIN", state="OBSERVER_ACCESS_LIMITED",
                    action="repeat the read through the supported root-authoritative path; do not change permissions and do not call it PUBLISHER_BLOCKED")
    return dict(out, result="BLOCKED", state="GATE_FAILED_IN_AUTHORITATIVE_CONTEXT")


def readiness(intent: Any, manifest: Any, ipa_plan: str | None) -> dict[str, Any]:
    """Missing preparation is NOT_CHECKED: neither READY nor BLOCKED."""
    out: dict[str, Any] = {"check": "publication_readiness"}
    if not intent or not manifest or ipa_plan in (None, ""):
        return dict(out, result="NOT_CHECKED", state="PREPARATION_NOT_DONE", action="prepare intent/manifest and read the canonical ipa-plan; do not infer READY or BLOCKED")
    if ipa_plan == "READY":
        return dict(out, result="NO_BLOCKER", state="PLAN_READY", note="a READY plan is not authorization; the Passkey is still required")
    return dict(out, result="BLOCKED", state="PLAN_NOT_READY", plan=ipa_plan)


def exit_code(result: Mapping[str, Any]) -> int:
    return {"NO_BLOCKER": EXIT_OK, "BLOCKED": EXIT_BLOCKED}.get(str(result.get("result")), EXIT_UNCERTAIN)


def main(argv: Sequence[str] | None = None, out=None) -> int:
    out = out or sys.stdout
    ap = argparse.ArgumentParser(prog="classify_release_blockers")
    ap.add_argument("check", choices=("review", "guard", "observer", "readiness"))
    ap.add_argument("--input", required=True, help="JSON file with the already-collected facts")
    a = ap.parse_args(argv)
    try:
        with open(a.input, encoding="utf-8") as fh: f = json.load(fh)
        if not isinstance(f, dict): raise ValueError("facts must be a JSON object")
        if a.check == "review": res = review_requirement(f.get("effective"), f.get("rulesets"), f.get("restRequiredCount"))
        elif a.check == "guard": res = guard_state(f.get("health"), f.get("baselineOk"), f.get("ceremony"), f.get("admissionFailure"))
        elif a.check == "observer": res = observer_access(f.get("context"), f.get("error"))
        else: res = readiness(f.get("intent"), f.get("manifest"), f.get("ipaPlan"))
    except (OSError, ValueError) as exc:
        out.write(json.dumps({"result": "UNCERTAIN", "code": "INPUT_UNREADABLE:" + type(exc).__name__}) + "\n")
        return EXIT_UNCERTAIN
    out.write(json.dumps(res, sort_keys=True) + "\n")
    return exit_code(res)


if __name__ == "__main__":
    raise SystemExit(main())
