#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compare locked Emacs package versions against online archives and overlay tip."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]

ARCHIVES = {
    "melpa": "https://melpa.org/packages/archive-contents",
    "gnu-elpa": "https://elpa.gnu.org/packages/archive-contents",
    "nongnu-elpa": "https://elpa.nongnu.org/nongnu/archive-contents",
}

# pname in Nix -> archive key when names differ.
ARCHIVE_ALIASES: dict[str, str] = {}

COMMIT_RE = re.compile(r"\(:commit\s+\.\s+\"([0-9a-f]+)\"\)")


@dataclass(frozen=True)
class ArchiveEntry:
    version: str
    commit: str | None
    archive: str


def fetch_text(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "ch-emacs-config-compare/1.0"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read().decode("utf-8", errors="replace")


def parse_version_at(text: str, start: int) -> str | None:
    melpa_match = re.match(r"\((\d{8})\s+(\d+)\)", text[start:])
    if melpa_match:
        minute = melpa_match.group(2).lstrip("0") or "0"
        return f"{melpa_match.group(1)}.{minute}"

    quoted_match = re.match(r'"([^"]+)"', text[start:])
    if quoted_match:
        return quoted_match.group(1)

    list_match = re.match(r"\(([^)\]]+)\)", text[start:])
    if list_match:
        parts = list_match.group(1).split()
        if parts and all(part.isdigit() for part in parts):
            return ".".join(parts)
    return None


def lookup_in_archive(text: str, pname: str, archive: str) -> ArchiveEntry | None:
    match = re.search(rf"\({re.escape(pname)}\s+\.\s+\[", text)
    if not match:
        return None

    start = match.end()
    version = parse_version_at(text, start)
    if not version:
        return None

    snippet = text[start : start + 2500]
    commit_match = COMMIT_RE.search(snippet)
    commit = commit_match.group(1) if commit_match else None
    return ArchiveEntry(version=version, commit=commit, archive=archive)


def load_archives() -> dict[str, tuple[str, str]]:
    """Return archive name -> (url, contents)."""
    loaded: dict[str, tuple[str, str]] = {}
    for archive, url in ARCHIVES.items():
        print(f"Fetching {archive}...", file=sys.stderr)
        loaded[archive] = (url, fetch_text(url))
    return loaded


def melpa_version_key(version: str) -> tuple[int, int] | None:
    match = re.fullmatch(r"(\d{8})\.(\d+)", version)
    if not match:
        return None
    return int(match.group(1)), int(match.group(2))


def compare_versions(locked: str, online: str) -> int:
    """Return -1 if locked is older, 0 if equal, 1 if locked is newer."""
    locked_key = melpa_version_key(locked)
    online_key = melpa_version_key(online)
    if locked_key and online_key:
        if locked_key < online_key:
            return -1
        if locked_key > online_key:
            return 1
        return 0
    if locked == online:
        return 0
    return 0


def lookup_archive(pname: str, archives: dict[str, tuple[str, str]]) -> ArchiveEntry | None:
    candidates = [pname, ARCHIVE_ALIASES.get(pname)]
    for archive, (_url, contents) in archives.items():
        for candidate in candidates:
            if not candidate:
                continue
            entry = lookup_in_archive(contents, candidate, archive)
            if entry:
                return entry
    return None


def build_manifest(
    repo_root: Path,
    *,
    overlay_tip: bool,
) -> dict[str, Any]:
    cmd = [
        "nix",
        "build",
        ".#packages.x86_64-linux.emacs-package-manifest",
        "--print-out-paths",
        "--no-link",
    ]
    if overlay_tip:
        cmd.extend(
            [
                "--override-input",
                "emacs-overlay",
                "github:nix-community/emacs-overlay",
            ]
        )
    result = subprocess.run(
        cmd,
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    )
    out_path = result.stdout.strip().splitlines()[-1]
    return json.loads(Path(out_path).read_text())


def overlay_lock_info(repo_root: Path) -> dict[str, Any]:
    lock_path = repo_root / "flake.lock"
    lock = json.loads(lock_path.read_text())
    node = lock["nodes"]["emacs-overlay"]["locked"]
    return {
        "rev": node["rev"],
        "lastModified": node.get("lastModified"),
    }


def fetch_overlay_tip_rev() -> str | None:
    url = "https://api.github.com/repos/nix-community/emacs-overlay/commits/HEAD"
    request = urllib.request.Request(url, headers={"User-Agent": "ch-emacs-config-compare/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
        return payload["sha"]
    except (urllib.error.URLError, KeyError, json.JSONDecodeError):
        return None


def classify_row(
    entry: dict[str, Any],
    archive: ArchiveEntry | None,
    tip_entry: dict[str, Any] | None,
) -> str:
    source = entry["source"]
    locked_version = entry["version"]
    locked_rev = entry.get("rev")

    if source == "local":
        return "local-only"
    if entry.get("patched"):
        if archive:
            cmp = compare_versions(locked_version, archive.version)
            if cmp < 0:
                return "patched (behind)"
        return "patched"
    if source == "treesit-grammar":
        return "treesit-grammar"

    if archive and locked_rev and archive.commit:
        if archive.commit.startswith(locked_rev[: len(archive.commit)]) or locked_rev.startswith(
            archive.commit[: len(locked_rev)]
        ):
            return "current"

    if archive:
        cmp = compare_versions(locked_version, archive.version)
        if cmp < 0:
            return "behind"
        if cmp > 0:
            return "ahead"
        return "current"

    if tip_entry and tip_entry["version"] != locked_version:
        return "needs-manual-review"

    return "not-found"


def format_online(entry: ArchiveEntry | None) -> str:
    if not entry:
        return "-"
    return f"{entry.version} ({entry.archive})"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        type=Path,
        help="Use an existing emacs-package-manifest.json instead of building.",
    )
    parser.add_argument(
        "--with-overlay-tip",
        action="store_true",
        help="Also build manifest against emacs-overlay HEAD (slow; needs network).",
    )
    parser.add_argument(
        "--markdown",
        action="store_true",
        help="Print markdown instead of a plain text table.",
    )
    args = parser.parse_args()

    if args.manifest:
        manifest = json.loads(args.manifest.read_text())
    else:
        print("Building locked manifest via Nix...", file=sys.stderr)
        manifest = build_manifest(REPO_ROOT, overlay_tip=False)

    tip_by_pname: dict[str, dict[str, Any]] = {}
    if args.with_overlay_tip:
        print("Building overlay-tip manifest via Nix...", file=sys.stderr)
        tip_manifest = build_manifest(REPO_ROOT, overlay_tip=True)
        tip_by_pname = {entry["pname"]: entry for entry in tip_manifest["packages"]}

    archive_sources = load_archives()
    lock_info = overlay_lock_info(REPO_ROOT)
    tip_rev = fetch_overlay_tip_rev()

    rows: list[tuple[str, str, str, str, str, str]] = []
    status_counts: dict[str, int] = {}

    for entry in manifest["packages"]:
        archive = lookup_archive(entry["pname"], archive_sources)
        tip_entry = tip_by_pname.get(entry["pname"])
        status = classify_row(entry, archive, tip_entry)
        status_counts[status] = status_counts.get(status, 0) + 1

        tip_version = tip_entry["version"] if tip_entry else "-"
        rows.append(
            (
                entry["pname"],
                entry["bundle"],
                entry["version"],
                format_online(archive),
                tip_version,
                status,
            )
        )

    if args.markdown:
        print("# Emacs package version comparison\n")
        print(f"- Emacs: {manifest.get('emacsVersion', '?')}")
        print(f"- Locked emacs-overlay: `{manifest.get('emacsOverlayRev', '?')}`")
        if lock_info.get("lastModified"):
            print(f"- Overlay lock lastModified: {lock_info['lastModified']}")
        if tip_rev:
            print(f"- emacs-overlay HEAD: `{tip_rev}`")
        print()
        print("| Package | Bundle | Locked | Online | Overlay tip | Status |")
        print("|---------|--------|--------|--------|-------------|--------|")
        for row in rows:
            print("| " + " | ".join(row) + " |")
        print()
        print("## Summary\n")
        for status, count in sorted(status_counts.items()):
            print(f"- {status}: {count}")
    else:
        print(f"Emacs {manifest.get('emacsVersion', '?')}")
        print(f"Locked overlay {manifest.get('emacsOverlayRev', '?')}")
        if tip_rev:
            print(f"Overlay HEAD {tip_rev}")
        print()
        print(f"{'Package':<32} {'Bundle':<14} {'Locked':<22} {'Online':<28} {'Tip':<22} Status")
        print("-" * 140)
        for row in rows:
            print(
                f"{row[0]:<32} {row[1]:<14} {row[2]:<22} {row[3]:<28} {row[4]:<22} {row[5]}"
            )
        print()
        print("Summary:", ", ".join(f"{k}={v}" for k, v in sorted(status_counts.items())))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
