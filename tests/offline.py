#!/usr/bin/env python3
# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Checks that need no VM: the OpenCore config opencore-config.py prints, and
# the QEMU command line launch.sh builds. Runs inside the image:
#
#       docker run --rm -v ./tests:/tests:ro --entrypoint python3 alcatraz /tests/offline.py
import os, plistlib, subprocess, sys, tempfile

UPSTREAM = "/opt/osx-kvm/OpenCore/config.plist"
CUSTOM = "/data/config.plist"
failures = []


def check(name, condition):
    print(("ok   " if condition else "FAIL ") + name)
    if not condition:
        failures.append(name)


def config(**env):
    out = subprocess.run(["/opt/alcatraz/opencore-config.py"], env={**os.environ, **env},
                         check=True, capture_output=True).stdout
    return plistlib.loads(out)


def qemu_args(**env):
    """launch.sh's QEMU arguments, with a stand-in qemu-system-x86_64 that prints them."""
    with tempfile.TemporaryDirectory() as bin:
        with open(f"{bin}/qemu-system-x86_64", "w") as f:
            f.write('#!/bin/sh\nprintf "%s\\0" "$@"\n')
        os.chmod(f"{bin}/qemu-system-x86_64", 0o755)
        env = {**os.environ, "BOOTDISK": "/bootdisk.qcow2", **env, "PATH": f"{bin}:{os.environ['PATH']}"}
        out = subprocess.run(["/opt/alcatraz/launch.sh"], env=env, check=True,
                             capture_output=True).stdout
    return out.decode().split("\0")[:-1]


def arg(args, flag, prefix=""):
    """Values of every `flag` argument that start with prefix."""
    return [v for f, v in zip(args, args[1:]) if f == flag and v.startswith(prefix)]


with open(UPSTREAM, "rb") as f:
    upstream = plistlib.load(f)

# opencore-config.py
stock = config()
check("stock config keeps OSX-KVM's serial",
      stock["PlatformInfo"]["Generic"]["SystemSerialNumber"] == upstream["PlatformInfo"]["Generic"]["SystemSerialNumber"])
check("stock config keeps the picker", stock["Misc"]["Boot"]["ShowPicker"] == upstream["Misc"]["Boot"]["ShowPicker"])
kexts = "/opt/osx-kvm/OpenCore/EFI/OC/Kexts"
check("the MCE reporter kext in the config exists in the EFI",
      all(os.path.exists(f"{kexts}/{k['BundlePath']}") for k in stock["Kernel"]["Add"] if "MCE" in k["BundlePath"]))

serials = config(DEVICE_MODEL="iMacPro1,1", SERIAL="C02TW0WAHX87", BOARD_SERIAL="C027251024NJG36UE",
                 UUID="5CCB366D-9118-4C61-A00A-E5BAF3BED451", MAC_ADDRESS="A8:5C:2C:9A:46:2F",
                 WIDTH="1280", HEIGHT="720")
generic = serials["PlatformInfo"]["Generic"]
check("serials go into PlatformInfo", (generic["SystemProductName"], generic["SystemSerialNumber"], generic["MLB"],
      generic["SystemUUID"]) == ("iMacPro1,1", "C02TW0WAHX87", "C027251024NJG36UE", "5CCB366D-9118-4C61-A00A-E5BAF3BED451"))
check("MAC_ADDRESS becomes the ROM", generic["ROM"] == bytes.fromhex("A85C2C9A462F"))
check("WIDTH and HEIGHT set the resolution", serials["UEFI"]["Output"]["Resolution"] == "1280x720@32")

nopicker = config(BOOT_PICKER="false")
check("BOOT_PICKER=false hides the picker",
      (nopicker["Misc"]["Boot"]["ShowPicker"], nopicker["Misc"]["Boot"]["Timeout"]) == (False, 0))
check("BOOT_PICKER=false only scans APFS and HFS", nopicker["Misc"]["Security"]["ScanPolicy"] == 0x301)

def hv_vmm_patches(config):
    return [p for p in config["Kernel"]["Patch"] if b"hv_vmm_present" in p["Find"] + p["Replace"]]

check("no hv_vmm_present patch by default", not hv_vmm_patches(stock))
patched = config(APPLEID_PATCH="true")
check("APPLEID_PATCH=true adds both hv_vmm_present patches", len(hv_vmm_patches(patched)) == 2)

custom = dict(upstream, alcatraz_test=True)
with open(CUSTOM, "wb") as f:
    plistlib.dump(custom, f)
try:
    check("/data/config.plist replaces OSX-KVM's", config().get("alcatraz_test") is True)
    with open(CUSTOM, "wb") as f:
        plistlib.dump(patched, f)
    check("APPLEID_PATCH=true doesn't repeat patches already in /data/config.plist",
          len(hv_vmm_patches(config(APPLEID_PATCH="true"))) == 2)
finally:
    os.remove(CUSTOM)

# launch.sh
args = qemu_args()
check("the installer is attached by default", arg(args, "-drive", "id=InstallMedia,"))
check("BOOT_PICKER=false leaves the installer out", not arg(qemu_args(BOOT_PICKER="false"), "-drive", "id=InstallMedia,"))
check("the bootdisk is BOOTDISK, read-only", arg(args, "-drive", "id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file=/bootdisk.qcow2"))
check("RAM is in GB", arg(args, "-m") == ["4G"])
check("CPUS and CORES make -smp", arg(qemu_args(CPUS="8", CORES="2"), "-smp") == ["8,cores=2"])
check("QEMU_ARGS is split on spaces", qemu_args(QEMU_ARGS="-display none")[-2:] == ["-display", "none"])

base = "user,id=net0,hostfwd=tcp::10022-:22,hostfwd=tcp::5900-:5900"
for ports, forwards in {
    "": "",
    "23": ",hostfwd=tcp::23-:23",
    "10023:80": ",hostfwd=tcp::10023-:80",
    "53/udp": ",hostfwd=udp::53-:53",
    "10023:80,10043:443,5353:53/udp": ",hostfwd=tcp::10023-:80,hostfwd=tcp::10043-:443,hostfwd=udp::5353-:53",
}.items():
    check(f"PORTS={ports!r}", arg(qemu_args(PORTS=ports), "-netdev") == [base + forwards])

if failures:
    sys.exit(f"{len(failures)} check(s) failed")
