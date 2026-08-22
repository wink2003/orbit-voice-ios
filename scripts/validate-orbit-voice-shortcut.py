#!/usr/bin/env python3
"""Validate the unsigned Orbit Voice Shortcut without exposing its contents."""

from __future__ import annotations

import argparse
import plistlib
from pathlib import Path

MINI_BUNDLE_ID = "net.opik.orbit.mini"
MINI_INTENT = "StartOrbitMiniHandsFreeIntent"
SHORTCUT_NAME = "Orbit Voice"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("shortcut", type=Path)
    args = parser.parse_args()
    with args.shortcut.open("rb") as handle:
        data = plistlib.load(handle)
    actions = data.get("WFWorkflowActions")
    assert data.get("WFWorkflowName") == SHORTCUT_NAME
    assert isinstance(actions, list) and len(actions) == 2
    assert actions[0]["WFWorkflowActionIdentifier"] == "is.workflow.actions.getcurrentapp"
    expected = f"{MINI_BUNDLE_ID}.{MINI_INTENT}"
    assert actions[1]["WFWorkflowActionIdentifier"] == expected
    descriptor = actions[1]["WFWorkflowActionParameters"]["AppIntentDescriptor"]
    assert descriptor == {
        "AppIntentIdentifier": MINI_INTENT,
        "BundleIdentifier": MINI_BUNDLE_ID,
        "Name": "Orbit Mini",
    }
    assert actions[1]["WFWorkflowActionParameters"]["OpenWhenRun"] is True
    assert "ShowWhenRun" not in actions[1]["WFWorkflowActionParameters"]
    # Keep this validator intentionally strict: no arbitrary URLs, secrets, or
    # private runtime state can enter the generated artifact.
    blob = repr(data)
    for forbidden in ("http://", "https://", "token", "password", "ORBIT_HOME"):
        assert forbidden not in blob
    print("orbit-voice-shortcut-valid actions=2 appintent=StartOrbitMiniHandsFreeIntent")


if __name__ == "__main__":
    main()
