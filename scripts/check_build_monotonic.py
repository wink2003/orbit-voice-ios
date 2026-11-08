#!/usr/bin/env python3
"""Early build-number monotonicity check for Main Orbit (issue #28).

A candidate Main Orbit build must be STRICTLY newer than the build currently published in the public SideStore feed.  The
canonical IOS_IPA admission (`ipa-plan`, root-owned intent/manifest, Guard/Passkey) is the only release authority and re-checks
this; this script is only an EARLY, CHEAP, ADVISORY signal so an equal/older number fails in seconds instead of after the macOS IPA build
and after a CI-green artifact has already been mistaken for an eligible release.  It never publishes, signs, increments or edits anything.

Exit codes:  0 PASS (candidate > live)   1 FAIL (candidate <= live)   2 UNKNOWN (live state unavailable/unverifiable -> fail closed)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from typing import Any, Callable, Sequence

EXIT_PASS, EXIT_FAIL, EXIT_UNKNOWN = 0, 1, 2
DEFAULT_FEED = "https://voice.orbit.opik.net/altstore/orbit.json"
DEFAULT_BUNDLE = "net.opik.orbit.voice"
BUILD_RE = re.compile(r"CURRENT_PROJECT_VERSION\s*=\s*([^;\s]+)\s*;")
DIGITS = re.compile(r"^[0-9]{1,9}$")
MAX_FEED_BYTES = 8 * 1024 * 1024


class Unverifiable(Exception):
    """The candidate or the live state cannot be established; callers must fail closed."""


def candidate_build(project_text: str) -> int:
    """The single CURRENT_PROJECT_VERSION used by every build configuration of the project (all must agree)."""
    values = set(BUILD_RE.findall(project_text))
    if not values: raise Unverifiable("CANDIDATE_BUILD_NOT_FOUND")
    if len(values) != 1: raise Unverifiable("CANDIDATE_BUILD_AMBIGUOUS:" + ",".join(sorted(values)))
    (value,) = values
    if not DIGITS.match(value): raise Unverifiable("CANDIDATE_BUILD_NOT_NUMERIC:" + value[:20])
    return int(value)


def live_build(feed: Any, bundle: str) -> int:
    """Highest published build of `bundle`; the feed must list newest-first (top entry == highest) or it is not trusted."""
    apps = feed.get("apps") if isinstance(feed, dict) else None
    if not isinstance(apps, list): raise Unverifiable("FEED_SHAPE_INVALID")
    mine = [a for a in apps if isinstance(a, dict) and a.get("bundleIdentifier") == bundle]
    if len(mine) != 1: raise Unverifiable("FEED_BUNDLE_NOT_FOUND_OR_DUPLICATED")
    versions = mine[0].get("versions")
    if not isinstance(versions, list) or not versions: raise Unverifiable("FEED_VERSIONS_MISSING")
    builds = []
    for v in versions:
        b = str(v.get("buildVersion", "")) if isinstance(v, dict) else ""
        if not DIGITS.match(b): raise Unverifiable("FEED_BUILD_NOT_NUMERIC")
        builds.append(int(b))
    if builds[0] != max(builds): raise Unverifiable("FEED_NOT_NEWEST_FIRST")
    return builds[0]


def fetch_feed(url: str, timeout: float = 20.0, opener: Callable[..., Any] = urllib.request.urlopen) -> Any:
    if not url.startswith("https://"): raise Unverifiable("FEED_URL_NOT_HTTPS")
    try:
        with opener(urllib.request.Request(url, headers={"User-Agent": "orbit-build-monotonic-check"}), timeout=timeout) as resp:
            if getattr(resp, "status", 200) != 200: raise Unverifiable(f"FEED_HTTP_{resp.status}")
            raw = resp.read(MAX_FEED_BYTES + 1)
    except Unverifiable:
        raise
    except urllib.error.HTTPError as exc:
        raise Unverifiable(f"FEED_HTTP_{exc.code}") from exc
    except (urllib.error.URLError, OSError, ValueError) as exc:
        raise Unverifiable("FEED_UNAVAILABLE") from exc
    if len(raw) > MAX_FEED_BYTES: raise Unverifiable("FEED_TOO_LARGE")
    try: return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc: raise Unverifiable("FEED_NOT_JSON") from exc


def evaluate(candidate: int, live: int) -> dict[str, Any]:
    ok = candidate > live
    out: dict[str, Any] = {"result": "PASS" if ok else "FAIL", "candidateBuild": candidate, "liveBuild": live}
    if not ok:
        out["code"] = "BUILD_NOT_NEWER_THAN_LIVE"
        out["action"] = (f"candidate build {candidate} is not newer than the published build {live}: bump CURRENT_PROJECT_VERSION "
                         f"(the two settings in project.pbxproj) to a number > {live} in a separate PR, merge it, and let the push CI run on that exact commit")
    return out


def main(argv: Sequence[str] | None = None, *, fetch: Callable[[str], Any] | None = None, out=None) -> int:
    out = out or sys.stdout
    ap = argparse.ArgumentParser(prog="check_build_monotonic")
    ap.add_argument("--project", required=True, help="path to project.pbxproj")
    ap.add_argument("--bundle", default=DEFAULT_BUNDLE)
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--feed-url", default=DEFAULT_FEED)
    src.add_argument("--feed-file", help="read the feed from a local file (tests / offline)")
    a = ap.parse_args(argv)
    try:
        with open(a.project, encoding="utf-8") as fh: cand = candidate_build(fh.read())
        if a.feed_file:
            with open(a.feed_file, encoding="utf-8") as fh: feed = json.load(fh)
        else:
            feed = (fetch or fetch_feed)(a.feed_url)
        res = evaluate(cand, live_build(feed, a.bundle))
    except (Unverifiable, OSError, ValueError) as exc:
        code = str(exc) if isinstance(exc, Unverifiable) else "INPUT_UNREADABLE:" + type(exc).__name__
        out.write(json.dumps({"result": "UNKNOWN", "code": code, "action": "live Main Orbit state could not be established; failing closed (the canonical ipa-plan remains the authority)"}) + "\n")
        return EXIT_UNKNOWN
    out.write(json.dumps(res) + "\n")
    return EXIT_PASS if res["result"] == "PASS" else EXIT_FAIL


if __name__ == "__main__":
    raise SystemExit(main())
