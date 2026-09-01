# Adaptive ARM64 engine

Ruffle Handheld v0.8.26 keeps the previously tested ARM64 executable as the
stable fallback. The adaptive executable is built from ruffle4consoles commit
`a12f2a9` plus `patches/ruffle4consoles-v0.8.26.patch`. The bundled ARM64
binary is dynamically linked to SDL2 and requires no newer than GLIBC 2.30.

The patch is deliberately narrow:

- external website requests are logged and ignored instead of panicking;
- Linux uses the current SDL display/drawable size instead of fixed 1280x720;
- Linux requests desktop fullscreen;
- `RUFFLE_HANDHELD_WIDTH` and `RUFFLE_HANDHELD_HEIGHT` can override detection;
- `RUFFLE_HANDHELD_FORCE_SCALE=showall` forces aspect-preserving fit.

The included GitHub Actions recipe is manual-only. It does not create or push
branches and exists only to make the bundled executable reproducible after the
source archive is uploaded by the project owner.

The adaptive executable is selected automatically only for known affected
hardware or profiles. `RUFFLE_HANDHELD_ENGINE=stable` always selects the frozen
fallback, while `RUFFLE_HANDHELD_ENGINE=adaptive` opts in explicitly.
