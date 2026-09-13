#!/usr/bin/env python3
import plistlib
from pathlib import Path
import sys
import zipfile

ipa = Path(sys.argv[1])
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, "Corrupt ZIP"
    prefix = "Payload/Speedtest.app/"
    info = plistlib.loads(archive.read(prefix + "Info.plist"))
    assert info["CFBundleIdentifier"] == "de.robinjuhas.speedtest"
    assert float(info["MinimumOSVersion"]) >= 17
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
    executable = archive.read(prefix + info["CFBundleExecutable"])
    assert len(executable) > 10_000, "Missing executable"
    assert executable[:4] in [b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"], "Not a Mach-O binary"
    assert prefix + "Assets.car" in archive.namelist(), "Missing compiled assets"
    assert prefix + "PrivacyInfo.xcprivacy" in archive.namelist(), "Missing privacy manifest"
    print(f"Verified: {ipa.name}, version {info['CFBundleShortVersionString']} ({info['CFBundleVersion']}), iPhoneOS, {len(executable):,} executable bytes")
