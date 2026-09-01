from __future__ import annotations

from hashlib import sha256
from pathlib import Path
from stat import S_IFREG
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo
import json


ROOT = Path(__file__).resolve().parents[1]
PORT = ROOT / "port" / "rufflehandheld"
META = json.loads((PORT / "port.json").read_text(encoding="utf-8"))
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
RELEASES = ROOT / "releases"
OUT = RELEASES / f"Ruffle-Handheld-v{VERSION}-OFFLINE.zip"
SOURCE_OUT = RELEASES / f"Ruffle-Handheld-v{VERSION}-SOURCE.zip"

# Stable and adaptive binaries plus the intentionally versioned control layer.
# The original binaries, cursor shim and performance helper remain byte-for-byte
# identical to the physically tested release. Every new selector/profile file
# is also pinned so later edits cannot slip into a build unnoticed.
PINNED_RELEASE_FILES = {
    "profiles/bad-ice-cream-3.profile": "7167edd1f8a0104a45dc46456214437f2a767918cc0568f0ade16b22c67b336c",
    "profiles/bejeweled-2.profile": "7163780b66b477dba19144043ce223592c21e57f53d918e42b9b34900ba176f9",
    "profiles/dad-n-me.profile": "6509fc72a2e76dd9ecba36c1c18e5813e16b126aca74c515678371d3e5a34bed",
    "profiles/default.profile": "e789fefdbbdb6d622a97d577f5692f3d71a04ae6140a411d7b5e2904123090bc",
    "profiles/final-fantasy-sonic-x5.profile": "f4c3f367ed3a6067394a76b5a6bed987ef3d926a1bd9edcb28e4c6e379e69859",
    "profiles/garfield-s-scary-scavenger-hunt.profile": "0b94a6933a993f0fb48189ccc1cc12d0ba699170022545f616866228da4cd478",
    "profiles/garfield.profile": "8aea13d63c558319042d05ee0160f6f624d2707b6e9972caac67c2d4adacf6b6",
    "profiles/henry-stickmin-breaking-the-bank.profile": "0093042806d0519f406db1b0530c26aa58f23e1ffe7234657e9886a1893fd17a",
    "profiles/mcdonald-s-videogame.profile": "cdd8219dd647563691a52e2092613e6c1998d1c3ae24e3a8fcaa160ab0c6df18",
    "profiles/minecrafttowerdefense.profile": "6a734486a033aa354143a538e181a9202ce54451a939453fdcfb3ccea4b60761",
    "profiles/papas-pizzeria.profile": "bc2e9853fc5657ea04a1be99212ff65eccd69badaacc2bc72ba377d67e3028a9",
    "profiles/ssf2.profile": "7ee4e60ee108ce9e071ded561bee0bdd55d2848d137d82f62d9c101538a37272",
    "profiles/super-mario-63.profile": "f00c751e9a8f54fa0bf82daff9f6c042ea36c49ec69c8ef1471be09540ddd179",
    "profiles/template.profile": "81f5df63899ad871e381b2e60a0437bf94a2e8d4e89919ac4a9d555c9cc770d6",
    "profiles/the-fancy-pants-adventure-1.profile": "8ef7ed0b5a2e319e191c1a26d5150ed6b4d674615f42f340ba55c2e460b7b758",
    "profiles/the-world-hardest-game.profile": "324b1187fca71632393e3b2c2a60416c954aba6e0035ee39102b421c9bb13d21",
    "profiles/ultimate-flash-sonic.profile": "6eb072b45539a5b01cae2f78709228482b026358b99d2f18cfb05245a3f3003a",
    "profiles/we-dancing-online.profile": "7d396251061c248d652d14218dddde5922207f2d1dc789252262b3c3c12281cb",
    "runtime/core/launch.sh": "652fb65ccf16f9a8f64139961fd2b39a9dc7f4aeda5a0fd8760694a391a34c0a",
    "runtime/core/lib/control_profiles.sh": "0af5f928b0d1cab708ee370f486ce858421b60bf493192ba915ecc27532c88eb",
    "runtime/core/lib/engine.sh": "a9d3e2b97e25a1cbab910ddda2221b13045de9fc633e3842d9a0ad7699374d93",
    "runtime/core/lib/performance.sh": "baa845c798ad834dc89c9c9c285b09479f0ae8e9cbbb2d67bb1d8db440861eba",
    "runtime/core/native_adaptive/ruffle-native-adaptive.aarch64": "582ebadd49c29de51adfefbf330a506409bb6a5bc1cf85314842cb149c848bb1",
    "runtime/core/native_multifile/Ruffle-Native-Multifile-Launch.sh": "9398b840eab6693fc79a3bbd3cb19b837e327271a9ac7e16baa397617d017098",
    "runtime/core/native_multifile/ruffle-native-multifile.aarch64": "dfbdcbf83883f268eb9a1210a72c5997391ec82b508ce0c3d7f4373ea3005ab5",
    "runtime/core/native_v020/Ruffle-Native-Launch.sh": "afb908ac00bbf4bf5403cb2ba6d52b8d697ca9069c8ec6b75b78920bc0dbad25",
    "runtime/core/native_v020/libruffle_cursorfix.aarch64.so": "269a60726e78f5a90405c987d296efe762793cd9a5b1a91917f5b3b10860edeb",
    "runtime/core/native_v020/ruffle-native.aarch64": "aa080b95afc09825dfa455094bc54c5a5171a6b3090ab7c2fae898cb0905e320",
    "theme/background_icon.png": "d2368e9aa17eadb1795a2e028ac7e67d863122c7011e7a0f48e4592af07974c5",
    "theme/system.png": "edf149542cb5f99441c8227d73bb64c1ada06a3acef42b856878912f4ee72d19",
}


def digest(path: Path) -> str:
    return sha256(path.read_bytes()).hexdigest()


def verify_known_good() -> None:
    payload = PORT / "rufflehandheld"
    errors: list[str] = []
    for relative, expected in PINNED_RELEASE_FILES.items():
        path = payload / relative
        if not path.is_file():
            errors.append(f"missing known-good file: {relative}")
        elif digest(path) != expected:
            errors.append(f"pinned runtime/control file changed: {relative}")
    if errors:
        raise SystemExit("\n".join(errors))


def iter_release_files() -> list[tuple[Path, Path]]:
    # Standard PortMaster package: one universal launch script and one port
    # directory. The same script works from ports or ports_scripts and resolves
    # the application independently of its own location.
    launcher = PORT / "Ruffle Handheld.sh"
    application = PORT / "rufflehandheld"
    if not launcher.is_file():
        raise SystemExit(f"Missing release launcher: {launcher.relative_to(ROOT)}")
    if not application.is_dir():
        raise SystemExit(f"Missing release application: {application.relative_to(ROOT)}")

    files: list[tuple[Path, Path]] = [(launcher, Path("Ruffle Handheld.sh"))]
    for path in sorted(application.rglob("*")):
        if not path.is_file():
            continue
        if path.name in {".setup-complete", "setup-info.txt", "setup.log"}:
            continue
        if "logs" in path.parts:
            continue
        files.append((path, Path("rufflehandheld") / path.relative_to(application)))
    return files


def iter_source_files() -> list[tuple[Path, Path]]:
    prefix = Path(f"Ruffle-Handheld-v{VERSION}-SOURCE")
    files: list[tuple[Path, Path]] = []
    excluded_parts = {".git", "releases", "__pycache__", ".pytest_cache"}
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT)
        if any(part in excluded_parts for part in relative.parts):
            continue
        if path.suffix.lower() in {".pyc", ".pyo"}:
            continue
        files.append((path, prefix / relative))
    return files


def verify_lf(files: list[tuple[Path, Path]]) -> None:
    text_suffixes = {".sh", ".profile", ".py", ".json", ".xml", ".txt", ".html", ".md", ".cfg"}
    text_names = {"VERSION", ".gitattributes"}
    bad = [
        str(arc)
        for src, arc in files
        if (src.suffix.lower() in text_suffixes or src.name in text_names) and b"\r\n" in src.read_bytes()
    ]
    if bad:
        raise SystemExit("CRLF found in release file(s): " + ", ".join(bad))


def write_member(zf: ZipFile, source: Path, archive: Path) -> None:
    executable = source.suffix == ".sh" or source.name.endswith(".aarch64")
    mode = 0o755 if executable else 0o644
    info = ZipInfo(str(archive).replace("\\", "/"), date_time=(2026, 8, 31, 0, 0, 0))
    info.create_system = 3
    info.external_attr = (S_IFREG | mode) << 16
    info.compress_type = ZIP_DEFLATED
    zf.writestr(info, source.read_bytes())


def main() -> None:
    verify_known_good()
    files = iter_release_files()
    verify_lf(files)
    source_files = iter_source_files()
    verify_lf(source_files)
    RELEASES.mkdir(exist_ok=True)
    with ZipFile(OUT, "w") as zf:
        for source, archive in files:
            write_member(zf, source, archive)
    with ZipFile(SOURCE_OUT, "w") as zf:
        for source, archive in source_files:
            write_member(zf, source, archive)
    print(OUT)
    print(SOURCE_OUT)


if __name__ == "__main__":
    main()
