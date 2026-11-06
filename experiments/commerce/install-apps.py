#!/usr/bin/env python3
"""Install the pinned official downloads only in the FeiYuCommerce AVD."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ADB = "/opt/feiyu/android-sdk/platform-tools/adb"
SERIAL = "emulator-5580"


def adb(*arguments, timeout=30):
    return subprocess.check_output([ADB, "-s", SERIAL, *arguments], timeout=timeout, text=True).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("downloads", type=Path)
    args = parser.parse_args()
    if adb("emu", "avd", "name").splitlines()[0] != "FeiYuCommerce" or adb("shell", "getprop", "sys.boot_completed") != "1":
        raise RuntimeError("The FeiYuCommerce AVD is not ready; no APK was installed.")
    items = json.loads(Path(__file__).with_name("software.json").read_text())["apps"]
    for item in items:
        path = args.downloads / item["file"]
        with path.open("rb") as f:
            if hashlib.file_digest(f, "sha256").hexdigest() != item["sha256"]:
                raise ValueError("Unexpected APK bytes: " + item["file"])
        if "Success" not in adb("install", "-r", str(path), timeout=180):
            raise RuntimeError("Android did not report a successful installation.")
        package = item["package"]
        if not adb("shell", "pm", "path", package).startswith("package:"):
            raise RuntimeError("Expected package not found: " + package)
        info = adb("shell", "dumpsys", "package", package)
        print(package, *re.findall(r"(?:versionName|primaryCpuAbi)=\S+", info), flush=True)


if __name__ == "__main__":
    main()
