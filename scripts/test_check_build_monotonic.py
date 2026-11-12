"""Tests for scripts/check_build_monotonic.py (issue #28). Stdlib only; local HTTP server, no external network."""
import io, json, os, subprocess, sys, tempfile, threading, unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import check_build_monotonic as C

PROJECT = os.path.join(REPO, "apps/orbit-voice-ios/VoiceAgent.xcodeproj/project.pbxproj")
BUNDLE = "net.opik.orbit.voice"


def feed(builds, bundle=BUNDLE, extra_apps=()):
    return {"apps": [{"bundleIdentifier": bundle, "versions": [{"version": "1.1", "buildVersion": str(b)} for b in builds]}, *extra_apps]}


def pbx(*values):
    return "\n".join(f"\t\t\t\tCURRENT_PROJECT_VERSION = {v};" for v in values) + "\n"


class Base(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(); self.addCleanup(__import__("shutil").rmtree, self.d, True)

    def write(self, name, text):
        p = os.path.join(self.d, name); open(p, "w").write(text); return p

    def run_main(self, project_text, feed_obj=None, **kw):
        proj = self.write("project.pbxproj", project_text); argv = ["--project", proj]
        if feed_obj is not None: argv += ["--feed-file", self.write("feed.json", json.dumps(feed_obj))]
        out = io.StringIO(); rc = C.main(argv + kw.pop("extra", []), out=out, **kw)
        return rc, json.loads(out.getvalue())


class Decision(Base):
    def test_newer_candidate_passes(self):
        rc, o = self.run_main(pbx(124, 124), feed([123, 122])); self.assertEqual((rc, o["result"], o["candidateBuild"], o["liveBuild"]), (0, "PASS", 124, 123))

    def test_equal_candidate_fails_with_an_actionable_message(self):
        rc, o = self.run_main(pbx(123, 123), feed([123, 122]))
        self.assertEqual((rc, o["result"], o["code"]), (1, "FAIL", "BUILD_NOT_NEWER_THAN_LIVE")); self.assertIn("bump CURRENT_PROJECT_VERSION", o["action"]); self.assertIn("> 123", o["action"])

    def test_older_candidate_fails(self):
        rc, o = self.run_main(pbx(121, 121), feed([123, 122])); self.assertEqual((rc, o["code"]), (1, "BUILD_NOT_NEWER_THAN_LIVE"))

    def test_only_the_main_bundle_counts(self):
        mini = {"bundleIdentifier": "net.opik.orbit.mini", "versions": [{"buildVersion": "999"}]}
        rc, o = self.run_main(pbx(124, 124), feed([123], extra_apps=[mini])); self.assertEqual((rc, o["liveBuild"]), (0, 123))


class FailClosed(Base):
    def unknown(self, project_text, feed_obj, code):
        rc, o = self.run_main(project_text, feed_obj); self.assertEqual((rc, o["result"]), (2, "UNKNOWN")); self.assertTrue(o["code"].startswith(code), o)

    def test_candidate_problems(self):
        self.unknown("no version here\n", feed([1]), "CANDIDATE_BUILD_NOT_FOUND")
        self.unknown(pbx(124, 125), feed([1]), "CANDIDATE_BUILD_AMBIGUOUS")
        self.unknown(pbx("$(BUILD)", "$(BUILD)"), feed([1]), "CANDIDATE_BUILD_NOT_NUMERIC")

    def test_feed_problems(self):
        self.unknown(pbx(124), {"apps": []}, "FEED_BUNDLE_NOT_FOUND_OR_DUPLICATED")
        self.unknown(pbx(124), {"nope": 1}, "FEED_SHAPE_INVALID")
        self.unknown(pbx(124), feed([]), "FEED_VERSIONS_MISSING")
        self.unknown(pbx(124), feed([123, "abc"]), "FEED_BUILD_NOT_NUMERIC")
        self.unknown(pbx(124), feed([121, 123]), "FEED_NOT_NEWEST_FIRST")        # an inconsistent feed is never trusted
        dup = {"bundleIdentifier": BUNDLE, "versions": [{"buildVersion": "1"}]}
        self.unknown(pbx(124), feed([123], extra_apps=[dup]), "FEED_BUNDLE_NOT_FOUND_OR_DUPLICATED")

    def test_unreadable_inputs_fail_closed(self):
        out = io.StringIO(); self.assertEqual(C.main(["--project", "/nonexistent/project.pbxproj", "--feed-file", "/nonexistent/f.json"], out=out), 2)
        self.assertEqual(json.loads(out.getvalue())["result"], "UNKNOWN")

    def test_non_https_feed_is_refused(self):
        with self.assertRaisesRegex(C.Unverifiable, "FEED_URL_NOT_HTTPS"): C.fetch_feed("http://voice.orbit.opik.net/altstore/orbit.json")


class Handler(BaseHTTPRequestHandler):
    status, body = 200, b"{}"
    def do_GET(self):
        self.send_response(Handler.status); self.end_headers(); self.wfile.write(Handler.body)
    def log_message(self, *a): pass


class Network(Base):
    """fetch_feed against a local server through an injected opener (the production URL must be https)."""
    def serve(self, status, body):
        Handler.status, Handler.body = status, body
        srv = HTTPServer(("127.0.0.1", 0), Handler); self.addCleanup(srv.server_close)
        t = threading.Thread(target=srv.serve_forever, daemon=True); t.start(); self.addCleanup(srv.shutdown)
        return f"http://127.0.0.1:{srv.server_address[1]}/orbit.json"

    def opener(self, req, timeout=None):                       # allow plain http only here, to reach the local server
        import urllib.request
        return urllib.request.urlopen(req, timeout=timeout)

    def fetch_local(self, url):
        class Shim(C.urllib.request.Request): pass
        return C.fetch_feed(url.replace("http://", "https://"), opener=lambda req, timeout=None: self.opener(C.urllib.request.Request(url), timeout=timeout))

    def test_ok_feed_is_parsed(self):
        url = self.serve(200, json.dumps(feed([124, 123])).encode()); self.assertEqual(C.live_build(self.fetch_local(url), BUNDLE), 124)

    def test_http_500_malformed_and_oversize_fail_closed(self):
        for status, body, code in ((500, b"x", "FEED_HTTP_500"), (200, b"not json", "FEED_NOT_JSON"), (200, b"x" * (C.MAX_FEED_BYTES + 5), "FEED_TOO_LARGE")):
            with self.subTest(code=code), self.assertRaisesRegex(C.Unverifiable, code): self.fetch_local(self.serve(status, body))

    def test_connection_refused_is_unavailable(self):
        srv = HTTPServer(("127.0.0.1", 0), Handler); port = srv.server_address[1]; srv.server_close()
        with self.assertRaisesRegex(C.Unverifiable, "FEED_UNAVAILABLE"): self.fetch_local(f"http://127.0.0.1:{port}/orbit.json")


class RealProject(unittest.TestCase):
    """The real project file parses; build 124 is newer than a feed at 123 and not newer than a feed already at 124."""
    def run_cli(self, builds):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh: json.dump(feed(builds), fh)
        self.addCleanup(os.unlink, fh.name)
        return subprocess.run([sys.executable, "-I", os.path.join(HERE, "check_build_monotonic.py"), "--project", PROJECT, "--feed-file", fh.name], stdout=subprocess.PIPE, text=True)

    def test_real_project_against_synthetic_feeds(self):
        cand = C.candidate_build(open(PROJECT).read())
        r = self.run_cli([cand - 1]); self.assertEqual((r.returncode, json.loads(r.stdout)["result"]), (0, "PASS"))
        r = self.run_cli([cand]); self.assertEqual((r.returncode, json.loads(r.stdout)["result"]), (1, "FAIL"))
        r = self.run_cli([cand + 1]); self.assertEqual(r.returncode, 1)

    def test_workflow_derives_the_build_number_before_the_macos_build(self):
        """Owner decision 2026-11-12: the release build number is DERIVED in CI (published+1); no bump PR, no separate gate job."""
        try: import yaml
        except ImportError: self.skipTest("PyYAML not available")
        wf = yaml.safe_load(open(os.path.join(REPO, ".github/workflows/build-orbit-voice-ios.yml")))
        jobs = wf["jobs"]; self.assertNotIn("build-number-gate", jobs); self.assertIn("build-number-tests", jobs)
        build = jobs["build"]; self.assertNotIn("needs", build)
        names = [st.get("name") for st in build["steps"]]
        derive_i = names.index("Derive build number (release branch only)"); xcode_i = names.index("Build unsigned iOS application")
        verify_i = names.index("Verify the built app carries the derived build number"); pack_i = names.index("Package IPA for AltStore")
        self.assertTrue(derive_i < xcode_i < verify_i < pack_i)
        derive = build["steps"][derive_i]
        self.assertIn("release/main-orbit", derive["if"]); self.assertTrue("derive_build_number.py" in derive["run"])
        self.assertIn("CPV_OVERRIDE", build["steps"][xcode_i]["env"]); self.assertIn("$CPV_OVERRIDE", build["steps"][xcode_i]["run"])
        self.assertIn("CFBundleVersion", build["steps"][verify_i]["run"])

if __name__ == "__main__":
    unittest.main()
