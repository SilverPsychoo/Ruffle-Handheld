# Ruffle Handheld

[English](README.md)

Juega archivos Flash en consolas Linux ARM64. Ruffle Handheld añade una sección Flash al menú, admite juegos SWF con archivos adicionales y funciona sin conexión. No incluye juegos.

**Versión actual:** 0.8.33. La configuración más probada es EmuELEC en equipos RK3326. El soporte para otros sistemas todavía se está comprobando con reportes de la comunidad; consulta [Compatibilidad](#compatibilidad).

## Instalación

Descarga `Ruffle-Handheld-v0.8.33-OFFLINE.zip` y descomprímelo. Contiene `Ruffle Handheld.sh` y la carpeta `rufflehandheld`.

| Sistema | Dónde copiar los archivos |
| --- | --- |
| EmuELEC | `Ruffle Handheld.sh` → `ROMS/ports_scripts/`; `rufflehandheld/` → `ROMS/ports/` |
| ArkOS, dArkOS y otros sistemas con PortMaster | Copia ambos elementos en la ubicación habitual de Ports; conserva el nombre `rufflehandheld` de la carpeta. |
| NextUI | Copia ambos elementos en la carpeta de juegos Ports (normalmente `Roms/2) Ports (PORTS)/`). Instala antes `PORTS.pak`. |

Ejecuta **Ruffle Handheld** una vez desde el menú Ports. El instalador crea la carpeta de juegos Flash y agrega la sección al menú. No descarga nada. Si Flash no aparece de inmediato, vuelve al menú o reinicia la consola.

Para actualizar, copia los archivos nuevos encima de los anteriores y ejecuta **Ruffle Handheld** otra vez. Tus juegos y perfiles en `profiles/custom/` permanecen en su lugar.

## Agregar juegos

Copia los archivos `.swf` a la carpeta `flash` de la tarjeta de ROMs:

```text
ROMS/flash/Fancy Pants.swf
```

Si un juego trae archivos adicionales, guárdalos en `flash_data` con el mismo nombre base que el SWF:

```text
ROMS/flash/Garfield.swf
ROMS/flash_data/Garfield.files/
```

Los archivos adicionales van dentro de `Garfield.files/`. Deja esa carpeta fuera de `flash/` para que el menú muestre solo el juego. Se aceptan extensiones `.swf` y `.SWF`; la compatibilidad varía porque Ruffle aún no admite todas las funciones de Flash.

## Controles

La configuración predeterminada está pensada para juegos que combinan teclado y ratón:

| Botón | Acción predeterminada |
| --- | --- |
| Cruceta | Flechas |
| A | Espacio |
| B | Z |
| X | X |
| Y | C |
| R1 | Clic del ratón |
| Stick derecho | Cursor, si la consola lo tiene |
| Start / Select | Enter / Escape |

Algunos juegos cuentan con perfiles de controles incluidos. En juegos que solo usan ratón, como Bejeweled 2, A sirve para hacer clic. Ruffle Handheld lee el mapeo del mando proporcionado por el sistema, por lo que no debería hacer falta un perfil distinto para cada juego solo para activar el clic de R1. Start+Select está previsto para salir cuando PortMaster lo permite, pero falta confirmarlo en algunos sistemas, incluido dArkOSRE.

Para cambiar los controles de un juego, abre `ports/rufflehandheld/profile-maker.html` en el navegador de tu celular o computadora. Escribe el nombre del SWF, asigna los botones, descarga el archivo `.profile` y cópialo a `ports/rufflehandheld/profiles/custom/`. Funciona sin Internet. Los perfiles personalizados tienen prioridad y se conservan al actualizar.

## Compatibilidad

| Sistema | Estado actual |
| --- | --- |
| EmuELEC | Probado en equipo RK3326 ARM64. |
| ArkOS / dArkOS | Incluye instalación y controles; los reportes de inicio, clic y salida necesitan más pruebas en consola. |
| ROCKNIX | Se ha confirmado que llega al reproductor en Flip; faltan pruebas de controles y juegos concretos. |
| NextUI / TrimUI Brick | El instalador y el reproductor se han ejecutado en la consola. El movimiento del cursor y los juegos que ocupan solo un cuarto de pantalla siguen en investigación. |
| AmberELEC / Knulli / otros sistemas Linux ARM64 | Incluye adaptadores de instalación; el resultado depende de la consola y el firmware. |

Un juego puede fallar por una función de Flash no compatible o por falta de memoria aunque la instalación y los controles funcionen. Ruffle Handheld incluye un reproductor ARM64; no incluye Adobe Flash Player.

## Logs y reportes de errores

Si falla la instalación, revisa `ports/rufflehandheld/logs/LAST-INSTALL.log`. Al abrir un juego se crea otro archivo en la misma carpeta con un nombre basado en el SWF, por ejemplo `Fancy_Pants.swf.log`. Cada intento reemplaza el log anterior de ese juego.

Para reportar un fallo, indica el sistema, modelo de consola, versión de Ruffle Handheld, nombre del juego, qué ocurrió y adjunta el log correspondiente. Una foto o un video corto ayuda cuando el problema es de imagen o controles.

## Licencias

Ruffle Handheld no incluye juegos Flash. Agrega archivos SWF que tengas derecho a utilizar. Los avisos de licencia del software incluido están en `rufflehandheld/licenses/`; la licencia del proyecto está en `LICENSE`.
