# Frequently asked questions

## Basics

### Is this legal?

The [macOS software license](https://www.apple.com/legal/sla/) allows running (some versions of) macOS in a virtual machine only on Apple hardware. The [Apple Security Bounty terms and conditions](https://security.apple.com/terms-and-conditions/) make an exception to that (and essentially anything in the macOS software license) under some specific circumstances.

Therefore, yes, there is a legal use for alcatraz. If your use doesn't fall under the license or the security bounty terms, then you are/will be violating the macOS software license. **Note that this is not provided as legal advice, and you should consult with your own counsel for legal guidance.**

Sick.Codes wrote a [deeper dive into the subject](https://sick.codes/is-hackintosh-osx-kvm-or-docker-osx-legal/) for Docker-OSX, and it applies here too.

### What does alcatraz do?

It runs a macOS virtual machine under [Docker](https://en.wikipedia.org/wiki/Docker_(software)). The [Dockerfile](Dockerfile) builds an Arch Linux image with QEMU, OVMF firmware, a pinned copy of [OSX-KVM](https://github.com/kholia/OSX-KVM) and a second OpenCore bootdisk with the picker turned off. When a container starts, [entrypoint.sh](rootfs/opt/alcatraz/entrypoint.sh):

1. downloads the macOS recovery image and creates an empty disk in `/data`, if they're missing
2. builds a bootdisk with your serial numbers or `config.plist`, if there are any
3. starts QEMU through [launch.sh](rootfs/opt/alcatraz/launch.sh)

### Why Docker?

Docker packages the whole setup into one command. It isn't the only way to run a macOS VM, and for a long-lived one it may not be the best. You may prefer to study the [Dockerfile](Dockerfile) and [OSX-KVM](https://github.com/kholia/OSX-KVM) and set up a VM under [Proxmox](https://en.wikipedia.org/wiki/Proxmox_Virtual_Environment) or [libvirt](https://en.wikipedia.org/wiki/Libvirt).

## Can I...

### ...run BlueBubbles/AirMessage/Beeper on it?

Yes. Generate your own [serial numbers](README.md#serial-numbers) and keep them across containers; don't use the default ones. Apple may still block or disable your account. See also the [legal considerations](#is-this-legal).

### ...develop iPhone apps on it?

Yes. Xcode's UI will be slow. Building from the command line (for example React Native) is less painful. Apple may still block your account or remove you from the Apple Developer Program. See also the [legal considerations](#is-this-legal).

### ...connect my iPhone or other USB device to it?

Yes, on a Linux host. See [USB devices](#usb-devices). On Windows it may or may not work.

### ...run CI/CD processes with it?

Maybe, but there are several reasons not to:
1. There are [legal considerations](#is-this-legal).
2. Hosted CI runners rarely offer nested virtualization, so there's no KVM for alcatraz to use.
3. Your own macOS runners, on real or virtual Mac hardware, are almost always the better fit for macOS CI.

You can install runners on the macOS VM itself (which does not get around the legal considerations above), but [Docker may not be the best approach](#why-docker).

### ...run on Linux but with Wayland?

Yes, through Xwayland, which most compositors run for X11 clients. The usual `-v /tmp/.X11-unix:/tmp/.X11-unix -e "DISPLAY=${DISPLAY:-:0.0}"` flags work. You can also skip the window and [use VNC](#headless-and-vnc).

### ...run on Windows?

Yes, on Windows 11 (build 22000 or later) with WSL2. Windows 10 doesn't work, even with WSL2.

1. Install WSL from an administrator PowerShell with `wsl --install`. Check that it's version 2 with `wsl -l -v`.
2. Turn on nested virtualization in `C:\Users\<you>\.wslconfig`:
   ```
   [wsl2]
   nestedVirtualization=true
   ```
3. In the WSL distribution, check for KVM with `kvm-ok` (from the `cpu-checker` package). It should print `KVM acceleration can be used`.
4. Install [Docker Desktop](https://docs.docker.com/desktop/windows/install/), and in its settings turn on "Use the WSL 2 based engine" and the integration with your WSL distribution.
5. For the QEMU window, point the container at WSLg's X server by replacing the X11 mount with `-v /mnt/wslg/.X11-unix:/tmp/.X11-unix`. If the window doesn't show, try `-e DISPLAY=:0`. WSLg may not pass every key through ([microsoft/wslg#376](https://github.com/microsoft/wslg/issues/376)). [VNC](#headless-and-vnc) is the fallback.

### ...run on macOS?

If you have a Mac with Apple Silicon you are better served by [UTM](https://apps.apple.com/us/app/utm-virtual-machines/id1538878817?mt=12).

On an Intel Mac, Docker ([Docker Desktop](https://www.docker.com/products/docker-desktop/) or [colima](https://github.com/abiosoft/colima)) runs inside a Linux VM, which complicates things, and you are likely to hit the [common errors](#common-errors) below. Run QEMU directly with HVF acceleration instead, for example with [libvirt](https://libvirt.org/macos.html).

### ...run on cloud services?

Probably not. Cloud providers run their services inside virtual machines, and those rarely allow nested virtualization, so there's no KVM. CI runners such as GitHub Actions, Azure DevOps Pipelines, CircleCI and GitLab CI/CD are the typical case (but see [running CI/CD](#run-cicd-processes-with-it)). Some providers sell machines that allow virtualization, such as [Amazon's EC2 bare metal instances](https://aws.amazon.com/about-aws/whats-new/2018/05/announcing-general-availability-of-amazon-ec2-bare-metal-instances/), usually at a premium.

## Common errors

### Docker errors

If you get an error like `docker: command not found` then you don't have Docker installed. Use [Docker Desktop](https://www.docker.com/products/docker-desktop/) on Windows or your distribution's package manager on Linux.

If you get `docker: Got permission denied while trying to connect to the Docker daemon` or `docker: unknown server OS: .`, your user most likely isn't in the `docker` group. Add it with `sudo usermod -aG docker "$USER"`, then log out and back in.

If you get `Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?`, then `dockerd` isn't running. On most Linux distributions `sudo systemctl enable --now docker` starts it.

### GTK initialization failed

QEMU can't open its window on your X server: either it can't reach it at all, or it isn't allowed to. Check that `DISPLAY` is set on the host (`echo $DISPLAY`) and that the command has both `-v /tmp/.X11-unix:/tmp/.X11-unix` and `-e "DISPLAY=${DISPLAY:-:0.0}"`. If it's a permission problem, `xhost +local:` on the host lets local containers connect. The package is `xorg-xhost` on Arch, `x11-xserver-utils` on Debian and Ubuntu, `xorg-x11-server-utils` on Fedora.

Or skip the window and [use VNC](#headless-and-vnc).

### KVM error

If you get an error like `error gathering device information while adding custom device "/dev/kvm": no such file or directory`, KVM isn't available on the Linux kernel Docker runs on. You may be somewhere without nested virtualization (see [cloud services](#run-on-cloud-services)), virtualization may be off in the BIOS, the CPU may be too old, or the `kvm_intel`/`kvm_amd` module isn't loaded. `grep -cE '(svm|vmx)' /proc/cpuinfo` prints 0 when the CPU doesn't expose virtualization. Fixing KVM is beyond this document, but you can [start here](https://www.linux-kvm.org/page/FAQ).

### ALSA error

You may see a wall of errors like this:

```
(qemu) ALSA lib confmisc.c:767:(parse_card) cannot find card '0'
ALSA lib conf.c:4745:(_snd_config_evaluate) function snd_func_card_driver returned error: No such file or directory
...
alsa: Could not initialize DAC
audio: Failed to create voice `dac'
```

QEMU uses ALSA for audio by default and found no sound card. If macOS boots, you can ignore them. Pass `--device /dev/snd` for sound through ALSA, [use PulseAudio](#audio-with-pulseaudio), or turn audio off with `-e AUDIO_DRIVER=none`.

### Cannot allocate memory

`cannot set up guest memory 'pc.ram': Cannot allocate memory` means `RAM` asks for more than the host can give. Lower it. If `free -h` shows most memory in `buff/cache`, `sudo tee /proc/sys/vm/drop_caches <<< 3` frees it.

### No disk to install on

The installer lists no disk until you erase it in Disk Utility. See [Installing](README.md#installing).

### Slow installation

This isn't specific to virtual hardware. The macOS installer's time estimates are random, and it often looks frozen when it isn't. Be patient. It can take hours.

### Installer after completing install

You booted from the installer instead of the disk you installed macOS on. Reboot and pick the right disk, or [skip the picker](README.md#skipping-the-picker).

## Running it

### Headless and VNC

Drop the X11 flags and have QEMU serve VNC instead:

```bash
docker run -i \
    --device /dev/kvm \
    -p 50922:10022 \
    -p 5999:5999 \
    -e QEMU_ARGS="-display none -vnc 0.0.0.0:99,password=on" \
    ghcr.io/shbernal/alcatraz:latest
```

Use `-i`, not `-it`, so you can type into the QEMU monitor. Press Enter until you see `(qemu)`, type `change vnc password`, and set a password. Then connect a VNC client to `localhost:5999`. To stop the container, `docker kill` it.

VNC isn't encrypted. On a remote host, don't publish port 5999; tunnel it instead with `ssh -N <user>@<host> -L 5999:127.0.0.1:5999`.

[SPICE](https://www.spice-space.org/spice-user-manual.html) works the same way: `-p 3001:3001 -e QEMU_ARGS="-display none -spice disable-ticketing=on,port=3001"`, then `remote-viewer spice://localhost:3001`. `disable-ticketing` means no password, so keep the port local.

### Audio with PulseAudio

On a host running PulseAudio or PipeWire's PulseAudio server, mount its socket and point QEMU at it:

```bash
    -e AUDIO_DRIVER=pa,server=unix:/tmp/pulseaudio.socket \
    -v "/run/user/$(id -u)/pulse/native:/tmp/pulseaudio.socket" \
```

Under WSLg, the socket is `/mnt/wslg/runtime-dir/pulse/native`. macOS has no driver for QEMU's HDA codec, so expect the controller to show up without working output.

### USB devices

QEMU runs as the container's `alcatraz` user. The simplest route that needs no extra privileges is USB redirection over the network. On the host, find the device's `vendor:product` ID with `lsusb` and serve it (from the `usbredir` package):

```bash
sudo usbredirserver -p 7700 1e3d:2096
```

Then attach it when the container starts:

```bash
    -e QEMU_ARGS="-chardev socket,id=usbredirchardev1,port=7700,host=172.17.0.1 -device usb-redir,chardev=usbredirchardev1,id=usbredirdev1" \
```

or at any time from the QEMU monitor (press Enter in the container's terminal for the `(qemu)` prompt):

```
chardev-add socket,id=usbredirchardev1,port=7700,host=172.17.0.1
device_add usb-redir,chardev=usbredirchardev1,id=usbredirdev1
```

`172.17.0.1` is the host on Docker's default bridge. `ip addr show docker0` confirms it.

Direct passthrough with `-device usb-host,hostbus=1,hostport=2` (numbers from `lsusb -t`) also works, but the container needs the device node (`--device /dev/bus/usb/001/005`) and QEMU needs write access to it. The host loses the device while the VM runs. `system_profiler SPUSBDataType` in macOS lists what arrived.

For an iPhone, [usbfluxd](https://github.com/corellium/usbfluxd) shares the host's `usbmuxd` over the network, which works on any machine. On the host, with `usbmuxd`, `avahi`, `socat` and `usbfluxd` installed and the phone plugged in:

```bash
sudo systemctl start usbmuxd
sudo avahi-daemon &
sudo socat tcp-listen:5000,fork unix-connect:/var/run/usbmuxd &
sudo usbfluxd -f -n
```

In macOS, build usbfluxd with Homebrew's tools and connect to the host:

```bash
brew install make automake autoconf libtool pkg-config gcc libimobiledevice usbmuxd
git clone https://github.com/corellium/usbfluxd.git && cd usbfluxd
./autogen.sh && make && sudo make install

sudo launchctl start usbmuxd
sudo /usr/local/sbin/usbfluxd -f -r 172.17.0.1:5000
```

Reopen Xcode and the phone shows up. On a desktop with a spare USB controller, VFIO passthrough is the other option: see [Silfalion/Iphone_docker_osx_passthrough](https://github.com/Silfalion/Iphone_docker_osx_passthrough).

### Shared folders

`sshfs` over the guest's SSH port needs nothing in the container. With Remote Login on in macOS:

```bash
mkdir -p ~/mnt/osx
sshfs <macos-user>@localhost: -p 50922 ~/mnt/osx
```

To share a host folder into macOS, mount it into the container and hand it to QEMU as a 9p share:

```bash
    -v "${HOME}/somefolder:/mnt/hostshare" \
    -e QEMU_ARGS="-virtfs local,path=/mnt/hostshare,mount_tag=hostshare,security_model=passthrough,id=hostshare" \
```

Then, in macOS, `sudo -S mount_9p hostshare`.

### Extra disks

Mount the disk image into the container and attach it to a free SATA port:

```bash
    -v "${PWD}/second.img:/disktwo" \
    -e QEMU_ARGS="-device ide-hd,bus=sata.5,drive=DISK-TWO -drive id=DISK-TWO,if=none,file=/disktwo,format=qcow2" \
```

### Extract the virtual disk

If you mounted `/data`, the disk is already on the host as `disk.img`. Otherwise, with the container stopped, copy the whole data directory out:

```bash
docker cp <container-id>:/data ./mac
```

Then run it with `-v ./mac:/data`, as in [Keep your disk](README.md#keep-your-disk).

To read it on Linux, connect it as a block device and mount the APFS partition with [apfs-fuse](https://github.com/sgan81/apfs-fuse), read-only:

```bash
sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 ./mac/disk.img
sudo fdisk -l /dev/nbd0
mkdir -p ./part
sudo apfs-fuse -o allow_other /dev/nbd0p2 ./part

# when done
sudo umount ./part
sudo qemu-nbd --disconnect /dev/nbd0
```

### Shrink a disk image

1. In macOS, delete what you don't need, run `sudo trimforce enable` and reboot.
2. Zero the free space with `dd if=/dev/zero of=./empty; rm -f ./empty`, then shut down.
3. [Extract the disk](#extract-the-virtual-disk) and rewrite it: `qemu-img convert -O qcow2 disk.img smaller.img`. Add `-c` to compress it further, at some cost in speed.
4. `qemu-img check smaller.img` before you rely on it.

### Disk space

Every container keeps its disk under `/var/lib/docker`. If that fills up, [mount `/data` from the host](README.md#keep-your-disk) somewhere with room, or move Docker's data directory with the `data-root` setting in `/etc/docker/daemon.json`.

### RAM and CPUs

`RAM`, `CPUS` and `CORES` are environment variables, so they apply every time a container starts. `-e RAM=half` gives the guest half of the host's memory. `CPUS` is the total and `CORES` the cores per socket, so `-e CPUS=8 -e CORES=2` gives four sockets of two cores. Unlike memory, CPU time is shared, so you can give the guest all your cores.

### Slow UI

macOS expects a GPU, and QEMU's virtual display has no acceleration. [osx-optimizer](https://github.com/sickcodes/osx-optimizer) lists macOS settings that help, such as turning off Spotlight indexing and transparency.

## Fixing Apple ID login

### The problem

When running macOS in a virtual machine, you may encounter problems logging into Apple services including:
- Apple ID
- iMessage
- iCloud
- App Store

This happens because Apple's services can detect that macOS is running in a virtual environment and block access. The solution is to apply a kernel patch that hides the VM presence from Apple's detection mechanism.

NOTE as per forum post: Unfortunately, this would very possibly break qemu-guest-agent, which is necessary for the host getting VM status or taking hot snapshot while the VM is running. This is because qemu-guest-agent also checks the hv_vmm_present flag, but only works if it is true (=1).

Use at your own risk.

### The fix: a kernel patch

This guide provides three methods to apply the necessary kernel patch. All methods implement the same fix originally described in [this forum post](https://forum.proxmox.com/threads/anyone-can-make-bluetooth-work-on-sonoma.153301/#post-697832).

#### Before you start

alcatraz attaches the OpenCore bootdisk with `snapshot=on`, so changes made to it from inside macOS are gone after the next shutdown. Patch a copy of the `config.plist` on the host instead and save it as `config.plist` in the `/data` directory; the container then builds its bootdisk from it at every start, with your [serial numbers](README.md#serial-numbers) filled in. To start from the stock config:

```bash
docker run --rm --entrypoint cat ghcr.io/shbernal/alcatraz:latest /opt/osx-kvm/OpenCore/config.plist > ./mac/config.plist
```

Whichever method you use:
- Make sure you can access your EFI partition
- Locate your OpenCore `config.plist` file (typically in the `EFI/OC` folder)
- Back up your current `config.plist` before making changes

### Method 1: the patch script

This is the fastest and easiest way to apply the patch.

1. Mount your EFI partition using Clover Configurator or another EFI mounting tool
2. Download the patch script:
   ```bash
   curl -o apply-appleid-kernelpatch.py https://raw.githubusercontent.com/shbernal/alcatraz/main/tools/apply-appleid-kernelpatch.py
   ```
3. Run the script with your `config.plist` file path:
   ```bash
   python3 apply-appleid-kernelpatch.py /path/to/config.plist
   ```

You can drag and drop the `config.plist` file into your terminal after typing `python3 apply-appleid-kernelpatch.py` for an easy path insertion.

**Note**: If you encounter a "permission denied" error, run the command with `sudo`:
```bash
sudo python3 apply-appleid-kernelpatch.py /path/to/config.plist
```

### Method 2: OCAT (OpenCore Auxiliary Tools)

If you prefer a graphical approach:

1. Open OCAT and load your `config.plist`
2. Navigate to the **Kernel** section
3. Go to the **Patch** subsection
4. Add two new patch entries with the following details:

#### Patch 1
| Setting | Value |
|---------|-------|
| **Identifier** | `kernel` |
| **Base** | *(leave empty)* |
| **Count** | `1` |
| **Find (Hex)** | `68696265726E61746568696472656164790068696265726E617465636F756E7400` |
| **Limit** | `0` |
| **Mask** | *(leave empty)* |
| **Replace (Hex)** | `68696265726E61746568696472656164790068765F766D6D5F70726573656E7400` |
| **Skip** | `0` |
| **Arch** | `x86_64` |
| **MinKernel** | `20.4.0` |
| **MaxKernel** | *(leave empty)* |
| **Enabled** | `True` |
| **Comment** | `Sonoma VM BT Enabler - PART 1 of 2 - Patch kern.hv_vmm_present=0` |

#### Patch 2
| Setting | Value |
|---------|-------|
| **Identifier** | `kernel` |
| **Base** | *(leave empty)* |
| **Count** | `1` |
| **Find (Hex)** | `626F6F742073657373696F6E20555549440068765F766D6D5F70726573656E7400` |
| **Limit** | `0` |
| **Mask** | *(leave empty)* |
| **Replace (Hex)** | `626F6F742073657373696F6E20555549440068696265726E617465636F756E7400` |
| **Skip** | `0` |
| **Arch** | `x86_64` |
| **MinKernel** | `22.0.0` |
| **MaxKernel** | *(leave empty)* |
| **Enabled** | `True` |
| **Comment** | `Sonoma VM BT Enabler - PART 2 of 2 - Patch kern.hv_vmm_present=0` |

5. Save the configuration
6. Reboot your VM

### Method 3: edit `config.plist` by hand

For users who prefer to manually edit the configuration file:

1. Mount your EFI partition
2. Locate and open your `config.plist` file in a text editor
3. Find the `<key>Kernel</key>` → `<dict>` → `<key>Patch</key>` → `<array>` section
4. Add these two `<dict>` entries within the `<array>`:

```xml
<dict>
    <key>Arch</key>
    <string>x86_64</string>
    <key>Base</key>
    <string></string>
    <key>Comment</key>
    <string>Sonoma VM BT Enabler - PART 1 of 2 - Patch kern.hv_vmm_present=0</string>
    <key>Count</key>
    <integer>1</integer>
    <key>Enabled</key>
    <true/>
    <key>Find</key>
    <data>aGliZXJuYXRlaGlkcmVhZHkAaGliZXJuYXRlY291bnQA</data>
    <key>Identifier</key>
    <string>kernel</string>
    <key>Limit</key>
    <integer>0</integer>
    <key>Mask</key>
    <data></data>
    <key>MaxKernel</key>
    <string></string>
    <key>MinKernel</key>
    <string>20.4.0</string>
    <key>Replace</key>
    <data>aGliZXJuYXRlaGlkcmVhZHkAaHZfdm1tX3ByZXNlbnQA</data>
    <key>ReplaceMask</key>
    <data></data>
    <key>Skip</key>
    <integer>0</integer>
</dict>
<dict>
    <key>Arch</key>
    <string>x86_64</string>
    <key>Base</key>
    <string></string>
    <key>Comment</key>
    <string>Sonoma VM BT Enabler - PART 2 of 2 - Patch kern.hv_vmm_present=0</string>
    <key>Count</key>
    <integer>1</integer>
    <key>Enabled</key>
    <true/>
    <key>Find</key>
    <data>Ym9vdCBzZXNzaW9uIFVVSUQAaHZfdm1tX3ByZXNlbnQA</data>
    <key>Identifier</key>
    <string>kernel</string>
    <key>Limit</key>
    <integer>0</integer>
    <key>Mask</key>
    <data></data>
    <key>MaxKernel</key>
    <string></string>
    <key>MinKernel</key>
    <string>22.0.0</string>
    <key>Replace</key>
    <data>Ym9vdCBzZXNzaW9uIFVVSUQAaGliZXJuYXRlY291bnQA</data>
    <key>ReplaceMask</key>
    <data></data>
    <key>Skip</key>
    <integer>0</integer>
</dict>
```

5. Save the file
6. Reboot your VM

### Notes

- The `MinKernel` values (`20.4.0` and `22.0.0`) may need adjustment depending on your specific macOS version (Monterey, Ventura, Sonoma, etc.)
- If you encounter issues, consult the [OpenCore documentation](https://dortania.github.io/docs/) for appropriate values for your setup
- Always back up your configuration before making changes
- After applying the patch and rebooting, try signing into Apple services again

### What the patch does

The patch makes macOS believe it runs on physical hardware by redirecting the `hv_vmm_present` kernel variable, which normally indicates VM presence. After applying the patch, Apple services should function normally within your virtual environment.
