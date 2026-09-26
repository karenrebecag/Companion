# Wave 16c–16e — UX/UI con paridad de Incredible

**Estado: CERRADO (2026-09-25).** Karen: "vamos con la ui de una, que quede igual que la de incredible". Parte de
`docs/research/ux-incredible-vs-companion.md` (§2 = contrato de paridad) y lo actualiza a lo que
cambió desde el 24: sin Groq, oído de Apple, boca ElevenLabs, manos y vista (15g/16a).

Karen (2026-09-25): "Asegúrate de que la UX/UI funcione igual que la de Incredible."

Criterio de done (medible): **pasos hasta el primer hold ≤ 5, todos dentro de la app**; **opciones
visibles ≤ 15**; **cero etiquetas técnicas** (proveedor, modelo, ejecutor, TTS, VAD); la isla es
la superficie principal (se escribe, se ve lo que dijo, se ven los resultados) y la ventana es
secundaria; ninguna pantalla de estado dice "Escuchando…".

## 1. Paridad: qué se copia y qué no

| Incredible hace | Companion 16c–16e | Nota |
|---|---|---|
| Bienvenida con stepper, una idea por pantalla, portada con un botón | igual | §2 |
| Login con su cuenta | **no**: claves propias (OpenAI obligatoria, Cerebras y ElevenLabs recomendadas) | no hay servidor |
| El orb saluda por voz mientras prepara | igual (voz de Apple si aún no hay clave) | |
| Idiomas en chips (máx. 5) | idioma de respuesta es/en en chips | Companion hoy solo es/en |
| **Permisos: una pantalla, 4 filas con estado y check**; continuar solo con todo concedido | igual: Micrófono · Accesibilidad · Grabación de pantalla · Reconocimiento de voz | cada fila abre el panel exacto y detecta el cambio |
| Micrófono con barra de nivel en vivo | igual | |
| Tour ilustrado que toma la pantalla | **no en 16c** | lo más caro y lo menos necesario; wave aparte si se quiere |
| "It's your turn": pantalla oscurecida, glifo `fn`, frase exacta; no termina sin un hold real | igual ("Mantén fn y di: *¿qué hay en mi pantalla?*") | |
| **Barra del notch = la app**: se abre al pasar el ratón; campo "Ask anything", adjuntar, enviar; resultados como tarjetas; menú de 5 (Settings · Open app · Shortcuts · Feedback · Clear history en rojo) | igual, sobre la isla existente | 16e |
| Píldora de escucha: solo barras de onda + anillo, sin texto | igual; transcript parcial debajo | 16e |
| Luz de estado: **ámbar = te necesita, verde = terminado** | igual (encargos y hojas de aprobación) | 16e |
| "No te oí": tarjeta que se va sola a los 6 s | igual | 16e |
| La voz **apunta a la tarjeta**, nunca la recita | igual (regla de prompt + tarjetas de 9e en la isla) | 16e |
| Errores con frase completa y salida ("Sin conexión.", "La clave de OpenAI no es válida. Abrir Claves") en la barra | igual | 16e |
| Cerrar la ventana no cierra la app; menú de barra con 5 entradas | igual: Cancelar acción (Esc) · Mostrar · Ajustes… · Buscar actualización… · Salir | 16d |
| Ajustes sin modelo, proveedor ni clave visibles | **claves sí** (no hay cuenta), enmascaradas en Privacidad y sistema; nada más de IA | 16d |
| Vocabulario ("words Incredible should get right") | la lista `contextualStrings` del oído pasa a ser editable en Ajustes | 16d |
| Modo pasivo a los 10 min | ya existe el rollover de 5 min (15a); sin cambio | |
| Geist + Geist Mono, negro sobre blanco, primario = píldora negra, chips grises, radio ~24 px | tokens de la app a ese sistema; orb con textura como identidad | 16c–16e |
| Tono: segunda persona, frases cortas, sin jerga, admite límites | reescritura de las ~12 etiquetas con jerga | 16d |

## 2. Entregas

- **16c — Bienvenida y permisos.** 7 pantallas: Portada ("Habla con tu Mac. Ella hace el resto.")
  → Hola (orb que saluda, nombre) → Claves (OpenAI obligatoria con verificación en vivo y "¿Dónde
  la consigo?"; Cerebras y ElevenLabs recomendadas, con una frase de por qué) → Permisos (4 filas)
  → La tecla (fn; si la tecla globo está asignada, botón a Teclado con una línea) → Tu micrófono
  (nivel en vivo) → Tu turno (hold real obligatorio, "Saltar" arriba). Se muestra una vez; se
  puede reabrir desde Ajustes.
- **16d — Ajustes fijos.** 3 pestañas, ≤ 15 opciones. **Tú:** nombre, foto, sobre ti, cómo
  responder. **Voz y teclas:** voz (6 presets con muestra), idioma, tecla para hablar (fn /
  Opción derecha), tecla de dictado, micrófono, sonidos, vocabulario. **Privacidad y sistema:**
  ver la pantalla, documentos abiertos, permisos con estado, claves enmascaradas, apariencia,
  modo depuración (transcripts), buscar actualización. Fuera de la UI (quedan en `Config`):
  velocidad, tono, fin de turno, paciencia, avidez, cancelación de eco, decidir en local,
  ejecutor, orden de proveedores, portapapeles, carpeta en la cabecera. Menús y cabecera por
  `Localized`. Menú de barra de 5 entradas; cerrar ventana ≠ salir.
- **16e — La isla como app.** Reposo: marca discreta. Hover en el borde superior: panel con campo
  "Pídele algo a Companion…", adjuntar, enviar, icono de ajustes con el menú de 5. Hold: barras +
  anillo, transcript parcial debajo, sin texto de estado. Pensando: pulso. Hablando: la frase en
  el panel. Resultados: tarjetas apiladas (título, una línea, "Ver →"). Luz ámbar/verde. "No te
  oí" 6 s. Errores de una línea con acción. La voz apunta a la tarjeta.

Cada entrega va en su propio PR, con capturas antes/después.

## 3. TDD y verificación

- ViewModels de la bienvenida y de la isla con tests de estado (qué pantalla sigue, cuándo se
  habilita continuar, auto-cierre a 6 s, luz ámbar/verde, error → acción).
- Test de inventario: las opciones visibles de Ajustes ≤ 15 y ninguna etiqueta contiene
  proveedor/modelo/TTS/VAD/ejecutor (lista de términos prohibidos sobre `Localizable.strings`).
- Test de i18n: toda cadena de menús y cabecera pasa por `Localized` (es y en con las mismas claves).
- Revisión visual: capturas de cada pantalla (claro y oscuro) contra las de Incredible del §2.7–2.8.

## 4. Riesgos

- El panel en hover sobre el notch compite con otras apps de notch (NotchNook está instalada):
  se detecta y la isla se desplaza o usa solo el atajo.
- La prueba "hold real obligatorio" no puede bloquear a quien no tiene micrófono: "Saltar" siempre.
- Reducir opciones borra ajustes que Karen hoy usa: los valores actuales se conservan en `Config`.

## 5. Aprobación

Aprobada 2026-09-25, incluidas las dos diferencias (claves visibles, sin tour). Las tres entregas seguidas.

## 9. Cierre (2026-09-25)

Entregado en una pasada (16c, 16d y 16e), 378 tests, gates 0 fallos, ×3 verde, instalada.

| Entrega | Qué quedó | Tests |
|---|---|---|
| 16e isla | Panel negro Geist en hover: campo, adjuntar, enviar, menú de 5 (Borrar historial en rojo con confirmación en el panel); tarjetas de respuesta (3, "Ver →"); luz ámbar/verde; escucha = barras + parcial, sin texto; "no te oí" y la pista se van a los 6 s (`noticeExpired`); errores con acción (Abrir Claves / panel del permiso); regla de voz "no leas la tarjeta, señálala" | IslandParityTests, HoldKeyTests, SessionMachineTests |
| 16c bienvenida | 7 pantallas (`WelcomeFlow` puro + `WelcomeModel` + puerto `WelcomeDevices` con adaptador de sistema): saludo con voz de Apple, claves con verificación en vivo (y camino local sin clave, ADR 001), 4 permisos en vivo, fn con enlace a Teclado, medidor de micro, "Tu turno" termina solo con hold real; Saltar solo en micro y tu turno; se reabre desde Ajustes | WelcomeFlowTests, WelcomeModelTests |
| 16d ajustes | Tú · Voz y teclas · Privacidad y sistema; 14 opciones (`SettingsInventory`); fuera de la UI con su valor: velocidad, volumen, fin de turno, paciencia, avidez, tono, eco, decidir en local, portapapeles, app enfocada, tipografía, acento, marca, atajo manos libres; vocabulario editable al oído; menús y barra por catálogo; ítem en la barra de menús con 5 entradas | SettingsParityTests (≤15, jerga prohibida, idiomas, barra, vocabulario) |

Revisiones: seguridad BLOCK (1 crítico) y código REQUEST_CHANGES, todo corregido con test en rojo primero:

| Hallazgo | Arreglo |
|---|---|
| CRÍTICO: una hoja que llega mientras escribes en la isla deja el panel con el teclado; Return aprobaba | `yieldsKeyboard` suelta el teclado; Permitir ya no tiene atajo (Return nunca aprueba, también en la ventana) |
| MEDIO: guarda de clic fallaba abierta | `ApprovalClickGuard.accepts(nil)` = false |
| ALTO: clic en otra app dejaba el panel abierto para siempre | `IslandPanel.onResignKey` desenfoca el campo |
| ALTO: `WelcomeVoice` sin reentrada ni cancelación | una línea a la vez; cancelar detiene la voz |
| MEDIO: reabrir la bienvenida no saludaba; fila de dictado sin refresco; menú no cambiaba de idioma | `greeted` se reinicia; modelo en `@State` con sondeo; `companionLanguageDidChange` |

Desviaciones:
- **Modo depuración no es un interruptor**: sigue siendo solo `COMPANION_DEBUG_TRANSCRIPTS=1` (15d-6 lo quiso así por privacidad); la isla ya avisa cuando está activo.
- **Micrófono (elegir dispositivo) no existe**: no hay selector de entrada que exponer; no se inventó.
- **"Borrar historial" archiva**: vacía la isla y abre conversación nueva; la anterior queda en Conversaciones (no hay borrado en el store).
- **Retry fuera**: "Sin conexión" va sin botón; el próximo hold reconecta.
- **`OnboardingView` queda sin uso en producción** (solo si no se inyecta bienvenida). Borrarlo es decisión de Karen.
- Capturas: `COMPANION_SNAPSHOTS=<dir> swift test --filter uiSnapshots` (campos, scroll y links no se pintan fuera de pantalla).
- Deuda: flake de temporización en `voiceViewModelTests` (pasa aislado).
