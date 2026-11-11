#!/bin/bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
	echo 'Run this script as root; see README.md for resource-limited build instructions.' >&2
	exit 1
fi

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "${here}/../.." && pwd)
work="${repo}/_build-o2p-vtdr6130"
kernel_out="${here}/_build/kernel"
out="${repo}/output/odin2portal-vtdr6130"
image=localhost/armada-o2p-vtdr6130:source1
archive=armada-o2p-vtdr6130-source1.oci
package=armada-kernel-7.2.6.tar.zst

for tool in podman runc python3 zstd sha256sum make gcc tar; do
	if ! command -v "${tool}" >/dev/null; then
		printf 'Missing build dependency: %s\n' "${tool}" >&2
		exit 1
	fi
done
runtime=$(command -v runc)
test ! -e "${out}/${archive}"
test ! -e "${out}/${archive}.part"
mkdir -p "${kernel_out}" "${out}/tmp"

# Never reuse a prepared kernel tree after changing the patch series.
env -u FAST WORK_DIR="${work}" OUT_DIR="${kernel_out}" \
	bash "${repo}/packages/kernel/scripts/build-kernel.sh"
(
	cd "${kernel_out}"
	sha256sum --check "${package}.sha256"
)
python3 "${here}/kernel-manifest.py" "${kernel_out}/${package}" \
	> "${kernel_out}/payload.sha256"

podman build --arch arm64 --runtime "${runtime}" --pull=missing \
	--memory=2g --memory-swap=2500m --tag "${image}" "${here}"
podman image inspect "${image}" > "${out}/image-inspection.json"
podman run --rm --arch arm64 --runtime "${runtime}" \
	--memory=1g --memory-swap=1500m --entrypoint /bin/bash \
	--volume "${kernel_out}/payload.sha256:/run/payload.sha256:ro,Z" \
	"${image}" -ceu '
		test "$(cat /usr/lib/armada/version)" = 20261010.o2p-vtdr120-source1
		grep -qx auto_update_enabled=0 /etc/armada/abl.conf
		sha256sum --check --quiet /run/payload.sha256
		sha256sum /usr/lib/modules/7.2.6/initramfs.img
	' > "${out}/verification.txt"
env GOMAXPROCS=2 TMPDIR="${out}/tmp" \
	podman save --format oci-archive --output "${out}/${archive}.part" "${image}"
mv "${out}/${archive}.part" "${out}/${archive}"
(
	cd "${out}"
	sha256sum "${archive}" > "${archive}.sha256"
	cat "${archive}.sha256"
)
printf 'Build complete: %s/%s\nNo device or SD-card writes were performed.\n' "${out}" "${archive}"
