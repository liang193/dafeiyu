#!/usr/bin/env python3
"""Install verified official SDK archives into this machine's isolated Linux runtime.

Run as root after downloading files listed in software.json. Does not accept SDK
licenses on a user's behalf, download APK mirrors, clear an AVD, or install apps.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import subprocess
import zipfile


def extract(archive, destination):
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for item in z.infolist():
            target = (destination / item.filename).resolve()
            if not target.is_relative_to(destination.resolve()):
                raise ValueError("Unsafe ZIP path")
            z.extract(item, destination)
            mode = (item.external_attr >> 16) & 0o777
            if mode and not item.is_dir():
                target.chmod(mode)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("downloads", type=Path)
    parser.add_argument("--tools-only", action="store_true")
    args = parser.parse_args()
    sdk = Path("/opt/feiyu/android-sdk")
    manifest = json.loads(Path(__file__).with_name("software.json").read_text())
    selected = [entry for entry in manifest["sdk"] if entry["file"] != "android-commandlinetools.zip"
                and (not args.tools_only or not entry["file"].startswith("android30"))]
    for entry in selected:
        path = args.downloads / entry["file"]
        algorithm = "sha256" if "sha256" in entry else "sha1"
        with path.open("rb") as f:
            actual = hashlib.file_digest(f, algorithm).hexdigest()
        if actual != entry[algorithm]:
            raise ValueError("Archive hash mismatch: " + entry["file"])
        destination = sdk / "system-images/android-30/google_apis" if entry["file"].startswith("android30") else sdk
        marker = sdk / (".installed-" + entry["file"])
        if not marker.exists() or marker.read_text() != actual:
            extract(path, destination)
            marker.write_text(actual)
        print("Verified installation: " + entry["file"], flush=True)
    if args.tools_only:
        return
    user = pwd.getpwnam("feiyu")
    android = Path("/var/lib/feiyu/android")
    avds = android / "avd"
    avd = avds / "FeiYuCommerce.avd"
    avd.mkdir(parents=True, exist_ok=True, mode=0o700)
    config = avd / "config.ini"
    if not config.exists():
        config.write_text("""AvdId=FeiYuCommerce
avd.ini.displayname=FeiYu Commerce Experiment
abi.type=x86_64
hw.cpu.arch=x86_64
hw.cpu.ncore=4
hw.ramSize=3072
hw.gpu.enabled=yes
hw.gpu.mode=software
hw.keyboard=yes
hw.lcd.width=720
hw.lcd.height=1280
hw.lcd.density=320
hw.mainKeys=no
hw.sdCard=no
disk.dataPartition.size=6G
disk.cachePartition=yes
disk.cachePartition.size=256M
image.sysdir.1=system-images/android-30/google_apis/x86_64/
tag.id=google_apis
tag.display=Google APIs
target=android-30
PlayStore.enabled=false
showDeviceFrame=no
fastboot.forceColdBoot=yes
""")
    (avds / "FeiYuCommerce.ini").write_text(f"avd.ini.encoding=UTF-8\npath={avd}\ntarget=android-30\n")
    for path in [android, *android.rglob("*")]:
        os.chown(path, user.pw_uid, user.pw_gid)
        path.chmod(0o700 if path.is_dir() else 0o600)
    subprocess.run(["usermod", "-aG", "kvm", "feiyu"], check=True)
    print("Created/reused FeiYuCommerce AVD; existing app data was preserved.")


if __name__ == "__main__":
    main()
