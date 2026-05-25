#!/usr/bin/env python3
"""Patch xmake.lua for static libpython (Cambricon aarch64) builds."""
from __future__ import annotations

import sys
from pathlib import Path


def patch_xmake(path: Path) -> None:
    if not path.is_file():
        return
    text = path.read_text()
    if "headeronly = true" in text:
        return
    lines = text.splitlines()
    out: list[str] = []
    in_ext_target = False
    inserted_shflags = False
    inserted_conf = False
    for line in lines:
        if not inserted_conf and line.strip() == 'add_requires("pybind11")':
            out.append(line)
            out.append(
                'add_requireconfs("python 3.x", {override = true, configs = {headeronly = true}})'
            )
            inserted_conf = True
            continue
        stripped = line.strip()
        if stripped.startswith('target("_infi') and (
            stripped.endswith('core")') or stripped.endswith('lm")')
        ):
            in_ext_target = True
            inserted_shflags = False
        elif in_ext_target and stripped == "target_end()":
            in_ext_target = False
        if in_ext_target and not inserted_shflags and 'add_rules("python.library"' in line:
            indent = line[: len(line) - len(line.lstrip())]
            out.append(
                f'{indent}add_shflags("-Wl,--unresolved-symbols=ignore-all", {{force = true}})'
            )
            inserted_shflags = True
        out.append(line)
    path.write_text("\n".join(out) + "\n")


def main() -> None:
    for arg in sys.argv[1:]:
        patch_xmake(Path(arg))


if __name__ == "__main__":
    main()
