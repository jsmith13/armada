#!/bin/bash
set -euo pipefail

version=7.2.6
package="armada-kernel-${version}.tar.zst"
modules="/usr/lib/modules/${version}"

cd /packages/kernel
sha256sum --check "${package}.sha256"
test -d "${modules}"
test "$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d | wc -l)" = 1
rm -rf /usr/lib/modules/7.2.6
tar --extract --zstd --file "${package}" --directory /usr
test -s "${modules}/vmlinuz"
test -s "${modules}/dtb/qcom/qcs8550-ayn-odin2portal-vtdr6130.dtb"
cp "${modules}/dtb/qcom/qcs8550-ayn-odin2portal-vtdr6130.dtb" \
	"${modules}/dtb/qcom/qcs8550-ayn-odin2portal.dtb"
sha256sum --check --quiet payload.sha256
depmod --all "${version}"

mkdir -p /etc/armada /var/roothome
printf '%s\n' 'auto_update_enabled=0' > /etc/armada/abl.conf
printf '%s\n' '20261010.o2p-vtdr120-source1' > /usr/lib/armada/version
printf '%s\n' 'EXPERIMENTAL: Odin 2 Portal VTDR6130; preferred 60 Hz plus optional 120 Hz; no ABL updates.' \
	> /usr/lib/armada/o2p-panel-experiment

dracut --force --no-hostonly --reproducible --kver "${version}" \
	--add ostree --add armada-splash --add armada-ostree-fallback \
	"${modules}/initramfs.img" "${version}"
test -s "${modules}/initramfs.img"
lsinitrd "${modules}/initramfs.img" > /run/o2p-initramfs-files.txt
for required in \
	usr/libexec/armada/armada-splash \
	usr/libexec/armada/armada-splash-launcher \
	usr/libexec/armada/device-env \
	usr/share/armada/splash/splash.asp \
	usr/libexec/armada/armada-ostree-fallback \
	usr/lib/ostree/ostree-prepare-root
do
	awk -v path="${required}" '$NF == path { found=1 } END { exit !found }' \
		/run/o2p-initramfs-files.txt
done
printf '%s\n' 'Matched kernel, modules, panel DTB and initramfs installed; ABL auto-update disabled.'
