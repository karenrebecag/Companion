# Wave 16o — Portal de la isla, brillo de pantalla y señalar con fn

**Estado: CERRADO EN CÓDIGO (2026-09-25, sin commit; instalada). Aprobado 2026-09-25. D1 = shader Metal igual al de Incredible; D2 = sin contorno, igual que Incredible.** Pedido de Karen con capturas de las 20:56 y 20:57: "necesitas
permitir overflow como si fueran portales para tooltips y dropdowns… puedes replicar el marco
azulado en fn de incredible sobre companion? y el cursor selector que aparece en fn".
Investigación: `docs/research/incredible-fn-glow-pointer.md` (valores del bundle de Incredible;
solo valores, nunca código). Reemplaza y concreta 16i §10 (16i-4).

## 1. Qué falla hoy

- **Tooltips y menús recortados.** Todo el contenido de la isla vive bajo
  `.clipShape(NotchShape)` (`IslandView.swift:94`). "Volumen de la voz" se corta en el borde
  izquierdo de la forma y "Más" se dibuja en la franja de la muesca, debajo de la cámara.
- **Clics.** El panel solo acepta clics dentro de `shape` (`IslandChrome.track`). Un menú que
  sobresalga de la forma quedaría a la vista, pero sin responder a los clics.
- **fn no muestra nada fuera de la isla.** No hay brillo en los bordes, rastro del cursor ni
  captura de lo señalado. `AXUIElementCopyElementAtPosition` no se usa en ningún lado.

## 2. 16o-1 Portal (tooltips y menús fuera del recorte)

El lienzo mide 560 × 620 y es más grande que la forma, así que el portal cabe dentro de la misma
ventana. No hace falta una ventana nueva. Incredible hace lo mismo: un portal DOM dentro de su
ventana overlay.

- Una capa `IslandPortal` encima del `clipShape`, en el `ZStack` de `IslandView`. Los disparadores
  publican su rectángulo con anchor preferences y la capa dibuja ahí el tooltip o el popover.
- **Colocación** (función pura `PortalPlacement.place(anchor:size:canvas:forbidden:)`):
  1. Por defecto va arriba del disparador, con 4 pt de separación.
  2. Si arriba invade la franja de la muesca, o se sale del lienzo, va abajo, con 6 pt.
  3. En horizontal se centra y se ajusta dentro del lienzo con un margen de 8 pt.
- **Valores de Incredible:**
  - Tooltip: fondo `#17181B`, texto de 14 pt en medium, solo opacidad, 0,15 s.
  - Menú: 230 de ancho y radio 16, que ya tenemos. Sombra `0 16 48` al 14 %, entrada con
    fundido + 4 pt en 0,2 s.
- **Clics:** el área activa pasa a ser la unión de la forma y el popover abierto. Los tooltips
  nunca reciben clics.
- **Tests:**
  - Colocación: arriba, abajo por la muesca, abajo por el borde y ajuste a izquierda/derecha.
  - Área activa: la unión cuando hay popover y solo la forma cuando no lo hay.

## 3. 16o-2 Brillo de pantalla mientras suena fn

- Una ventana por pantalla, a pantalla completa, sin clics, en todos los Spaces y encima de apps en
  pantalla completa. Se crea al arrancar y solo cambia su opacidad.
- **Valores de Incredible:**
  - Colores: rueda de azul `#1C69F0`, teal `#0AB4AF`, violeta `#8C46E6` y cian `#1496DC`. Gira
    alrededor del centro de la pantalla con una deriva lenta de unos 71 s por vuelta.
  - Forma: banda de unos 120 px hacia adentro, con ondulación. Esquinas rectas; no sigue el
    bisel.
  - Opacidad máxima 0,5. Entra en 260 ms y sale en 900 ms; baja a la mitad mientras piensa.
- **Estados:** encendido mientras escucha con fn, a la mitad mientras piensa y apagado en reposo.
- **Ajustes:** interruptor "Brillo de pantalla" en General, encendido por defecto, como
  `screen_glow_enabled` en Incredible. Con Reducir movimiento no gira ni ondula; solo aparece y se
  va.
- **Tests:**
  - La máquina de estados: fase → opacidad objetivo.
  - El ángulo de cada color en un instante dado.
  - Que el interruptor apagado nunca muestre la ventana.

## 4. 16o-3 Señalar con el cursor

- **Rastro:** tinta `rgb(70,120,245)` de 16 pt como máximo, 620 ms de vida, que se afina en el
  último 20 %. Posición suavizada al 0,3, un punto nuevo cada 1,5 pt como mínimo, compuesto al
  30 %. Si el cursor salta más de 260 pt, el trazo se corta. Va en la misma ventana del brillo con
  `TimelineView` + `Canvas`.
- **Orbe que sigue al cursor:** 32 pt, desplazado +14/+17 del cursor, suavizado al 0,16. Debajo,
  chips de lo capturado (archivo, texto seleccionado, texto copiado) que entran con resorte.
- **Qué señalaste:**
  - Cada 100 ms mientras fn está abajo se guarda el elemento de Accesibilidad bajo el cursor (app,
    ventana, rol, título o valor recortado) junto con la hora.
  - Al cerrar el turno, esa lista se alinea con las palabras y viaja como contexto del turno.
  - Solo en memoria: nada al disco ni al log.
  - Nuevo puerto `PointerProbe` en Services, probado con un doble.
- **Tests:**
  - El rastro: puntos que caducan, corte por salto y grosor por edad.
  - La alineación de palabras con muestras por tiempo.
  - Que el contexto se vacíe al terminar el turno.

## 5. Decisiones abiertas

- **D1 El brillo:** ¿shader de Metal, igual al de Incredible (ondas, ruido), o degradado
  angular nativo de SwiftUI (misma rueda de color y giro, sin ondas)? El shader obliga a compilar
  un `.metal` dentro del paquete SPM, y eso toca `Package.swift`, que es config raíz.
- **D2 Marco del elemento señalado:** Incredible no lo tiene; en su código web no hay contorno del
  elemento bajo el cursor, solo rastro y orbe. ¿Lo añadimos (contorno azul del elemento de
  Accesibilidad) o nos quedamos como ellos?

## 5b. Cómo se hace D1 sin tocar la config

El toolchain de Metal no está instalado en esta Mac (`xcrun metal` pide descargar un componente,
que sería instalar una dependencia). El shader se escribe como texto MSL y se compila al arrancar
con `MTLDevice.makeLibrary(source:)`, que va dentro de Metal.framework; se dibuja en un `MTKView`.
`Package.swift` no se toca. Si la compilación falla en tiempo de ejecución, el brillo no aparece y
se registra en el log (sin romper la escucha).

## 6. Límites

- La captura recortada alrededor del cursor exige el permiso de grabación de pantalla: queda
  fuera de esta wave.
- Archivos por sesión: 16o-1 toca `IslandView`, `IslandPopover`, `IslandChrome` y un
  `IslandPortal` nuevo. 16o-2 y 16o-3 suman una ventana overlay en UI, el cableado en
  `CompanionMain` y el puerto en Services.

## 7. Cierre (2026-09-25)

- **16o-1**: `IslandPortal` (colocación pura `PortalPlacement`, arriba 4 / abajo 6, margen 8, nunca en la
  franja de la muesca); tooltip `#17181B` 14 medium; el menú cae bajo su botón; el área de clic es forma
  ∪ menú (`IslandGeometry.portal`).
- **16o-2**: `ScreenOverlays` (una ventana por pantalla, sin clics, `sharingType = .none`), shader MSL
  compilado al arrancar (`ScreenGlowShader`, test que lo compila), interruptor en Ajustes › General.
- **16o-3**: `PointerTrail`/`PointerOrb` dibujados solo en la pantalla donde empieza el hold y nunca con
  Reducir movimiento; `PointerSampler` (AX bajo el cursor cada 100 ms) → `<pointed_while_speaking>` en
  el turno, en los dos pipelines, solo con el canal de pantalla activo; la memoria no lo guarda.

Revisiones (APPROVE tras re-revisión): código HIGH ×2 (el muestreo solo arrancaba con clave; un popover
que se iba borraba el área de clic del nuevo), MEDIUM ×3 (rastro en todas las pantallas, interruptor no
reactivo, Reducir movimiento); seguridad MEDIUM (el menú sobrevivía a un cambio de tamaño). Todas con
test. Sin chips de captura bajo el orbe: no hay dato de qué se capturó. Pendiente: prueba en vivo.

## 8. Crash con fn (2026-09-26 00:20)

Con fn sobre una ventana de Companion, `AXUIElementCopyElementAtPosition` se respondía dentro del propio
proceso, en la cola del muestreo, y SwiftUI evaluaba `CompanionRootView` fuera del hilo principal
(trap del aislamiento). Arreglo: `PointerSampler` pregunta antes `ownsPoint` y no muestrea sobre una
ventana propia que reciba clics (`AXPointerProbe.ownWindowCovers`, en el hilo principal). Test:
`pointerSamplerSkipsOwnWindowsTests`. La revisión encontró que la prueba anterior del muestreo usaba el
guardia real y reventaba el proceso de tests (sin `NSApp`); corregido y aprobado.
