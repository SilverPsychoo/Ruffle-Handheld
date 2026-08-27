# Ruffle Handheld

[English](README.md)

Ruffle Handheld es un launcher offline para juegos Flash en consolas portátiles Linux ARM64. Incluye un runtime derivado de Ruffle adaptado a consola, integra los juegos Flash en EmulationStation, permite perfiles de control por juego y soporta tanto juegos de un solo SWF como juegos multifile.

**No se incluyen juegos Flash ni archivos de Adobe Flash Player.**

## Soporte actual

- Arquitectura: **aarch64 / ARM64**.
- Primera prueba en hardware real: portátil RK3326 + EmuELEC.
- Los objetivos de prueba comunitarios incluyen ArkOS, ROCKNIX, muOS, Knulli, AmberELEC y otros entornos Linux para consolas portátiles.
- Cuando PortMaster está disponible se aprovechan sus helpers, pero el release funciona completamente offline e incluye su runtime.
- El proyecto no está ligado a un modelo específico de consola.

## Instalación

### Instalación manual / sin Internet

Descarga el ZIP offline más reciente desde **Releases**. Contiene únicamente:

```text
Ruffle Handheld.sh
rufflehandheld/
```

Copia ambas cosas dentro de la carpeta **Ports** de la consola y después ejecuta **Ruffle Handheld** una sola vez desde el menú Ports.

La primera ejecución:

1. Detecta la raíz de ROMs cuando es posible.
2. Crea las carpetas para los juegos Flash.
3. Registra un sistema **Flash Games** en EmulationStation.
4. Usa el tema actual de EmulationStation sin sobrescribirlo.
5. Mantiene todo el runtime dentro de la propia carpeta del port.

Si Flash Games no aparece inmediatamente, reinicia EmulationStation.

**No se necesita Internet.** El runtime ARM64 y los archivos necesarios del proyecto ya vienen dentro del release.

### PortMaster

El repositorio usa una estructura de port al estilo de PortMaster para poder probarlo en distintos entornos y preparar una futura publicación oficial. Mientras no exista una entrada oficial en su catálogo, utiliza el release manual/offline.

## Estructura después de instalar

El jugador solamente necesita preocuparse por las carpetas de juegos creadas en la raíz de ROMs:

```text
ROMs/
├── flash/
└── flash_data/
```

El runtime instalado permanece dentro de Ports:

```text
Ports/
├── Ruffle Handheld.sh
└── rufflehandheld/
    ├── bin/
    ├── runtime/
    ├── profiles/
    ├── assets/
    ├── licenses/
    └── logs/
```

El usuario no tiene que crear ni mover carpetas internas del runtime manualmente.

## Agregar juegos

### Juegos de un solo archivo

Coloca el `.swf` directamente en `flash/`:

```text
ROMs/
└── flash/
    └── Fancy Pants.swf
```

EmulationStation mostrará el SWF como un juego Flash.

### Juegos multifile

Algunos juegos Flash necesitan archivos XML, otros SWF, imágenes, sonidos u otros recursos además del archivo principal.

El SWF principal permanece en `flash/` y sus archivos adicionales van en `flash_data/<nombre del juego>.files/`:

```text
ROMs/
├── flash/
│   └── Garfield.swf
└── flash_data/
    └── Garfield.files/
        ├── data.xml
        ├── images/
        ├── sounds/
        └── otros archivos del juego
```

El nombre base debe coincidir:

```text
Garfield.swf
Garfield.files/
```

Mantener la carpeta adicional dentro de `flash_data/` evita que EmulationStation muestre las carpetas de recursos como si fueran juegos independientes.

Por compatibilidad con instalaciones anteriores, el launcher también puede detectar una carpeta `<juego>.files` colocada junto al SWF.

No subas SWFs ni recursos de juegos con copyright a este repositorio.

## Perfiles de controles

Los perfiles ya vienen instalados con Ruffle Handheld y en la consola se encuentran aquí:

```text
Ports/rufflehandheld/profiles/
```

Dentro del repositorio esos mismos archivos están en:

```text
port/rufflehandheld/rufflehandheld/profiles/
```

Existe una sola copia fuente de cada perfil.

Cuando inicia un juego, Ruffle Handheld normaliza el nombre del SWF, busca un `.profile` correspondiente, revisa sus aliases y usa `default.profile` si todavía no existe un perfil dedicado.

Actualmente se incluyen perfiles para juegos como Fancy Pants, Dad 'n Me, Papa's Pizzeria, Henry Stickmin, Super Mario 63, Bad Ice-Cream 3, Garfield y The World's Hardest Game.

### Crear un perfil

Copia:

```text
port/rufflehandheld/rufflehandheld/profiles/template.profile
```

Renombra la copia usando un nombre normalizado, por ejemplo:

```text
alien-hominid.profile
```

Los perfiles usan entradas simples `clave=valor`:

```text
name=Alien Hominid
aliases=alien-hominid|alienhominid
mouse_click=r1
native_a_mode=keyboard

dpad_up=38
dpad_down=40
dpad_left=37
dpad_right=39
south=32
east=90
west=88
north=67
start=13
select=27
left_trigger=16
right_trigger=none
```

Los valores de teclado usan códigos de tecla virtuales de Flash/Windows. Usa `none` para desactivar una asignación.

Mapeo físico usado por el frontend incluido:

| Control físico | Campo del profile |
| --- | --- |
| D-pad | `dpad_up`, `dpad_down`, `dpad_left`, `dpad_right` |
| A | `south` |
| B | `east` |
| X | `west` |
| Y | `north` |
| Start | `start` |
| Select/Back | `select` |
| L1 | `left_trigger` |
| Ruta extra/interna | `right_trigger` |

`mouse_click` indica qué botón de la consola se usa como clic izquierdo adicional cuando `gptokeyb2` o un helper compatible está disponible. El valor normal del proyecto es `r1`.

`native_a_mode` controla cómo se maneja la A física en el frontend congelado:

- `keyboard` — A se usa como la acción de teclado indicada por el perfil en juegos de teclado o híbridos.
- `native` — conserva el comportamiento nativo de A, útil para juegos únicamente de ratón.
- `disabled` — A no recibe una acción de Ruffle.

Cuando `native_a_mode=keyboard`, parte de la ruta de A se resuelve internamente en el launcher. Normalmente el colaborador solo debe indicar la acción deseada en `south=` y dejar `right_trigger=none` a menos que conozca esa ruta interna.

## Controles de ratón

El frontend incluido proporciona el comportamiento de cursor utilizado por el proyecto. El clic adicional puede aprovechar `gptokeyb2` de PortMaster cuando exista en el sistema.

Un juego exclusivamente de ratón puede conservar A como clic nativo. Un juego híbrido puede utilizar A como tecla y R1 como clic mediante su perfil.

Si una consola o CFW se comporta diferente, reporta exactamente el dispositivo y firmware para poder ajustar el perfil o la plataforma sin romper otros sistemas.

## Modo de rendimiento

Ruffle Handheld incluye optimizaciones conservadoras durante la ejecución de los juegos:

- Solicita governor `performance` en CPU/GPU/memoria cuando esos nodos existen y el sistema permite modificarlos.
- Restaura los valores anteriores al cerrar el juego.
- Usa un symlink para el SWF temporal principal cuando es posible en lugar de copiar el archivo completo.
- Si alguna optimización no está disponible, continúa usando un fallback seguro.

Esto **no es overclock**. El proyecto no agrega frecuencias ni voltajes nuevos.

## Temas de EmulationStation

Ruffle Handheld no reemplaza ni modifica los archivos del tema del usuario.

Durante la configuración revisa el tema activo:

- Si el tema ya contiene una entrada de sistema `flash`, utiliza `flash`.
- Si no existe, el sistema Flash usa la entrada `arcade` del mismo tema como fallback.

Así Flash conserva el aspecto del tema seleccionado sin instalar un tema propio encima del usuario.

## Seguimiento de compatibilidad

La base oficial de compatibilidad de la comunidad es **`Compatibility.xlsx`**, ubicada en la raíz del repositorio. Ahí se registran estado del juego, rendimiento, controles, tipo de entrada, consola, CFW/sistema operativo, arquitectura, audio, perfil utilizado y notas de las pruebas.

Compatibilidad y rendimiento se registran por separado porque un juego puede abrir correctamente y aun así correr lento.

Estado de compatibilidad:

- `Perfect` — no se encontraron problemas importantes durante esa prueba.
- `Playable` — se puede jugar con problemas menores.
- `Partial` — falta o falla una función importante.
- `Boots` — llega a mostrar contenido, pero todavía no se considera jugable.
- `Doesn't open` — el launcher/runtime no logra entrar al juego.
- `Black screen` — el runtime abre, pero la salida del juego permanece negra.
- `Crash` — el runtime o juego se cierra inesperadamente.
- `Needs assets` — el SWF principal abre, pero faltan archivos adicionales necesarios.
- `Untested` — todavía no existe una prueba confirmada por la comunidad.

El rendimiento se registra por separado como `High`, `Medium`, `Low`, `Unknown` o `N/A`.

Un mismo juego puede tener resultados distintos según la consola o el CFW, por lo que pueden existir varias filas de prueba. La comunidad normalmente **no edita el Excel directamente**: envía un **Game compatibility report** desde Issues y un mantenedor revisa el resultado y lo agrega al tracker.

## Cómo aportar

No necesitas saber Git para ayudar.

Entra a **Issues → New issue** y selecciona uno de los formularios incluidos:

### Game compatibility report

Úsalo después de probar un juego. El formulario solicita:

- Juego y nombre del SWF.
- Versión de Ruffle Handheld.
- Consola.
- CFW / sistema operativo.
- SoC / arquitectura.
- Estado de compatibilidad.
- Rendimiento.
- Controles.
- Audio.
- Notas y logs cuando sean necesarios.

Envía reportes separados cuando el mismo juego se comporte diferente en distintas consolas o CFW.

### Control profile submission

Úsalo para proponer o mejorar controles. Incluye:

- Juego y nombre del SWF.
- Consola / CFW usada durante la prueba.
- Controles originales de teclado/ratón.
- Mapeo propuesto para la portátil.
- Acciones que realmente probaste dentro del juego.

### Runtime bug report

Úsalo para problemas del proyecto como configuración, lanzamiento, cursor, controles, regresiones de rendimiento, carga multifile o integración con temas.

### Pull Requests

Los colaboradores que prefieran Git pueden modificar directamente los archivos reales:

```text
Profiles: port/rufflehandheld/rufflehandheld/profiles/
Runtime:  port/rufflehandheld/rufflehandheld/runtime/
```

Mantén los cambios pequeños y enfocados. Un aporte de controles normalmente necesita únicamente su `.profile`. Los resultados de compatibilidad deberían enviarse mediante el formulario de GitHub para mantener consistente el tracker. No agregues SWFs ni recursos de juegos con copyright.

## Estructura del repositorio

```text
Ruffle-Handheld/
├── .github/
│   ├── ISSUE_TEMPLATE/        Formularios de aportes comunitarios
│   └── workflows/             Automatización del release
├── port/
│   └── rufflehandheld/        Fuente completa del port instalable
├── tools/
│   └── build_release.py       Empaquetador para mantenedores
├── Compatibility.xlsx        Tracker comunitario de compatibilidad
├── README.md
├── README.es.md
├── LICENSE
├── VERSION
├── .gitattributes
└── .gitignore
```

El release instalable contiene solamente:

```text
Ruffle Handheld.sh
rufflehandheld/
```

`.github`, `Compatibility.xlsx`, `tools` y los archivos propios del repositorio no se copian a la consola.

## Generar el ZIP offline

Los jugadores y colaboradores normales **no ejecutan este script**.

GitHub Actions puede generar el paquete offline automáticamente. Un mantenedor que quiera construirlo localmente puede ejecutar:

```text
Windows:  py tools\build_release.py
Linux:    python3 tools/build_release.py
macOS:    python3 tools/build_release.py
```

Utiliza únicamente la biblioteca estándar de Python y genera `releases/rufflehandheld.zip`.

## Solución de problemas

**Flash Games no aparece en EmulationStation**  
Reinicia EmulationStation después de ejecutar Ruffle Handheld una vez. Si continúa sin aparecer, reporta el CFW y la ubicación de su `es_systems.cfg`.

**Un juego no aparece**  
Confirma que el archivo principal termine en `.swf` y esté dentro de la carpeta `flash/` creada durante la instalación.

**Un juego multifile abre pero faltan recursos**  
Comprueba que la carpeta adicional use exactamente el mismo nombre base: `Game.swf` + `flash_data/Game.files/`.

**R1 no hace clic en un CFW específico**  
Reporta si el sistema tiene PortMaster/gptokeyb2 e incluye consola y CFW. En perfiles de ratón, el clic nativo de A puede seguir disponible.

**Pantalla negra o crash**  
Abre un Runtime bug report o Game compatibility report y adjunta los logs de `Ports/rufflehandheld/logs/` cuando existan.

**Un profile funciona diferente en otra consola**  
No asumas que el perfil está mal para todos. Reporta la consola y CFW porque el mapeo del controlador puede variar entre entornos.

## Componentes de terceros y legal

Ruffle Handheld es un proyecto de integración/launcher. La emulación de Flash utiliza componentes derivados de Ruffle incluidos para la arquitectura objetivo.

- Ruffle: https://ruffle.rs/
- ruffle4consoles: https://github.com/Hexadecinull/ruffle4consoles
- PortMaster / gptokeyb2: https://github.com/PortsMaster/gptokeyb2

Los avisos de terceros necesarios para el runtime distribuido se conservan dentro de:

```text
port/rufflehandheld/rufflehandheld/licenses/
```

Ruffle Handheld no distribuye juegos Flash. Los usuarios y colaboradores son responsables de contar con el derecho de uso de los SWFs y recursos externos que agreguen.
