import io, json, os, tempfile, unittest
import derive_build_number as d

PBX = "CURRENT_PROJECT_VERSION = 147;\nCURRENT_PROJECT_VERSION = 147;\n"


def feed(top):
    return {"apps": [{"bundleIdentifier": "net.opik.orbit.voice", "versions": [{"buildVersion": str(top)}, {"buildVersion": str(top - 1)}]}]}


class Derive(unittest.TestCase):
    def run_main(self, pbx, fetch, env=None):
        with tempfile.NamedTemporaryFile("w", suffix=".pbxproj", delete=False) as f:
            f.write(pbx)
        self.addCleanup(os.unlink, f.name)
        buf = io.StringIO()
        old = os.environ.pop("GITHUB_OUTPUT", None)
        if env:
            os.environ["GITHUB_OUTPUT"] = env
        try:
            rc = d.main(["--project", f.name], fetch=fetch, out=buf)
        finally:
            os.environ.pop("GITHUB_OUTPUT", None)
            if old is not None:
                os.environ["GITHUB_OUTPUT"] = old
        return rc, json.loads(buf.getvalue())

    def test_live_plus_one(self):
        rc, res = self.run_main(PBX, lambda url: feed(147))
        self.assertEqual((rc, res["buildNumber"], res["reason"]), (0, 148, "live+1"))

    def test_source_newer_than_live_plus_one_is_kept(self):
        rc, res = self.run_main(PBX, lambda url: feed(100))
        self.assertEqual((rc, res["buildNumber"], res["reason"]), (0, 147, "source_is_newer"))

    def test_fails_closed_without_feed(self):
        def boom(url):
            raise d.cbm.Unverifiable("FEED_UNAVAILABLE")
        rc, res = self.run_main(PBX, boom)
        self.assertEqual((rc, res["result"]), (2, "UNKNOWN"))

    def test_ambiguous_source_fails_closed(self):
        rc, res = self.run_main("CURRENT_PROJECT_VERSION = 1;\nCURRENT_PROJECT_VERSION = 2;\n", lambda url: feed(5))
        self.assertEqual((rc, res["result"]), (2, "UNKNOWN"))

    def test_github_output_written(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as o:
            pass
        self.addCleanup(os.unlink, o.name)
        rc, _ = self.run_main(PBX, lambda url: feed(150), env=o.name)
        self.assertEqual(rc, 0)
        self.assertEqual(open(o.name).read().strip(), "build_number=151")


if __name__ == "__main__":
    unittest.main()
