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

# Frozen binaries and the intentionally versioned control layer. The binaries,
# cursor shim and performance helper remain the physically tested v0.7.7 files.
# Launcher/profile hashes change only for an explicit input release and are
# still pinned so later edits cannot slip into a build.
PINNED_RELEASE_FILES = {
    "profiles/bad-ice-cream-3.profile": "7167edd1f8a0104a45dc46456214437f2a767918cc0568f0ade16b22c67b336c",
    "profiles/bejeweled-2.profile": "ee42620b1044734740354076222e424d36524f90ce36236f01a275e874ffd2e0",
    "profiles/dad-n-me.profile": "6509fc72a2e76dd9ecba36c1c18e5813e16b126aca74c515678371d3e5a34bed",
    "profiles/default.profile": "e9d16447f2378246eae18de1021ac4cfe6000510723c2d5bf139130687e6c44c",
    "profiles/final-fantasy-sonic-x5.profile": "a5a997335da132be2e5eed3356443915346d718039536a7bf91346a5225a04d9",
    "profiles/garfield-s-scary-scavenger-hunt.profile": "0b94a6933a993f0fb48189ccc1cc12d0ba699170022545f616866228da4cd478",
    "profiles/garfield.profile": "8aea13d63c558319042d05ee0160f6f624d2707b6e9972caac67c2d4adacf6b6",
    "profiles/henry-stickmin-breaking-the-bank.profile": "16440ec72fd7f58e7bf3d13817b0f97df5f6510be106264cddebd696a69897b9",
    "profiles/minecrafttowerdefense.profile": "110c592c77db1241ee36a8f71910ba0d963f956eeb33c300286d6dbe7ab3606f",
    "profiles/papas-pizzeria.profile": "6f48fb410edd9754b9a69946c004ce5a434373be2f2e5a941be19e88ce8bc6ea",
    "profiles/ssf2.profile": "7ee4e60ee108ce9e071ded561bee0bdd55d2848d137d82f62d9c101538a37272",
    "profiles/super-mario-63.profile": "f00c751e9a8f54fa0bf82daff9f6c042ea36c49ec69c8ef1471be09540ddd179",
    "profiles/template.profile": "1c28e6062d69aeed1edc613a1a02f3559fc89d99ce063859b58dcb42579e2736",
    "profiles/the-fancy-pants-adventure-1.profile": "8ef7ed0b5a2e319e191c1a26d5150ed6b4d674615f42f340ba55c2e460b7b758",
    "profiles/the-world-hardest-game.profile": "324b1187fca71632393e3b2c2a60416c954aba6e0035ee39102b421c9bb13d21",
    "profiles/ultimate-flash-sonic.profile": "6eb072b45539a5b01cae2f78709228482b026358b99d2f18cfb05245a3f3003a",
    "profiles/we-dancing-online.profile": "7d396251061c248d652d14218dddde5922207f2d1dc789252262b3c3c12281cb",
    "runtime/core/launch.sh": "69aab715b9b193f03e389de1ce04c63c610dc758c9b1b8870dfd3de740de7dd8",
    "runtime/core/lib/control_profiles.sh": "0af5f928b0d1cab708ee370f486ce858421b60bf493192ba915ecc27532c88eb",
    "runtime/core/lib/performance.sh": "baa845c798ad834dc89c9c9c285b09479f0ae8e9cbbb2d67bb1d8db440861eba",
    "runtime/core/native_multifile/Ruffle-Native-Multifile-Launch.sh": "10892cb6783bd1d6bd91248847db2b5f746c86bb412d2b5c723897d85a2832fa",
    "runtime/core/native_multifile/ruffle-native-multifile.aarch64": "dfbdcbf83883f268eb9a1210a72c5997391ec82b508ce0c3d7f4373ea3005ab5",
    "runtime/core/native_v020/Ruffle-Native-Launch.sh": "3a1e34fc181c13e4d362dbb80d57d9f1b295480bb085b113aae95ba5a66017e5",
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


def verify_lf(files: list[tuple[Path, Path]]) -> None:
    text_suffixes = {".sh", ".profile", ".py", ".json", ".xml", ".txt", ".html"}
    bad = [str(arc) for src, arc in files if src.suffix.lower() in text_suffixes and b"\r\n" in src.read_bytes()]
    if bad:
        raise SystemExit("CRLF found in release file(s): " + ", ".join(bad))


def write_member(zf: ZipFile, source: Path, archive: Path) -> None:
    executable = source.suffix == ".sh" or source.name.endswith(".aarch64")
    mode = 0o755 if executable else 0o644
    info = ZipInfo(str(archive).replace("\\", "/"), date_time=(2026, 8, 27, 0, 0, 0))
    info.create_system = 3
    info.external_attr = (S_IFREG | mode) << 16
    info.compress_type = ZIP_DEFLATED
    zf.writestr(info, source.read_bytes())


def main() -> None:
    verify_known_good()
    files = iter_release_files()
    verify_lf(files)
    RELEASES.mkdir(exist_ok=True)
    with ZipFile(OUT, "w") as zf:
        for source, archive in files:
            write_member(zf, source, archive)
    print(OUT)


if __name__ == "__main__":
    main()
