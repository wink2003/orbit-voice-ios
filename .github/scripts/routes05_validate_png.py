#!/usr/bin/env python3
"""Reject PNG captures that contain only a blank surface/status bar."""

import argparse
import json
import struct
import sys
import zlib


def validate_png(
    path: str,
    route: str | None = None,
    ready_json: str | None = None,
    capture_id: str | None = None,
) -> int:
    if route in {"exams", "timetable"}:
        if not ready_json:
            raise ValueError(f"{route} route requires a readiness contract")
        with open(ready_json, "r", encoding="utf-8") as handle:
            contract = json.load(handle)
        if contract.get("route") != route:
            raise ValueError(f"{route} readiness contract has the wrong route")
        if capture_id and contract.get("captureID") != capture_id:
            raise ValueError(f"{route} readiness contract has a stale capture ID")
        if contract.get("contentReady") is not True:
            raise ValueError(f"{route} readiness contract is not content-ready")
        if not isinstance(contract.get("contentCount"), int) or contract["contentCount"] < 1:
            raise ValueError(f"{route} readiness contract has no rendered entries")
        if route == "timetable":
            if not isinstance(contract.get("visibleLessonCount"), int) or contract["visibleLessonCount"] < 1:
                raise ValueError("timetable readiness contract has no visible lessons")
            if contract.get("selectedWeek") in (None, "") or contract.get("visibleDayCount") != 5:
                raise ValueError("timetable readiness contract has incomplete week coverage")
            if contract.get("scrollHorizontalSettled") is not True:
                raise ValueError("timetable readiness contract did not settle horizontal capture state")

    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    offset = 8
    compressed = bytearray()
    width = height = color_type = bit_depth = interlace = None
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
    if bit_depth != 8 or interlace != 0 or color_type not in (2, 6):
        raise ValueError("unsupported PNG format")

    decoded = zlib.decompress(bytes(compressed))
    bytes_per_pixel = 3 if color_type == 2 else 4
    stride = width * bytes_per_pixel
    previous = bytearray(stride)
    colors = set()
    cursor = 0
    for y in range(height):
        filter_type = decoded[cursor]
        row = bytearray(decoded[cursor + 1 : cursor + 1 + stride])
        cursor += stride + 1
        for index in range(stride):
            left = row[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            up = previous[index]
            upper_left = previous[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            if filter_type == 1:
                row[index] = (row[index] + left) & 255
            elif filter_type == 2:
                row[index] = (row[index] + up) & 255
            elif filter_type == 3:
                row[index] = (row[index] + ((left + up) // 2)) & 255
            elif filter_type == 4:
                prediction = left + up - upper_left
                distances = (abs(prediction - left), abs(prediction - up), abs(prediction - upper_left))
                predictor = (left, up, upper_left)[distances.index(min(distances))]
                row[index] = (row[index] + predictor) & 255
            elif filter_type != 0:
                raise ValueError("unsupported PNG filter")
        if y % max(1, height // 48) == 0:
            for x in range(0, width, max(1, width // 48)):
                pixel = tuple(row[x * bytes_per_pixel : x * bytes_per_pixel + 3])
                colors.add(tuple(channel // 8 for channel in pixel))
        previous = row
    minimum_colors = 8 if route in {"exams", "timetable"} else 24
    if len(colors) < minimum_colors:
        raise ValueError(f"content-blank PNG: only {len(colors)} sampled colors (minimum {minimum_colors})")
    return len(colors)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--route")
    parser.add_argument("--ready-json")
    parser.add_argument("--capture-id")
    args = parser.parse_args()
    try:
        count = validate_png(args.path, args.route, args.ready_json, args.capture_id)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(str(error)) from error
    print(f"png-content-ok sampled_colors={count}")


if __name__ == "__main__":
    main()
