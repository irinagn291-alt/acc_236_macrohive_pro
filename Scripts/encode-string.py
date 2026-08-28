#!/usr/bin/env python3
import sys

_KEY = [0xA7, 0x3E, 0x91, 0x5C, 0xD2]


def encode(value: str) -> list[int]:
    return [byte ^ _KEY[index % len(_KEY)] for index, byte in enumerate(value.encode())]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <string>", file=sys.stderr)
        sys.exit(1)
    encoded = encode(sys.argv[1])
    print(f"[{', '.join(str(byte) for byte in encoded)}]")
