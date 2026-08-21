# Wave 6a — Fundamentos de escritorio

**Estado: BORRADOR** — pendiente de aprobacion de Karen.

## Objetivo

Cerrar lo que hace al rebuild frustrante frente al prototipo: menu de
aplicacion, adjuntos y feedback (avisos + sonido de interfaz). Es la tanda
que convierte "funciona" en "se siente como una app de Mac".

## Alcance

### Menu de la aplicacion (CompanionApp)
| Archivo | Contenido | Referencia |
|---|---|---|
| `AppMenu.swift` (nuevo) | `NSApp.mainMenu` completo: menu de app (Ajustes, Ocultar, Salir), Edicion (Deshacer/Rehacer/Cortar/Copiar/Pegar/Seleccionar todo — SIN esto no funcionan Cmd+C/V/X en ningun campo), Conversacion (Nueva, Adjuntar, Historial, atajos de voz con sus equivalentes visibles), Ventana. | prototipo `AppMenu.swift` (su primera linea documenta por que no es cosmetico) |

El menu se RECONSTRUYE cuando cambian los atajos en Ajustes, para que los
equivalentes de teclado mostrados nunca mientan (contrato del prototipo).
Los items de Conversacion enrutan a los ViewModels via un puerto delgado; el
menu no conoce Services.

### Adjuntos (Core + UI + App)
| Archivo | Contenido | Referencia |
|---|---|---|
| Core `Conversation.swift` (ampliar) | `AttachmentRef` gana lo que la serializacion necesita: distincion imagen/archivo ya existe (`AttachmentKind`); anadir tamano y origen. Las imagenes viajan al chat como `image_url` base64 (vision); los archivos de texto legible, inline; los binarios, solo la ruta para el especialista. | prototipo `Attachments.swift`, ledger seccion Chat |
| Services `AttachmentStore.swift` (nuevo) | Adopcion del archivo: copia a Application Support bajo el id de conversacion, miniaturas para imagenes, descarte al borrar. Limites de tamano con mensaje claro. | prototipo `Attachments.swift` |
| Services `ChatSSEAttempt.swift` (ampliar) | Serializar partes multimodales (texto + image_url) cuando el turno lleva imagenes. | prototipo `TalkClient` 299-317 |
| UI `AttachmentViews.swift` (nuevo) | Chips removibles sobre el composer con miniatura, nombre y peso; estado de arrastre sobre TODA la ventana (drag & drop en ambos modos, como el prototipo); pegar imagen desde el portapapeles. | prototipo `AttachmentViews.swift` |
| Voz | Una imagen adjuntada durante sesion de voz viva entra a la sesion (item de imagen con caption), sin bloquear el turno. | ledger; prototipo `RealtimeConversation.push` |

### Feedback (UI)
| Archivo | Contenido | Referencia |
|---|---|---|
| `Toasts.swift` (nuevo) | Avisos efimeros arriba a la derecha: aparecen con motion, se van solos (~4 s), apilables, con variante de error. API unica `toast(_:)` en el ViewModel raiz. | prototipo `Toasts.swift` |
| `UISound.swift` (nuevo) | Sonidos cortos de interfaz (alerta, confirmacion) generados o del sistema — sin assets pesados. Respeta el volumen del sistema y un toggle en Ajustes. | prototipo `UISound.swift` |

### Actualizaciones (Services + UI) — implementa ADR 002
| Archivo | Contenido |
|---|---|
| Services `UpdateChecker.swift` (nuevo) | Consulta la ultima release de GitHub (API publica, sin auth), compara versiones semver contra `Build.version`, cachea el resultado del dia. Sin red ⇒ silencio, jamas un error. |
| UI | Si hay version nueva: toast discreto + entrada en Ajustes → Sistema con boton que abre la pagina de la release. Nada de descargas en segundo plano (ADR 002). |

## Tests

Menu: el arbol de items y equivalentes como funcion pura (accion → titulo,
atajo) verificada; reconstruccion tras cambio de atajo. Adjuntos: adopcion y
descarte en directorio temporal, limites, serializacion multimodal con
fixtures, degradacion de binarios. Updates: comparacion semver con fixtures
de la API (incluida una release malformada). Toasts: cola y expiracion con
reloj inyectado.

## Definicion de done

Cmd+C/V/X funcionan en todos los campos; arrastrar una imagen a la ventana la
adjunta y el modelo la ve; los avisos aparecen y se van solos; la app avisa
cuando hay version nueva. Prueba manual de Karen incluida. Gates verdes.

## Riesgos

- Drag & drop global + SwiftUI tiene esquinas (usar el patron del prototipo,
  que ya funcionaba, no inventar).
- Las imagenes grandes infladas a base64 revientan el limite del proveedor:
  reescalar antes de codificar (el prototipo usaba maxEdge 1024; portar).
