#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "${ROOT}" <<'PY'
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
from pathlib import Path
import sys
import tarfile
from unittest.mock import patch

path = Path(sys.argv[1]) / "experiments/odin2portal-vtdr6130/kernel-manifest.py"
spec = importlib.util.spec_from_file_location("kernel_manifest", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
prefix = "lib/modules/7.2.6/"

def run(count, status=0):
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode="w") as archive:
        files = {
            prefix + "vmlinuz": b"matched kernel",
            prefix + "dtb/qcom/qcs8550-ayn-odin2portal.dtb": b"stock",
            prefix + "dtb/qcom/qcs8550-ayn-odin2portal-vtdr6130.dtb": b"variant",
        }
        files.update({prefix + f"kernel/test-{i}.ko": b"module" for i in range(count)})
        for name, payload in files.items():
            member = tarfile.TarInfo(name)
            member.size = len(payload)
            archive.addfile(member, io.BytesIO(payload))
    data.seek(0)
    class Process:
        stdout = data
        def __enter__(self):
            return self
        def __exit__(self, *args):
            self.stdout.close()
        def wait(self):
            return status
    output = io.StringIO()
    with patch.object(module.subprocess, "Popen", return_value=Process()), \
         patch.object(sys, "argv", ["kernel-manifest.py", "kernel.tar.zst"]), \
         redirect_stdout(output):
        module.main()
    return dict((name, digest) for digest, name in
                (line.split("  ", 1) for line in output.getvalue().splitlines()))

manifest = run(1615)
assert manifest["/usr/" + prefix + "vmlinuz"] == hashlib.sha256(b"matched kernel").hexdigest()
assert manifest["/usr/" + prefix + "dtb/qcom/qcs8550-ayn-odin2portal.dtb"] == \
       hashlib.sha256(b"variant").hexdigest()
assert len(manifest) == 1618
for count, status, error in [(1614, 0, ValueError), (1615, 1, RuntimeError)]:
    try:
        run(count, status)
    except error:
        pass
    else:
        raise AssertionError(f"Accepted invalid kernel package: {count=}, {status=}")
print("Odin 2 Portal kernel payload manifest tests passed")
PY
