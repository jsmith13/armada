# Odin 2 Portal VTDR6130 source-build experiment

Source-only reproduction of the panel configuration tested in
[armada-os/armada#845](https://github.com/armada-os/armada/issues/845).
No custom image download or image registry publication is needed: build the
patched kernel locally, then package it as a matched bootc update on top of the
official, digest-pinned `20261010` image.

## Scope and precautions

- **Only for Odin 2 Portals confirmed to use the VTDR6130 panel.** Android's
  selected primary-panel reference must point to the VTDR6130 node; finding an
  unused candidate node is not sufficient. This is not for Odin 3 or the
  original ICNA3512 Portal panel.
- Start with an existing **SD-installed `20261010` Armada** system. An external
  monitor can provide access when its internal screen is black. Installation
  over other Armada releases has not been validated.
- The experiment provides preferred 60 Hz and optional 120 Hz modes. Boot,
  Gaming Mode, touch, controls, rendering, audio, brightness, suspend/resume and
  refresh-rate switching passed initial testing on one affected device; this
  is not an extended stress test or universal hardware validation.
- This installs a complete modified `20261010` deployment, not just a panel
  module. Kernel, modules, DTB and regenerated initramfs are kept together.
  The stock source DTS and boot-DTB list remain unchanged; this build substitutes
  the experimental DTB into the existing Portal boot slot.
- Back up the SD card and keep an external monitor available for recovery.
  Do not flash ABL or install internally. Do not enable stock OS updates while
  relying on this experimental kernel.

The branch is based on `c3d178c9e5cc7107aaa128b8c1f384a9c6bd8dfa`.
The panel source matches the tested dual-refresh experiment. Locally rebuilt
packages have their own build metadata and checksums; they are not claimed to
be byte-identical to the original test artifacts. The resulting version is
`20261010.o2p-vtdr120-source1`.

## Build on a Linux host

Use a separate Linux build host, not the Portal. Use rootful Podman on the host,
not inside another container. An ARM64 host
avoids emulation. The same recipe supports x86-64 with an ARM64 cross compiler
and working ARM64 QEMU/binfmt registration for container execution. Expect a
long build and a roughly 6.5 GB output archive. At least 100 GB free disk space
and 8 GB RAM are recommended.

Required host tools: Git, Podman, runc, Python 3.11+, GCC and binutils, make,
bc, bison, flex, OpenSSL and libelf development headers, pahole/dwarves, zstd,
xz, cpio, patch, curl, Perl, kmod/depmod, and the usual GNU shell utilities.
On x86-64 also install `gcc-aarch64-linux-gnu` and
`binutils-aarch64-linux-gnu` plus the distribution's ARM64 QEMU/binfmt support.
Dependencies are not installed by the experiment script.

Clone this branch and run from its repository root:

```bash
git clone --branch experiment/odin2portal-vtdr6130 --single-branch \
  https://github.com/jsmith13/armada.git armada-o2p-vtdr6130
cd armada-o2p-vtdr6130
```

On x86-64, verify ARM64 container execution before starting a lengthy build:

```bash
sudo podman run --rm --arch arm64 --runtime runc \
  --entrypoint /usr/bin/uname \
  ghcr.io/armada-os/armada@sha256:f1be3089bb7c917adf41068704ce8dd9a679e3c47cab466b3d2832be1b2f0cde -m
```

It must print `aarch64`; an exec-format error means binfmt is not ready.

This systemd-host example limits the entire build, including image export.
It assumes CPUs 0 and 1 are available:

```bash
sudo systemd-run --scope \
  -p MemoryMax=3G -p MemorySwapMax=512M -p CPUQuota=200% \
  taskset -c 0-1 bash experiments/odin2portal-vtdr6130/build.sh
```

The script uses the repository's existing kernel builder and full patch series,
without `FAST=1`. It verifies the package checksum and all 1,615 module payloads,
kernel and panel DTBs, regenerates initramfs, disables automatic ABL updates in
the image, runs `bootc container lint`, and exports a local OCI archive plus
checksum. Existing unrelated lint warnings in the base image may still appear.
It does not publish an image or touch a block device.

Outputs:

```text
output/odin2portal-vtdr6130/armada-o2p-vtdr6130-source1.oci
output/odin2portal-vtdr6130/armada-o2p-vtdr6130-source1.oci.sha256
output/odin2portal-vtdr6130/verification.txt
```

Build scratch and package files are under ignored `_build*` directories.
The script refuses to overwrite an existing final archive. Preserve that
archive under another name before starting a new build.

## Apply to the existing SD installation

Copy the OCI archive and its `.sha256` file to `~/Downloads` on the Portal.
Do not install only the kernel or copy an unmatched module into the live OS.

In Desktop Mode, open Konsole. First check the installation target:

```bash
findmnt -T /sysroot -o SOURCE,FSTYPE,TARGET
findmnt -T /boot -o SOURCE,FSTYPE,TARGET
findmnt -T /boot/efi -o SOURCE,FSTYPE,TARGET
```

On the tested SD layout these are `/dev/mmcblk0p3[/root]`, `/dev/mmcblk0p2`,
and `/dev/mmcblk0p1`. **Stop if you cannot confirm these are the SD partitions.**

Disable automatic ABL updates on the running installation before staging:

```bash
sudo mkdir -p /etc/armada
sudoedit /etc/armada/abl.conf
```

Set `auto_update_enabled=0`, preserving any other settings, then verify:

```bash
grep -x 'auto_update_enabled=0' /etc/armada/abl.conf
```

Preserve the current deployment and a recovery copy of its SD boot image:

```bash
sudo ostree admin pin booted
mkdir -p ~/o2p-vtdr6130-recovery
sudo install -m 0644 --backup=numbered /boot/efi/KERNEL \
  "$HOME/o2p-vtdr6130-recovery/KERNEL"
sudo sha256sum /boot/efi/KERNEL "$HOME/o2p-vtdr6130-recovery/KERNEL"
```

Ensure both hashes match, and copy this recovery directory off the SD card.
The saved `KERNEL` boots the pinned original deployment, not the experiment.

Verify and stage the locally built update:

```bash
cd ~/Downloads
sha256sum --check armada-o2p-vtdr6130-source1.oci.sha256
sudo bootc switch --download-only --retain --transport oci-archive \
  "$PWD/armada-o2p-vtdr6130-source1.oci"
bootc status
```

Stop on any error. At this point the new deployment is downloaded but not
queued for boot. When ready, save your work and activate it:

```bash
sudo bootc switch --from-downloaded --apply
```

This reboots immediately. Let normal shutdown finish; do not force power off.
Select **AYN Odin 2 Portal -> Linux -> Go** in the existing ROCKNIX interface.
In Desktop Mode, verify `cat /usr/lib/armada/version` prints
`20261010.o2p-vtdr120-source1`. Run `kcmshell6 kcm_kscreen` to choose 60 or
120 Hz. Gaming Mode may automatically select 120 Hz despite 60 Hz being the
panel's preferred mode.

## Recovery

If the experiment boots but is unusable, use the external monitor and run:

```bash
sudo bootc rollback --apply
```

After the experiment's first boot, the rollback should be the original pinned
deployment; check `bootc status` before proceeding. Its `/etc` configuration is
restored along with that deployment.

If the new SD boot image cannot boot, power off normally if possible, remove
the SD card, and use another computer to restore the saved `KERNEL` file to
the SD card's FAT boot partition as `KERNEL`. This is an SD-file recovery
operation, not an ABL/internal flash. Keep the pinned original deployment.
Disable temporary SSH when diagnostics are finished.
