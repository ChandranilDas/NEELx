import os
import plistlib
import shutil
import subprocess
import time
from pathlib import Path

base = Path(__file__).resolve().parent
src_dir = base / 'source/NEELx'
app = base / 'NEELx.app'

print("=== 1. Terminating any running NEELx / Glance instances ===")
subprocess.run(['pkill', '-9', '-f', 'NEELx'], check=False)
subprocess.run(['pkill', '-9', '-f', 'glance'], check=False)
subprocess.run(['pkill', '-9', '-f', 'Glance'], check=False)
time.sleep(1)

print("=== 2. Cleaning orphaned state and old app support directories ===")
home = Path.home()
app_support = home / 'Library/Application Support'
for folder in ['glance-hardened', 'glance', 'Glance', 'NEELx']:
    p = app_support / folder
    if p.exists():
        print(f"Removing old state directory: {p}")
        shutil.rmtree(p, ignore_errors=True)

# Delete old orphaned Keychain items
subprocess.run(['security', 'delete-generic-password', '-s', 'local.glance.hardened'], capture_output=True)
subprocess.run(['security', 'delete-generic-password', '-s', 'local.neelx'], capture_output=True)

# Delete old defaults
subprocess.run(['defaults', 'delete', 'local.glance.hardened'], capture_output=True)
subprocess.run(['defaults', 'delete', 'local.neelx'], capture_output=True)

# Configure clean default preferences for NEELx
subprocess.run(['defaults', 'write', 'local.neelx', 'NEELxSettings.hasCompletedOnboarding', '-bool', 'false'], check=True)
subprocess.run(['defaults', 'write', 'local.neelx', 'NEELxSettings.matchThreshold', '-float', '0.63'], check=True)
subprocess.run(['defaults', 'write', 'local.neelx', 'NEELxSettings.isFaceUnlockEnabled', '-bool', 'true'], check=True)
subprocess.run(['defaults', 'write', 'local.neelx', 'NEELxSettings.livenessMode', '-string', 'light'], check=True)
subprocess.run(['defaults', 'write', 'local.neelx', 'NEELxSecurity.scanLightEnabled', '-bool', 'true'], check=True)

print("=== 3. Ensuring NEELx.app is freshly built ===")
subprocess.run(['python3', str(base / 'build_neelx.py')], check=True)

print("=== 4. Installing to /Applications/NEELx.app ===")
target_app = Path('/Applications/NEELx.app')
old_apps = [
    Path('/Applications/Glance Hardened.app'),
    Path('/Applications/Glance.app'),
    Path('/Applications/Glance Hardened Previous.app')
]
for old in old_apps:
    if old.exists():
        print(f"Removing legacy app: {old}")
        shutil.rmtree(old, ignore_errors=True)

if target_app.exists():
    shutil.rmtree(target_app, ignore_errors=True)

subprocess.run(['ditto', '--norsrc', str(app), str(target_app)], check=True)
subprocess.run(['xattr', '-cr', str(target_app)], check=False)
subprocess.run(['dot_clean', str(target_app)], check=False)

ent = base / 'local.entitlements'
sign_cmd = [
    'codesign', '--force', '--sign', '-',
    '--options', 'runtime',
    '--strip-disallowed-xattrs',
    '--entitlements', str(ent),
    str(target_app)
]
subprocess.run(sign_cmd, check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target_app)], check=True)
print("Code signature on /Applications/NEELx.app verified.")

print("=== 5. Registering with LaunchServices & Spotlight (Fixes F4/Launchpad/Spotlight) ===")
lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
subprocess.run([lsregister, '-f', '-R', '-trusted', str(target_app)], check=False)
subprocess.run(['mdimport', str(target_app)], check=False)
subprocess.run(['touch', str(target_app)], check=False)

print("=== 6. Launching NEELx ===")
subprocess.run(['open', str(target_app)], check=True)
print("NEELx launched successfully! The onboarding notch is now ready.")
