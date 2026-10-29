#!/usr/bin/env python3
"""Compile Apple resources; never execute the vendored prebuilt helper."""
import plistlib
import subprocess
import sys
from pathlib import Path

app = Path(sys.argv[1]).resolve()
source = Path(__file__).resolve().parents[1] / 'src/CocoaTop'
if not (app / 'Info.plist').is_file():
    raise SystemExit(f'Missing staged Info.plist: {app}')
subprocess.run(['xcrun', 'ibtool', '--errors', '--warnings', '--notices',
                '--minimum-deployment-target', '15.0', '--target-device', 'iphone',
                '--target-device', 'ipad', '--compile', str(app / 'LaunchScreen.storyboardc'),
                str(source / 'res/LaunchScreen.storyboard')], check=True)
partial = app / 'asset-info.plist'
subprocess.run(['xcrun', 'actool', str(source / 'res/Assets.xcassets'),
                '--compile', str(app), '--platform', 'iphoneos',
                '--minimum-deployment-target', '15.0', '--target-device', 'iphone',
                '--target-device', 'ipad', '--app-icon', 'AppIcon',
                '--output-partial-info-plist', str(partial)], check=True)
with (app / 'Info.plist').open('rb') as stream:
    info = plistlib.load(stream)
with partial.open('rb') as stream:
    info.update(plistlib.load(stream))
with (app / 'Info.plist').open('wb') as stream:
    plistlib.dump(info, stream)
partial.unlink()
