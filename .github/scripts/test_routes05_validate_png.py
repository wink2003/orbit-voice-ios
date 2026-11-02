#!/usr/bin/env python3
import importlib.util
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path


SCRIPT = Path(__file__).with_name("routes05_validate_png.py")
SPEC = importlib.util.spec_from_file_location("routes05_validate_png", SCRIPT)
VALIDATOR = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(VALIDATOR)


def write_png(path: Path, populated: bool, palette_size: int | None = None) -> None:
    width = height = 48
    rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            if populated and palette_size:
                index = (y * width + x) % palette_size
                row.extend(((index * 9) & 255, (index * 13) & 255, (index * 17) & 255, 255))
            elif populated:
                row.extend(((x * 5) & 255, (y * 5) & 255, ((x + y) * 3) & 255, 255))
            else:
                row.extend((17, 24, 21, 255))
        rows.append(row)

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

    payload = b"".join(rows)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(payload))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


class Routes05PNGValidatorTests(unittest.TestCase):
    def write_contract(self, root: Path, **overrides: object) -> Path:
        contract = {
            "route": "timetable",
            "captureID": "capture-1",
            "contentReady": True,
            "contentCount": 5,
            "visibleLessonCount": 5,
            "visibleDayCount": 5,
            "selectedWeek": "2026-11-02",
            "scrollHorizontal": True,
        }
        contract.update(overrides)
        path = root / "ready.json"
        path.write_text(json.dumps(contract), encoding="utf-8")
        return path

    def test_populated_exams_image_with_23_colors_passes_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "exams-dark.png"
            contract = root / "ready.json"
            write_png(image, populated=True, palette_size=23)
            contract.write_text(json.dumps({"route": "exams", "contentReady": True, "contentCount": 3}), encoding="utf-8")
            self.assertEqual(VALIDATOR.validate_png(str(image), "exams", str(contract)), 23)

    def test_populated_exams_contract_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "exams-dark.png"
            contract = root / "ready.json"
            write_png(image, populated=True)
            contract.write_text(json.dumps({"route": "exams", "contentReady": True, "contentCount": 3}), encoding="utf-8")
            self.assertGreaterEqual(VALIDATOR.validate_png(str(image), "exams", str(contract)), 24)

    def test_blank_exams_image_fails_even_with_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "blank.png"
            contract = root / "ready.json"
            write_png(image, populated=False)
            contract.write_text(json.dumps({"route": "exams", "contentReady": True, "contentCount": 3}), encoding="utf-8")
            with self.assertRaises(ValueError):
                VALIDATOR.validate_png(str(image), "exams", str(contract))

    def test_populated_timetable_light_and_dark_pass_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for appearance in ("light", "dark"):
                image = root / f"timetable-{appearance}.png"
                write_png(image, populated=True, palette_size=20)
                contract = self.write_contract(root)
                self.assertEqual(VALIDATOR.validate_png(str(image), "timetable", str(contract), "capture-1"), 20)

    def test_blank_timetable_fails_even_with_rendered_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "blank.png"
            write_png(image, populated=False)
            contract = self.write_contract(root)
            with self.assertRaises(ValueError):
                VALIDATOR.validate_png(str(image), "timetable", str(contract), "capture-1")

    def test_timetable_rejects_missing_stale_and_false_readiness(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "timetable.png"
            write_png(image, populated=True, palette_size=20)
            for overrides, capture_id in (
                ({"captureID": "old-capture"}, "capture-1"),
                ({"contentReady": False}, "capture-1"),
                ({"contentCount": 0}, "capture-1"),
                ({"visibleLessonCount": 0}, "capture-1"),
                ({"scrollHorizontal": False}, "capture-1"),
            ):
                contract = self.write_contract(root, **overrides)
                with self.assertRaises(ValueError):
                    VALIDATOR.validate_png(str(image), "timetable", str(contract), capture_id)
            with self.assertRaises(ValueError):
                VALIDATOR.validate_png(str(image), "timetable", None, "capture-1")

    def test_timetable_rejects_wrong_route_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "timetable.png"
            write_png(image, populated=True, palette_size=20)
            contract = self.write_contract(root, route="exams")
            with self.assertRaises(ValueError):
                VALIDATOR.validate_png(str(image), "timetable", str(contract), "capture-1")

    def test_exams_without_rendered_entries_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            image = root / "image.png"
            contract = root / "ready.json"
            write_png(image, populated=True)
            contract.write_text(json.dumps({"route": "exams", "contentReady": False, "contentCount": 0}), encoding="utf-8")
            with self.assertRaises(ValueError):
                VALIDATOR.validate_png(str(image), "exams", str(contract))


if __name__ == "__main__":
    unittest.main()
