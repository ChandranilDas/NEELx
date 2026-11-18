#!/usr/bin/env python3
"""
Downloads Apple's official Core ML Depth Anything V2 Small (Float16) model
from Hugging Face (apple/coreml-depth-anything-v2-small) into:
  source/NEELx/Models/DepthAnythingV2SmallF16.mlpackage

Uses only Python's standard library so no virtualenv or pip packages are needed.
"""

import json
import os
import sys
import urllib.request
from pathlib import Path

REPO_ID = "apple/coreml-depth-anything-v2-small"
MODEL_DIR_NAME = "DepthAnythingV2SmallF16.mlpackage"
API_BASE = f"https://huggingface.co/api/models/{REPO_ID}/tree/main"
RAW_BASE = f"https://huggingface.co/{REPO_ID}/resolve/main"

SCRIPT_DIR = Path(__file__).resolve().parent
DEST_ROOT = SCRIPT_DIR.parent / "NEELx" / "Models" / MODEL_DIR_NAME


def list_tree(subpath: str) -> list[dict]:
    url = f"{API_BASE}/{subpath}"
    req = urllib.request.Request(url, headers={"User-Agent": "NEELx-ModelFetcher/2.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def collect_files(subpath: str) -> list[tuple[str, int]]:
    files: list[tuple[str, int]] = []
    for entry in list_tree(subpath):
        entry_type = entry.get("type")
        entry_path = entry.get("path")
        if entry_type == "file":
            size = int(entry.get("size") or 0)
            files.append((entry_path, size))
        elif entry_type == "directory":
            files.extend(collect_files(entry_path))
    return files


def download_file(remote_path: str, local_path: Path, expected_size: int) -> None:
    local_path.parent.mkdir(parents=True, exist_ok=True)
    if local_path.exists() and expected_size > 0 and local_path.stat().st_size == expected_size:
        print(f"  [cached] {remote_path}")
        return

    url = f"{RAW_BASE}/{remote_path}"
    print(f"  [download] {remote_path} ({expected_size / (1024 * 1024):.2f} MB)...")
    req = urllib.request.Request(url, headers={"User-Agent": "NEELx-ModelFetcher/2.0"})
    tmp_path = local_path.with_suffix(local_path.suffix + ".part")
    with urllib.request.urlopen(req, timeout=120) as resp, open(tmp_path, "wb") as out:
        downloaded = 0
        while True:
            chunk = resp.read(1024 * 256)
            if not chunk:
                break
            out.write(chunk)
            downloaded += len(chunk)
            if expected_size > 5 * 1024 * 1024:
                pct = downloaded * 100.0 / expected_size
                print(f"\r    {downloaded / (1024 * 1024):.1f} / {expected_size / (1024 * 1024):.1f} MB ({pct:.0f}%)", end="", flush=True)
        if expected_size > 5 * 1024 * 1024:
            print()
    os.replace(tmp_path, local_path)


def main() -> int:
    print(f"Fetching {MODEL_DIR_NAME} from Hugging Face ({REPO_ID})...")
    files = collect_files(MODEL_DIR_NAME)
    if not files:
        print("Error: No model files found in repository.", file=sys.stderr)
        return 1

    total_mb = sum(s for _, s in files) / (1024 * 1024)
    print(f"Found {len(files)} files ({total_mb:.1f} MB total). Destination: {DEST_ROOT}")

    for remote_path, size in files:
        rel = remote_path[len(MODEL_DIR_NAME) + 1:]
        local_path = DEST_ROOT / rel
        download_file(remote_path, local_path, size)

    print(f"\n✅ Downloaded {MODEL_DIR_NAME} successfully to {DEST_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
