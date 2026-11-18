import os
import plistlib
import shutil
import subprocess
from pathlib import Path

base = Path(__file__).resolve().parent
src_dir = base / 'source/NEELx'
app = base / 'NEELx.app'

print("=== Building NEELx.app ===")

# Clean previous build
if app.exists():
    shutil.rmtree(app)

(app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
(app / 'Contents/Resources').mkdir(parents=True, exist_ok=True)

# Copy all resources from source/NEELx/Resources
res_dir = src_dir / 'Resources'
if res_dir.exists():
    shutil.copytree(res_dir, app / 'Contents/Resources', dirs_exist_ok=True)

# Copy icon
if (res_dir / 'NEELx.icns').exists():
    shutil.copy2(res_dir / 'NEELx.icns', app / 'Contents/Resources/NEELx.icns')

# Info.plist
info = {
    'CFBundleIdentifier': 'local.neelx',
    'CFBundleName': 'NEELx',
    'CFBundleDisplayName': 'NEELx',
    'CFBundleExecutable': 'NEELx',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '2.0.0',
    'CFBundleVersion': '2',
    'CFBundleIconFile': 'NEELx',
    'LSMinimumSystemVersion': '15.0',
    'NSPrincipalClass': 'NSApplication',
    'NSHighResolutionCapable': True,
    'NSCameraUsageDescription': 'NEELx uses the camera on-device to recognize your face for unlocking your Mac.',
    'NSHumanReadableCopyright': 'NEELx - Advanced Biometric Unlock for macOS.'
}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(app / 'Contents/PkgInfo').write_bytes(b'APPL????')

# Find all Swift source files in source/NEELx
swift_files = [str(p) for p in src_dir.rglob('*.swift')]
sdk = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
swiftc = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
module_cache = base / 'ModuleCache'
module_cache.mkdir(parents=True, exist_ok=True)

args = [
    swiftc,
    '-O',
    '-whole-module-optimization',
    '-parse-as-library',
    '-swift-version', '5',
    '-default-isolation', 'MainActor',
    '-enable-upcoming-feature', 'NonisolatedNonsendingByDefault',
    '-sdk', sdk,
    '-target', 'arm64-apple-macos15.0',
    '-module-cache-path', str(module_cache),
    '-module-name', 'NEELx',
    '-o', str(app / 'Contents/MacOS/NEELx')
] + swift_files

print(f"Compiling {len(swift_files)} Swift source files with {swiftc}...")
res = subprocess.run(args, capture_output=True, text=True)
if res.returncode != 0:
    print("Compilation FAILED:")
    print(res.stderr)
    raise SystemExit(res.returncode)

print("Compilation SUCCEEDED!")

# Clean extended attributes and dot files (stage in /tmp to avoid iCloud/Finder xattr race in ~/Documents)
stage_app = Path('/tmp/NEELx_stage.app')
if stage_app.exists():
    shutil.rmtree(stage_app)
subprocess.run(['ditto', '--norsrc', str(app), str(stage_app)], check=True)
subprocess.run(['xattr', '-cr', str(stage_app)], check=False)
subprocess.run(['dot_clean', str(stage_app)], check=False)

# Ad-hoc code signing with local entitlements
ent = base / 'local.entitlements'
sign_cmd = [
    'codesign', '--force', '--sign', '-',
    '--options', 'runtime',
    '--strip-disallowed-xattrs',
    '--entitlements', str(ent),
    str(stage_app)
]
subprocess.run(sign_cmd, check=True)

verify_cmd = ['codesign', '--verify', '--deep', '--strict', '--verbose=2', str(stage_app)]
subprocess.run(verify_cmd, check=True)

# Copy cleanly back to workspace
shutil.rmtree(app)
subprocess.run(['ditto', '--norsrc', str(stage_app), str(app)], check=True)
subprocess.run(['xattr', '-cr', str(app)], check=False)
print(f"Successfully built and signed: {app}")
