# Ruffle Handheld

[Read in English](README.md)

Ruffle Handheld integra juegos Flash en consolas Linux ARM64 sin Internet. La versión 0.8.21 conserva byte por byte los binarios ARM64, cursor shim y optimización funcionales de v0.7.7. Añade seis perfiles comunitarios y un editor visual de controles totalmente disponible en español e inglés.

> **Estado:** community preview. Hardware probado: **RK3326 / aarch64**. CFW probado: **EmuELEC**. ArkOS, ROCKNIX, AmberELEC, muOS y Knulli se detectan para elegir un adaptador conservador, pero aún no se anuncian como soporte verificado.

## Instalación offline

Como un port estándar de PortMaster, el ZIP contiene exactamente un launcher y una carpeta:

```text
Ruffle Handheld.sh
rufflehandheld/
```

En **EmuELEC**, coloca el mismo launcher en `ROMS/ports_scripts/Ruffle Handheld.sh` y la carpeta en `ROMS/ports/rufflehandheld/`. En ArkOS y otros CFW, instala esos mismos dos elementos mediante PortMaster o en la ubicación Ports normal de ese sistema. No existe una edición distinta del `.sh` para cada CFW.

Al ejecutarlo, el único launcher detecta la raíz de ROMS y valida la aplicación en `ports/rufflehandheld/` mediante archivos centinela. No asume que la carpeta está junto al `.sh`, por lo que funciona cuando EmuELEC lo inicia desde `ports_scripts/`.

No descarga nada. Native, Native Multifile, cursor shim, perfiles, scripts y assets del theme ya están en el ZIP.

## Organización final

Una instalación limpia queda así:

```text
ROMS/
├── flash/                         Solo juegos .swf
├── flash_data/                    Assets multifile
├── ports_scripts/
│   └── Ruffle Handheld.sh
└── ports/
    └── rufflehandheld/
        ├── runtime/               Core y adaptadores
        ├── profiles/
        │   └── custom/            Remapeos del usuario, protegidos de updates
        ├── profile-maker.html     Creador visual offline
        ├── logs/                  Un archivo por juego ejecutado
        ├── theme/                 Chef y logo Adobe Flash
        ├── licenses/
        ├── setup.sh
        └── core-install.sh
```

No se crean `flash_runtime/`, `flash_profiles/` ni `ports/ruffle_r36s/` en la raíz de ROMS. EmuELEC ejecuta directamente el adaptador instalado en `ports/rufflehandheld/runtime/`. Para conservar intacto el core v0.7.7, el entrypoint genera durante cada juego una vista compatible en `/tmp` y la elimina al terminar.

## Juegos

Un SWF normal va directamente en `flash/`:

```text
flash/Fancy Pants.swf
flash/dadnme.swf
```

Para multifile, el nombre base debe coincidir:

```text
flash/Garfield.swf
flash_data/Garfield.files/
```

EmulationStation escanea solamente `flash/` y solamente `.swf .SWF`; `flash_data/` queda fuera del sistema y sus carpetas no aparecen como juegos adicionales.

Al actualizar, una carpeta antigua `flash/Garfield.files/` se mueve a `flash_data/Garfield.files/`. Si el destino ya existe, los datos se combinan y el original se conserva dentro de `rufflehandheld/migrated/` antes de retirarlo del listado visible.

## Perfiles de controles

Todos los perfiles viven en:

```text
ports/rufflehandheld/profiles/
```

Se incluyen perfiles para Fancy Pants, Dad 'n Me, Papa's Pizzeria, Henry Stickmin, Super Mario 63, Bad Ice-Cream 3, Garfield, The World's Hardest Game, Bejeweled 2, We Dancing Online, Ultimate Flash Sonic, Final Fantasy Sonic X5, Minecraft Tower Defense y Super Smash Flash 2. Los juegos únicamente de ratón usan A como clic mediante `gptokeyb2`; los juegos híbridos reservan R1 para el cursor.

Los nuevos perfiles usan estos controles principales:

| Juego | Controles portátiles |
| --- | --- |
| Bejeweled 2 | Stick derecho = cursor; A = clic |
| We Dancing Online | Cruceta = flechas; B = Espacio; X = X; Y = C; Start = Enter; Select = Escape; L1 = Shift; R1 = clic |
| Ultimate Flash Sonic | Cruceta = flechas; A = salto/Spin Dash; Start = pausa; R1 = clic de menú |
| Final Fantasy Sonic X5 | Stick derecho = cursor; A = seleccionar |
| Minecraft Tower Defense | Stick derecho = cursor; A = excavar, construir y seleccionar |
| Super Smash Flash 2 | Cruceta = WASD; A = ataque; B = especial; X = agarrar; Y = escudo; Start = iniciar; Select = pausa; L1 = burla; R1 = clic de menú |

### Remapeo visual

El source también incluye `tools/profile-maker.html`, un editor de controles bilingüe y completamente offline para crear o modificar archivos `.profile` desde cualquier navegador de PC o celular. El Release conserva el mismo editor en `ports/rufflehandheld/profile-maker.html`, así que el usuario no necesita Python ni ningún servicio en línea para remapear controles.

No es necesario aprender códigos de teclado ni editar `config.ron`:

1. Abre `ports/rufflehandheld/profile-maker.html` en cualquier navegador de PC o celular. Funciona sin Internet y permite cambiar toda la interfaz entre Español y English.
2. Escribe el nombre exacto del `.swf` y selecciona la acción de cada botón.
3. Descarga el `.profile` y cópialo a `ports/rufflehandheld/profiles/custom/`.
4. Abre el juego normalmente; no es necesario reinstalar.

El editor también puede cargar un `.profile` existente para modificarlo. Un perfil dentro de `profiles/custom/` tiene prioridad sobre los perfiles incluidos y el instalador nunca borra esa carpeta. El botón elegido como clic no envía al mismo tiempo una tecla, evitando dobles acciones.

Una actualización migra automáticamente `flash_profiles/*.profile` al nuevo directorio. Un perfil antiguo modificado por el usuario tiene prioridad y el perfil incluido que reemplaza se respalda en `rufflehandheld/migrated/`.

## CFW y frontend

| CFW detectado | Registro Flash | Recarga automática | Estado |
| --- | --- | --- | --- |
| EmuELEC | Config principal y `es_systems_flash.cfg` en `.config` y `.emulationstation` | `emustation.service`, con comprobación | Verificado |
| ArkOS | Solo un `es_systems.cfg` existente y escribible | Manual | No verificado |
| ROCKNIX / AmberELEC | Solo config existente en `/storage` | Manual | No verificado |
| Knulli / Batocera | Overlay `es_systems_rufflehandheld.cfg` | Manual | No verificado |
| muOS | Se detecta, pero no se finge que usa EmulationStation | No disponible | Adaptador pendiente |
| Otro Linux ARM64 | Descubrimiento de una config existente y escribible | Manual | No verificado |

Cuando existe PortMaster, `control.txt` sigue siendo la fuente autoritativa. Sin PortMaster se usa el adaptador offline incluido. Un CFW sin adaptador seguro recibe un error claro; el instalador no escribe a ciegas ni declara éxito falso.

En EmuELEC, la entrada registrada es equivalente a (los adaptadores ArkOS/Knulli usan el token `%ROM%` de sus frontends):

```xml
<system>
  <name>flash</name>
  <fullname>Adobe Flash Player</fullname>
  <path>RUTA_DETECTADA/flash</path>
  <extension>.swf .SWF</extension>
  <command>/bin/bash RUTA_DETECTADA/ports/rufflehandheld/runtime/es-launch.sh "%ROM_RAW%"</command>
  <platform>flash</platform>
  <theme>flash</theme>
</system>
```

En EmuELEC se sincronizan tanto las dos configuraciones principales como sus dos archivos auxiliares `es_systems_flash.cfg`, porque el frontend puede priorizar estos últimos. Al repetir la instalación se reemplaza únicamente la entrada Flash: no se duplican sistemas ni se tocan los demás.

## Theme de EmulationStation

Los assets incluidos son:

- `theme/system.png`: logo completo de Adobe Flash Player.
- `theme/background_icon.png`: fondo transparente con el chef.

Si el theme activo ya contiene `flash/theme.xml`, se conserva íntegramente. Si falta y existe un layout `arcade/theme.xml` escribible, se crea solo `flash/` y se copian el layout, el logo y el chef. No se sobrescribe ningún archivo Flash existente. Si el theme no puede ampliarse con seguridad, se usa `arcade` como fallback.

## Runtime conocido funcional

El build verifica SHA-256 y se detiene si cambia accidentalmente cualquier pieza congelada de v0.7.7:

- Native ARM64 y Native Multifile ARM64;
- cursor shim y `LD_PRELOAD`;
- optimización;
- logo y chef.

Los binarios no se actualizaron. Los launchers, perfiles y su resolver están versionados intencionalmente en v0.8.21; los perfiles incluidos no contienen `native_a_mode`, las configuraciones antiguas se convierten de forma compatible y `profiles/custom/` mantiene prioridad. Sus hashes quedan fijados por el build.

## Logs

Cada juego genera únicamente su propio archivo:

```text
ports/rufflehandheld/logs/Fancy_Pants.swf.log
ports/rufflehandheld/logs/Garfield.swf.log
```

El archivo se sobrescribe cuando vuelves a abrir el mismo juego, por lo que no crece una colección de logs por intento. Incluye la ruta recibida, perfil, backend, salida Native o Multifile, memoria y cualquier diagnóstico de salida 137. Los logs auxiliares de las versiones anteriores se eliminan automáticamente durante la actualización.

## Compatibilidad y contribuciones

`Compatibility.xlsx` es la tabla mantenida por el proyecto. `.github/ISSUE_TEMPLATE/` incluye formularios para:

- Game compatibility report
- Control profile submission
- Runtime bug report

## Build del Release

El usuario normal no necesita Python. Para mantenedores y GitHub Actions:

```bash
python3 tools/build_release.py
```

El resultado es `releases/Ruffle-Handheld-vX.X.X-OFFLINE.zip` y contiene únicamente `Ruffle Handheld.sh` y `rufflehandheld/`, siguiendo el formato estándar de un port.

## Límite de las pruebas automáticas

Las pruebas en un host no ARM verifican instalación limpia, actualización, XML, duplicados, espacios, permisos, LF, hashes, perfiles, theme y el flujo Simple/Multifile hasta el punto de ejecutar el binario. El binario ARM64 no se presenta como ejecutado en x86_64: renderizado, audio, cursor, controles físicos y la recarga real deben verificarse en la consola EmuELEC/RK3326.

## Legal

Ruffle Handheld no incluye juegos Flash ni el ejecutable de Adobe Flash Player. El usuario aporta SWF obtenidos legalmente. Las licencias del runtime y de la integración están en `rufflehandheld/licenses/` y en `LICENSE`.
