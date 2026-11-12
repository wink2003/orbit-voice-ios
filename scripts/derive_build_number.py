#!/usr/bin/env python3
"""Derive the Main Orbit build number for a release-branch CI build: max(published SideStore build + 1, source CURRENT_PROJECT_VERSION).

Replaces the manual "bump PR" (owner decision 2026-11-12). The number is passed to xcodebuild as a CURRENT_PROJECT_VERSION override, so the
IPA's Info.plist carries it; the canonical IOS_IPA pipeline reads the build number from the IPA, never from the source tree, and its own
admission (`ipa-plan`) still re-checks monotonicity against the live feed.  The source project.pbxproj is NOT edited.

Fails closed (exit 2) when the live feed cannot be established or the source number is ambiguous.  Never publishes anything.
Output: one JSON line; with GITHUB_OUTPUT set also `build_number=<n>`.
"""
from __future__ import annotations

import argparse, json, os, sys
from typing import Any, Callable, Sequence

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_build_monotonic as cbm  # noqa: E402


def derive(source_build: int, live: int) -> dict[str, Any]:
    n = max(live + 1, source_build)
    return {"result": "DERIVED", "buildNumber": n, "liveBuild": live, "sourceBuild": source_build,
            "reason": "live+1" if n == live + 1 else "source_is_newer"}


def main(argv: Sequence[str] | None = None, *, fetch: Callable[[str], Any] | None = None, out=None) -> int:
    out = out or sys.stdout
    ap = argparse.ArgumentParser(prog="derive_build_number")
    ap.add_argument("--project", required=True)
    ap.add_argument("--bundle", default=cbm.DEFAULT_BUNDLE)
    src = ap.add_mutually_exclusive_group()
    src.add_argument("--feed-url", default=cbm.DEFAULT_FEED)
    src.add_argument("--feed-file")
    a = ap.parse_args(argv)
    try:
        with open(a.project, encoding="utf-8") as fh:
            source = cbm.candidate_build(fh.read())
        if a.feed_file:
            with open(a.feed_file, encoding="utf-8") as fh:
                feed = json.load(fh)
        else:
            feed = (fetch or cbm.fetch_feed)(a.feed_url)
        res = derive(source, cbm.live_build(feed, a.bundle))
    except (cbm.Unverifiable, OSError, ValueError) as exc:
        code = str(exc) if isinstance(exc, cbm.Unverifiable) else "INPUT_UNREADABLE:" + type(exc).__name__
        out.write(json.dumps({"result": "UNKNOWN", "code": code, "action": "live Main Orbit state could not be established; failing closed"}) + "\n")
        return cbm.EXIT_UNKNOWN
    out.write(json.dumps(res) + "\n")
    gh = os.environ.get("GITHUB_OUTPUT")
    if gh:
        with open(gh, "a", encoding="utf-8") as fh:
            fh.write(f"build_number={res['buildNumber']}\n")
    return cbm.EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
