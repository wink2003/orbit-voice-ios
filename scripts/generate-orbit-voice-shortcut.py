#!/usr/bin/env python3
"""Generate the external Orbit Voice Shortcut used to start Orbit Mini.

This intentionally contains no Mini lifecycle or return-to-app logic.  The
public AppIntent is the only product action; previous-app restoration belongs
to the user's separate Personal Automation (see the workflow README).
"""

from __future__ import annotations

import argparse
import plistlib
import uuid
from pathlib import Path


MINI_BUNDLE_ID = "net.opik.orbit.mini"
MINI_INTENT = "StartOrbitMiniHandsFreeIntent"
SHORTCUT_NAME = "Orbit Voice"


def stable_uuid(label: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"https://orbit.family/shortcut/{label}"))


def generate() -> dict:
    get_current_app_uuid = stable_uuid("get-current-app")
    start_intent_uuid = stable_uuid("start-mini-hands-free")
    return {
        "WFWorkflowName": SHORTCUT_NAME,
        "WFWorkflowDescription": (
            "Captures the current app at the Shortcuts boundary, then invokes "
            "Orbit Mini hands-free. Return-to-previous-app is configured by "
            "the separate Personal Automation."
        ),
        "WFWorkflowClientVersion": "2600.0",
        "WFWorkflowClientRelease": "2.0",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientRelease": "2.0",
        "WFWorkflowIcon": {
            "WFWorkflowIconStartColor": 4282601983,
            "WFWorkflowIconGlyphNumber": 59511,
        },
        "WFWorkflowTypes": ["NCWidget", "WatchKit"],
        "WFWorkflowImportQuestions": [],
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowActions": [
            {
                "WFWorkflowActionIdentifier": "is.workflow.actions.getcurrentapp",
                "WFWorkflowActionParameters": {"UUID": get_current_app_uuid},
            },
            {
                "WFWorkflowActionIdentifier": f"{MINI_BUNDLE_ID}.{MINI_INTENT}",
                "WFWorkflowActionParameters": {
                    "AppIntentDescriptor": {
                        "AppIntentIdentifier": MINI_INTENT,
                        "BundleIdentifier": MINI_BUNDLE_ID,
                        "Name": "Orbit Mini",
                    },
                    # AppIntent metadata says openAppWhenRun=true.  Shortcuts
                    # serializes that property as OpenWhenRun (not
                    # ShowWhenRun, which is a different action convention).
                    "OpenWhenRun": True,
                    "UUID": start_intent_uuid,
                },
            },
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as handle:
        plistlib.dump(generate(), handle, fmt=plistlib.FMT_BINARY, sort_keys=True)


if __name__ == "__main__":
    main()
