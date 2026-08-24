from __future__ import annotations

import argparse
import json
import sys


def reject_duplicates(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON object key")
        result[key] = value
    return result


def validate(text: str, json_lines: bool) -> None:
    values = text.splitlines() if json_lines else [text]
    for index, value in enumerate(values, start=1):
        if json_lines and not value.strip():
            continue
        try:
            json.loads(value, object_pairs_hook=reject_duplicates)
        except Exception as error:
            label = f"line {index}: " if json_lines else ""
            raise ValueError(label + str(error)) from error


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-lines", action="store_true")
    args = parser.parse_args()
    validate(sys.stdin.buffer.read().decode("utf-8-sig"), args.json_lines)


if __name__ == "__main__":
    main()
