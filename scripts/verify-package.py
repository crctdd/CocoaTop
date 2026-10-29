#!/usr/bin/env python3
"""Read-only deb audit. Does not run maintainer scripts or install packages."""
import io
import plistlib
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

package, scheme = Path(sys.argv[1]).resolve(), sys.argv[2]
expected_arch = 'iphoneos-arm64e' if scheme == 'roothide' else 'iphoneos-arm64'
expected_slices = {'arm64e'} if scheme == 'roothide' else {'arm64', 'arm64e'}
control = subprocess.check_output(['dpkg-deb', '-f', str(package)], text=True)
print(control)
fields = dict(line.split(': ', 1) for line in control.splitlines() if ': ' in line)
assert fields['Package'] == 'com.crctdd.cocoatop'
assert fields['Name'] == 'CocoaTop'
assert fields['Version'] == '3.0.0'
assert fields['Architecture'] == expected_arch
assert fields['Author'] == fields['Maintainer'] == 'crctdd'
assert 'firmware (>= 15.0)' in fields['Depends']
assert set(fields['Conflicts'].split(', ')) == {'cn.zqbb.ccatop', 'cn.llld.cocoatop', 'ru.domo.cocoatop64', 'cn.zqbb.ccatop.whitelist'}
raw = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(package)])
with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
    members = {m.name.removeprefix('./'): m for m in archive.getmembers()}
    roots = [name[:-len('Info.plist')] for name in members if name.endswith('Applications/CocoaTop.app/Info.plist')]
    assert len(roots) == 1, roots
    root = roots[0]
    if scheme == 'rootless':
        assert root == 'var/jb/Applications/CocoaTop.app/', root
    else:
        assert root == 'Applications/CocoaTop.app/', root
    info = plistlib.loads(archive.extractfile(members[root + 'Info.plist']).read())
    assert info['CFBundleIdentifier'] == 'com.crctdd.cocoatop'
    assert info['MinimumOSVersion'] == '15.0'
    assert root + 'zh-Hans.lproj/Localizable.strings' in members
    assert root + 'Assets.car' in members
    assert any(n.startswith(root + 'LaunchScreen.storyboardc/') for n in members)
    with tempfile.TemporaryDirectory(prefix='.verify-', dir=package.parent) as tmp:
        for name, mode in [('CocoaTop', 0o755), ('CocoaTop-helper', 0o4755)]:
            member = members[root + name]
            assert member.isfile() and member.mode == mode, (name, oct(member.mode))
            assert member.uid == member.gid == 0, (name, member.uid, member.gid)
            binary = Path(tmp) / name
            binary.write_bytes(archive.extractfile(member).read())
            slices = set(subprocess.check_output(['xcrun', 'lipo', '-archs', str(binary)], text=True).split())
            assert slices == expected_slices, (name, slices)
            entitlements = subprocess.check_output(['ldid', '-e', str(binary)])
            assert plistlib.loads(entitlements)['platform-application'] is True
            print(f'{name}: uid=0 gid=0 mode={mode:o} archs={sorted(slices)} signed')
print(f'PASS {scheme}: metadata, layout, resources, ownership, modes, architecture, entitlements')
