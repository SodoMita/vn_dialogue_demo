#!/usr/bin/env python3
"""Stamp a vn_dialogue_demo export with its release identity.

Writes <build_dir>/version.json and injects a small version badge plus the
repo link into the exported web player so any release is identifiable from
the browser.

Usage: python3 scripts/stamp_release.py BUILD_DIR VERSION [COMMIT] [BRANCH]
"""
from __future__ import annotations

import datetime as _dt
import json
import pathlib
import re
import sys

REPO_URL = "https://github.com/SodoMita/vn_dialogue_demo"


def main(argv: list[str]) -> int:
    build_dir = pathlib.Path(argv[1] if len(argv) > 1 else "build/web")
    version = argv[2] if len(argv) > 2 else "0.0.0-dev"
    commit = argv[3] if len(argv) > 3 else "local"
    branch = argv[4] if len(argv) > 4 else "local"

    build_dir.mkdir(parents=True, exist_ok=True)
    stamp = {
        "game": "vn_dialogue_demo",
        "version": version,
        "commit": commit,
        "branch": branch,
        "built_at": _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo_url": REPO_URL,
    }
    (build_dir / "version.json").write_text(json.dumps(stamp, indent=2) + "\n", encoding="utf-8")

    index = build_dir / "index.html"
    if not index.is_file():
        print(f"stamp: no web player at {index}")
        return 0

    html = index.read_text(encoding="utf-8")
    title = f"VN Dialogue Demo {version}"
    html = re.sub(r"<title>.*?</title>", f"<title>{title}</title>", html, count=1, flags=re.S)

    badge = (
        f'<div id="vn-build-badge" style="position:fixed;right:10px;bottom:10px;'
        f'z-index:99;font:12px/1.4 system-ui,-apple-system,Segoe UI,sans-serif;'
        f'color:#e8f0ff;background:rgba(10,14,24,.72);border:1px solid rgba(180,200,255,.35);'
        f'border-radius:8px;padding:6px 10px;backdrop-filter:blur(6px);pointer-events:auto">'
        f'<b>VN Demo</b> {version} · {commit[:8]}'
        f'&nbsp;<a href="{REPO_URL}" style="color:#a9c9ff">github</a></div>'
    )
    if "vn-build-badge" not in html and "</body>" in html:
        html = html.replace("</body>", badge + "\n</body>", 1)
    index.write_text(html, encoding="utf-8")
    print(f"stamp: {index} -> {title} ({commit[:8]} on {branch})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
