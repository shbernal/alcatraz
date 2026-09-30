#!/usr/bin/env python3
# alcatraz: macOS in a container
# https://github.com/shbernal/alcatraz
# Hard fork of Docker-OSX by Sick.Codes (https://github.com/sickcodes/Docker-OSX)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints the OpenCore config for build-bootdisk.sh: /data/config.plist if it
# exists, otherwise OSX-KVM's, with the serials from the environment if SERIAL
# is set, the resolution from WIDTH and HEIGHT, the picker off if
# BOOT_PICKER=false, and the hv_vmm_present kernel patch if APPLEID_PATCH=true.
import os, plistlib, re, sys
path = "/data/config.plist"
if not os.path.exists(path):
    path = "/opt/osx-kvm/OpenCore/config.plist"
with open(path, "rb") as f:
    config = plistlib.load(f)
if os.environ.get("SERIAL"):
    generic = config["PlatformInfo"]["Generic"]
    generic["SystemProductName"] = os.environ["DEVICE_MODEL"]
    generic["SystemSerialNumber"] = os.environ["SERIAL"]
    generic["MLB"] = os.environ["BOARD_SERIAL"]
    generic["SystemUUID"] = os.environ["UUID"]
    generic["ROM"] = bytes.fromhex(os.environ["MAC_ADDRESS"].replace(":", ""))
# OSX-KVM leaves the resolution to OVMF, which boots at 1280x800
width, height = os.environ.get("WIDTH") or "1920", os.environ.get("HEIGHT") or "1080"
config["UEFI"]["Output"]["Resolution"] = f"{width}x{height}@32"
if os.environ.get("BOOT_PICKER") == "false":
    config["Misc"]["Boot"]["ShowPicker"] = False
    config["Misc"]["Boot"]["Timeout"] = 0
    # only list APFS and HFS volumes: with every volume, the bootdisk's own EFI
    # partition comes first, fails to boot, and OpenCore shows the picker anyway
    config["Misc"]["Security"]["ScanPolicy"] = 0x1 | 0x100 | 0x200
# swap the kernel's hv_vmm_present sysctl name with hibernatecount's, so macOS
# reads 0 there and Apple services don't see a VM (from
# https://forum.proxmox.com/threads/anyone-can-make-bluetooth-work-on-sonoma.153301/#post-697832)
if os.environ.get("APPLEID_PATCH") == "true":
    patches = config["Kernel"]["Patch"]
    for part, minkernel, find, replace in (
        (1, "20.4.0", b"hibernatehidready\0hibernatecount\0", b"hibernatehidready\0hv_vmm_present\0"),
        (2, "22.0.0", b"boot session UUID\0hv_vmm_present\0", b"boot session UUID\0hibernatecount\0"),
    ):
        if not any(p.get("Find") == find and p.get("Replace") == replace for p in patches):
            patches.append({
                "Arch": "x86_64", "Base": "", "Comment": f"APPLEID_PATCH {part}/2: kern.hv_vmm_present=0",
                "Count": 1, "Enabled": True, "Find": find, "Identifier": "kernel", "Limit": 0, "Mask": b"",
                "MaxKernel": "", "MinKernel": minkernel, "Replace": replace, "ReplaceMask": b"", "Skip": 0,
            })
# the config names a kext that ships as MCEReporterDisabler.kext; without it
# AppleIntelMCEReporter panics on iMacPro1,1 and MacPro models
for kext in config["Kernel"]["Add"]:
    if kext["BundlePath"] == "AppleMCEReporterDisabler.kext" and not os.path.exists("/opt/osx-kvm/OpenCore/EFI/OC/Kexts/AppleMCEReporterDisabler.kext"):
        kext["BundlePath"] = "MCEReporterDisabler.kext"
# keep <data> on one line like the original, plistlib wraps it
out = plistlib.dumps(config, sort_keys=False)
out = re.sub(rb"<data>(.*?)</data>", lambda m: b"<data>" + b"".join(m[1].split()) + b"</data>", out, flags=re.S)
sys.stdout.buffer.write(out)
