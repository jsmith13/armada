import hashlib
from pathlib import Path
import subprocess
import sys
import tarfile


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: kernel-manifest.py armada-kernel-7.2.6.tar.zst")
    package = Path(sys.argv[1])
    prefix = "lib/modules/7.2.6/"
    hashes = {}
    with subprocess.Popen(["zstd", "-dc", str(package)], stdout=subprocess.PIPE) as proc:
        with tarfile.open(fileobj=proc.stdout, mode="r|") as archive:
            for member in archive:
                if not member.isfile():
                    continue
                name = member.name.removeprefix("./")
                if not name.startswith(prefix):
                    raise ValueError(f"Unexpected kernel archive path: {name}")
                if not (
                    name.endswith((".ko", ".ko.xz", ".ko.zst", ".ko.gz", ".dtb"))
                    or name == prefix + "vmlinuz"
                ):
                    continue
                with archive.extractfile(member) as payload:
                    hashes[name] = hashlib.file_digest(payload, "sha256").hexdigest()
        if proc.wait() != 0:
            raise RuntimeError("Kernel archive decompression failed")

    dtbs = prefix + "dtb/qcom/"
    hashes[dtbs + "qcs8550-ayn-odin2portal.dtb"] = hashes[
        dtbs + "qcs8550-ayn-odin2portal-vtdr6130.dtb"
    ]
    modules = sum(".ko" in name for name in hashes)
    if modules != 1615:
        raise ValueError(f"Expected 1615 modules for this release, found {modules}")
    if prefix + "vmlinuz" not in hashes:
        raise ValueError("Kernel image missing from archive")
    for name, digest in sorted(hashes.items()):
        print(f"{digest}  /usr/{name}")


if __name__ == "__main__":
    main()
