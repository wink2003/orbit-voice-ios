#!/usr/bin/env python3
"""Reject PNG captures that contain only a blank surface/status bar."""

import struct
import sys
import zlib


def main(path: str) -> None:
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit("not a PNG")
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
        raise SystemExit("unsupported PNG format")

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
                raise SystemExit("unsupported PNG filter")
        if y % max(1, height // 48) == 0:
            for x in range(0, width, max(1, width // 48)):
                pixel = tuple(row[x * bytes_per_pixel : x * bytes_per_pixel + 3])
                colors.add(tuple(channel // 8 for channel in pixel))
        previous = row
    if len(colors) < 24:
        raise SystemExit(f"content-blank PNG: only {len(colors)} sampled colors")
    print(f"png-content-ok sampled_colors={len(colors)}")


if __name__ == "__main__":
    main(sys.argv[1])
