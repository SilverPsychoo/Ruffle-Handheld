from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import json

ROOT = Path(__file__).resolve().parents[1]
PORT = ROOT / "port" / "rufflehandheld"
META = json.loads((PORT / "port.json").read_text(encoding="utf-8"))
RELEASES = ROOT / "releases"
RELEASES.mkdir(exist_ok=True)
OUT = RELEASES / META["name"]

required = [PORT / item.rstrip("/") for item in META["items"]]
missing = [str(p.relative_to(ROOT)) for p in required if not p.exists()]
if missing:
    raise SystemExit("Missing release item(s): " + ", ".join(missing))

with ZipFile(OUT, "w", ZIP_DEFLATED) as z:
    for item in required:
        if item.is_file():
            z.write(item, item.name)
        else:
            for path in sorted(item.rglob("*")):
                if path.is_file() and path.name not in {".setup-complete", "setup-info.txt"} and "logs" not in path.parts:
                    z.write(path, str(Path(item.name) / path.relative_to(item)))
print(OUT)
