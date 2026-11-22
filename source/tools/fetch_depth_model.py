#!/usr/bin/env python3
"""
Downloads Apple's official Core ML Depth Anything V2 Small (Float16) model
from Hugging Face (apple/coreml-depth-anything-v2-small) into:
  source/NEELx/Models/DepthAnythingV2SmallF16.mlpackage

Uses only Python's standard library so no virtualenv or pip packages are needed.
"""

import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

# Pin exact commit revision from Hugging Face for deterministic, reproducible builds (Item #5)
REPO_ID = "apple/coreml-depth-anything-v2-small"
PINNED_REVISION = "cfef6f6f2a70783dedc0bfae40cecbc2052285d3"
MODEL_DIR_NAME = "DepthAnythingV2SmallF16.mlpackage"
API_BASE = f"https://huggingface.co/api/models/{REPO_ID}/tree/{PINNED_REVISION}"
RAW_BASE = f"https://huggingface.co/{REPO_ID}/resolve/{PINNED_REVISION}"

# Cryptographic SHA-256 hashes of expected model files for supply-chain integrity verification
EXPECTED_SHA256 = {
    "Manifest.json": "2883ae290c48fe916dc5ececac03a7d847fa277165a49ef5652fa1d2b9cb55f7",
    "Data/com.apple.CoreML/model.mlmodel": "44ac97a3efcfd52113183fb2862ff59cd0368e9ec2e30a90a54980dd11407042",
    "Data/com.apple.CoreML/weights/weight.bin": "fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed",
}

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


def compute_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1024 * 512):
            h.update(chunk)
    return h.hexdigest()


def download_file(remote_path: str, local_path: Path, expected_size: int, rel_path: str) -> None:
    local_path.parent.mkdir(parents=True, exist_ok=True)
    expected_hash = EXPECTED_SHA256.get(rel_path)

    if local_path.exists() and expected_size > 0 and local_path.stat().st_size == expected_size:
        if expected_hash:
            actual_hash = compute_sha256(local_path)
            if actual_hash == expected_hash:
                print(f"  [cached & verified] {rel_path} (SHA-256: {actual_hash[:12]}...)")
                return
            else:
                print(f"  [checksum mismatch] {rel_path} cached hash invalid, redownloading...")
        else:
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

    # Verify cryptographic checksum before moving into place
    if expected_hash:
        actual_hash = compute_sha256(tmp_path)
        if actual_hash != expected_hash:
            tmp_path.unlink(missing_ok=True)
            raise RuntimeError(f"Integrity check failed for {rel_path}! Expected {expected_hash}, got {actual_hash}")
        print(f"  [verified] {rel_path} (SHA-256: {actual_hash[:12]}...)")

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
        download_file(remote_path, local_path, size, rel)

    print(f"\n✅ Downloaded {MODEL_DIR_NAME} successfully to {DEST_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
