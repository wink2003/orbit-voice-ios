"""Tests for scripts/classify_release_blockers.py (issue #57). Stdlib only, no network."""
import io, json, os, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import classify_release_blockers as C

NO_APPROVAL = {"requiresApprovingReviews": False, "requiredApprovingReviewCount": None}


class Review(unittest.TestCase):
    def test_rest_says_one_but_effective_false_null_and_no_rulesets_is_no_blocker(self):
        r = C.review_requirement(NO_APPROVAL, [], rest_required_count=1)
        self.assertEqual((r["result"], r["githubApprovalRequired"]), ("NO_BLOCKER", False))
        self.assertEqual(r["basis"], "EFFECTIVE_POLICY_DOES_NOT_REQUIRE_APPROVAL_REST_CONTRADICTS")
        self.assertTrue(any("diff/code review" in x for x in r["alsoRequired"]))     # review and Passkey are not waived
        self.assertTrue(any("Passkey" in x for x in r["alsoRequired"]))

    def test_effective_policy_requiring_approval_is_blocked(self):
        r = C.review_requirement({"requiresApprovingReviews": True, "requiredApprovingReviewCount": 1}, [])
        self.assertEqual((r["result"], r["requiredCount"]), ("BLOCKED", 1))

    def test_ruleset_requiring_approval_is_blocked_even_if_protection_says_false(self):
        r = C.review_requirement(NO_APPROVAL, [{"requiredApprovingReviewCount": 2}])
        self.assertEqual((r["result"], r["basis"]), ("BLOCKED", "RULESET_REQUIRES_APPROVAL"))

    def test_unreadable_inputs_are_uncertain_never_a_requirement(self):
        self.assertEqual(C.review_requirement(NO_APPROVAL, None, 1)["result"], "UNCERTAIN")
        self.assertEqual(C.review_requirement(None, [], 1)["result"], "UNCERTAIN")        # REST alone is not authoritative
        self.assertEqual(C.review_requirement({"requiresApprovingReviews": True, "requiredApprovingReviewCount": None}, [])["result"], "UNCERTAIN")

    def test_protected_true_alone_does_not_imply_approval(self):
        self.assertEqual(C.review_requirement({"protected": True}, [])["result"], "UNCERTAIN")


class Guard(unittest.TestCase):
    HEALTH = {"mode": "production-synthetic-only", "productionAccess": False}

    def test_idle_synthetic_only_with_baseline_ok_is_safe_idle_not_blocked(self):
        r = C.guard_state(self.HEALTH, True, "NOT_STARTED")
        self.assertEqual((r["result"], r["state"]), ("NO_BLOCKER", "SAFE_IDLE_NOT_REQUESTED"))
        self.assertEqual(C.guard_state(self.HEALTH, True, None)["result"], "NO_BLOCKER")

    def test_baseline_not_ok_blocks(self):
        self.assertEqual(C.guard_state(self.HEALTH, False, None)["state"], "BASELINE_NOT_OK")

    def test_authoritative_admission_failure_blocks_fail_closed(self):
        r = C.guard_state(self.HEALTH, True, "STARTED", {"reporter": "ceremony", "kind": "IOS_IPA", "gate": "ADMISSION"})
        self.assertEqual((r["result"], r["state"]), ("BLOCKED", "ADMISSION_FAILED"))

    def test_non_authoritative_failure_is_uncertain_not_a_guard_repair(self):
        r = C.guard_state(self.HEALTH, True, None, {"reporter": "observer", "gate": "ADMISSION"})
        self.assertEqual((r["result"], r["state"]), ("UNCERTAIN", "FAILURE_NOT_AUTHORITATIVE"))

    def test_health_missing_or_ceremony_running_is_uncertain(self):
        self.assertEqual(C.guard_state(None, True, None)["result"], "UNCERTAIN")
        self.assertEqual(C.guard_state(self.HEALTH, True, "STARTED")["state"], "CEREMONY_IN_PROGRESS")


class Observer(unittest.TestCase):
    def test_restricted_observer_permission_error_is_access_limited_not_publisher_blocked(self):
        r = C.observer_access("restricted-observer", "PermissionError: lstat legacy publisher")
        self.assertEqual((r["result"], r["state"]), ("UNCERTAIN", "OBSERVER_ACCESS_LIMITED"))

    def test_root_authoritative_ok_and_failure(self):
        self.assertEqual(C.observer_access("root-authoritative", None)["result"], "NO_BLOCKER")
        self.assertEqual(C.observer_access("authorized-executor", "PUBLISHER_UNTRUSTED")["result"], "BLOCKED")
        self.assertEqual(C.observer_access("root-authoritative", "PermissionError")["result"], "BLOCKED")   # fail closed in the real context

    def test_unknown_context_is_uncertain(self):
        self.assertEqual(C.observer_access(None, "PermissionError")["state"], "CONTEXT_UNKNOWN")


class Readiness(unittest.TestCase):
    def test_no_preparation_is_not_checked_not_ready_not_blocked(self):
        for args in ((None, None, None), ({"id": "i"}, None, None), ({"id": "i"}, {"m": 1}, "")):
            r = C.readiness(*args)
            self.assertEqual((r["result"], r["state"]), ("NOT_CHECKED", "PREPARATION_NOT_DONE"))

    def test_ready_and_not_ready_plan(self):
        self.assertEqual(C.readiness({"i": 1}, {"m": 1}, "READY")["state"], "PLAN_READY")
        self.assertEqual(C.readiness({"i": 1}, {"m": 1}, "BLOCKED")["result"], "BLOCKED")


class Cli(unittest.TestCase):
    def run_cli(self, check, facts):
        d = tempfile.mkdtemp(); self.addCleanup(__import__("shutil").rmtree, d, True)
        p = os.path.join(d, "f.json"); json.dump(facts, open(p, "w"))
        buf = io.StringIO(); code = C.main([check, "--input", p], out=buf)
        return code, json.loads(buf.getvalue())

    def test_exit_codes(self):
        self.assertEqual(self.run_cli("review", {"effective": NO_APPROVAL, "rulesets": [], "restRequiredCount": 1})[0], 0)
        self.assertEqual(self.run_cli("review", {"effective": {"requiresApprovingReviews": True, "requiredApprovingReviewCount": 1}, "rulesets": []})[0], 1)
        self.assertEqual(self.run_cli("readiness", {})[0], 2)

    def test_bad_input_is_uncertain(self):
        buf = io.StringIO()
        self.assertEqual(C.main(["review", "--input", "/nonexistent/f.json"], out=buf), 2)
        self.assertIn("INPUT_UNREADABLE", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
