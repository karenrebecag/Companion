# Wave 16g — Ajustes con la forma de los de Incredible

**Estado: CERRADO (2026-09-25). Aprobado con "vamos, aprobado"; Memoria entró; s1 y s2 en una corrida.** Karen, sobre 10 capturas de Incredible 0.2.36: "mira la ui del
módulo de config es muy bonita."

Lo que no cambia: el inventario de 16d (14 opciones, tope 15, sin jerga) y lo que hace cada
opción. Esta wave cambia **la forma**: dónde vive cada opción y cómo se ve.

Criterio de done (medible):
- Ajustes es una hoja con barra lateral y buscador; ningún ajuste queda a más de un clic de abrir la
  hoja.
- Cada página son tarjetas blancas de filas; cada fila es título + subtítulo gris + un control al
  final (píldora "Cambiar", interruptor, desplegable o deslizador). Cero campos sueltos fuera de una
  tarjeta.
- El buscador encuentra cualquier opción del inventario por título o subtítulo, en es y en en, y al
  elegirla salta a su página y la resalta.
- `SettingsParityTests` sigue en verde (≤15 opciones, sin jerga) y cada opción declara su página.
- Captura de cada página en claro y oscuro junto a la de Incredible (§5).

## 1. Qué hace Incredible y qué hacemos hoy

| | Incredible | Companion hoy (16d) |
|---|---|---|
| Contenedor | Hoja modal, X arriba a la derecha | Hoja con 3 pestañas arriba |
| Navegación | Barra lateral: General, Incredible, Vocabulary, Contacts, Memory, System; sección Account (Account, Members, Billing, Data and privacy); versión abajo | Tú / Voz y teclas / Privacidad y sistema |
| Buscar | "Search settings…" arriba de la barra | No hay |
| Filas | Tarjeta blanca radio ~24 con borde fino; filas separadas por una línea; título negro, subtítulo gris, control a la derecha | Controles apilados con encabezados en versalitas |
| Controles | Píldora gris "Change", interruptor negro, desplegable en píldora, deslizador con % | Mezcla de `SettingsItem`, botones y campos |
| Tecla | La tecla dibujada como tecla (`fn`) dentro del subtítulo | `fn` en un keycap aparte |
| Listas | Vocabulario: ejemplo arriba ("Tell **Frederick** I'm in") + lista + píldora negra "+ Add word" | Un campo de texto con palabras separadas por comas |
| Vacíos | Ilustración + frase + botón (Contacts, Memory) | — |
| Peligro | Sección "Danger zone" con píldora roja | "Borrar conversaciones" dentro de Sistema |

## 2. Diseño

### 2.1 Páginas (barra lateral)

| Página | Qué lleva (opciones de 16d, sin inventar ninguna) |
|---|---|
| **General** | Hablar (fn como tecla, "Cambiar"), tecla de dictado, idioma, sonidos |
| **Voz** | Voz (desplegable + "Escuchar"), la voz de ElevenLabs si hay key |
| **Vocabulario** | Página de lista: ejemplo arriba, palabras, "+ Añadir palabra" |
| **Memoria** | Lo que Companion recuerda de ti (lectura de `MemoryStore`, con borrar por entrada); vacío con ilustración si no hay nada |
| **Tú** | Tarjeta con foto y nombre arriba; filas: sobre ti, instrucciones, apariencia, tamaño de texto |
| **Privacidad** | Permisos (4 filas con estado y "Abrir"), contexto (pantalla, documentos), claves |
| **Sistema** | Versión + "Buscar de nuevo", adjuntos guardados, "Ver la bienvenida otra vez"; **Zona de peligro**: borrar conversaciones (píldora roja con confirmación) |

Contactos, Miembros y Facturación no existen en Companion: no hay cuenta ni equipo. No se dibujan.

Memoria es un panel nuevo, no una opción: muestra y borra, no cambia una preferencia. El tope de 15
no se mueve. Si Karen prefiere no tocar memoria en esta wave, la página se va y queda para después.

### 2.2 Piezas (UI, tokens)

- `SettingsSidebar`: buscador arriba, secciones, versión abajo. Fila activa en gris claro.
- `SettingsCard` + `SettingsRow(title:subtitle:trailing:)`: tarjeta con borde de 1 px y separadores
  internos; el padding y los radios salen de tokens nuevos en `Space`/`Radius`, no de literales
  (contrato de conformidad).
- `SettingsPill(kind: .neutral | .primary | .destructive)`: gris "Cambiar", negra "+ Añadir", roja
  "Borrar…".
- `SettingsToggle`: interruptor negro (blanco en oscuro).
- `Keycap` inline: la tecla dentro del texto del subtítulo.
- `SettingsEmptyState`: ilustración (SF Symbols compuestos, nada de assets de Incredible) + frase +
  botón.
- Colores: fondo de la hoja con un token nuevo `Semantic.surfaceSunken` (~#F9F9F9; hoy solo existen
  `surface`, `surfaceOverlay`, `border`, `hairline`), tarjeta `Semantic.surface` (blanco), borde
  `Semantic.hairline`. En oscuro, los mismos tokens invertidos.

### 2.3 Búsqueda (Core, puro)

`SettingsSearch.match(_ query:, in: [Entry]) -> [Entry]`: normaliza (minúsculas, sin acentos), busca
por palabras en título y subtítulo localizados, ordena por coincidencia en título primero. El
inventario le da a cada opción su `page`, así que el resultado sabe a dónde saltar. Sin resultados:
"Nada con «x»".

### 2.4 Lo que no se copia

Nada de su código, textos ni iconos: solo la estructura observable y medidas aproximadas de las
capturas. Los textos son los nuestros de 16d.

## 3. TDD

- `SettingsSearch`: acentos ("vocabulario" encuentra "Vocabulario" y "vocabulário" no aplica), en/es,
  título antes que subtítulo, consulta vacía = nada, sin resultados.
- `SettingsInventory`: cada opción tiene página; ninguna página queda vacía salvo las de lista;
  sigue ≤15 y sin jerga.
- `VocabularyPreference`: añadir y quitar una palabra respetan `Vocabulary.parse` (tope 50, 40
  caracteres, sin duplicados).
- Memoria: listar y borrar una entrada pasan por `MemoryStore`; borrar pide confirmación.
- Zona de peligro: borrar conversaciones sigue exigiendo confirmación (test existente, ruta nueva).
- Capturas (`COMPANION_SNAPSHOTS`) de las 7 páginas en claro y oscuro.

## 4. Archivos

Core: `SettingsSearch.swift` (nuevo), `SettingsInventory.swift` (página por opción; se mueve a Core
si la búsqueda lo necesita). UI: `SettingsView.swift` (hoja + barra), `SettingsPieces.swift` (nuevo:
tarjeta, fila, píldora, interruptor, vacío), `SettingsPages.swift` (nuevo), `SettingsAppPane.swift`,
`HoldSettings.swift`, `SettingsVoiceSection.swift` (pasan a filas). Tests: `SettingsSearchTests`,
`SettingsParityTests`, `SnapshotTests`.

Son más de 5 archivos: se hace en dos sesiones. **s1**: piezas + barra + búsqueda + General, Voz,
Tú, Privacidad, Sistema. **s2**: Vocabulario y Memoria como páginas de lista.

## 5. Riesgos

- `ImageRenderer` no pinta `TextField` ni `ScrollView`: las capturas del buscador y de listas largas
  se revisan en la app instalada, no en PNG.
- La hoja crece de 560 a ~760 pt de ancho por la barra lateral; en pantallas chicas se limita al
  alto visible.

## 6. Orden respecto a 16f

Independientes: 16f toca la isla, 16g la hoja de Ajustes. Se pueden aprobar juntas; recomiendo
16f primero porque es lo que Karen ve todo el día.

## 7. Aprobación

Pendiente de Karen: esta spec, si Memoria entra en esta wave (§2.1), y el orden respecto a 16f.

## 8. Cierre (2026-09-25)

| Criterio | Resultado |
|---|---|
| Hoja con barra lateral y buscador | Hecho: 7 páginas en dos grupos, versión abajo |
| Filas en tarjetas con control al final | Hecho: `SettingsCard`, `SettingsRow`, `SettingsPill`, `SettingsSwitch`, `SettingsKeycap` |
| Buscar cualquier opción es/en y saltar | Hecho: `SettingsSearch` (Core), test sobre las 14 opciones en los dos idiomas; la fila se ilumina 1,6 s |
| ≤15 opciones, sin jerga | 14; `SettingsParityTests` en verde |
| Capturas claro/oscuro | 14 PNG de las 7 páginas (`COMPANION_SNAPSHOTS`) |

Desviaciones:
- **Zona de peligro:** "Borrar conversaciones" no existía; lo que se puede vaciar es la carpeta de
  adjuntos, y eso quedó ahí. Borrar todas las conversaciones sería código nuevo y no se inventó.
- **Sin token `surfaceSunken`:** el fondo de la hoja es `Semantic.background` (#FAFAFA, ya existía).
  Token nuevo solo `Radius.card` (20).
- **Hablar (fn) no tiene "Cambiar":** la tecla es fija; se dibuja como tecla, sin botón que no haga nada.
- **Memoria olvida borrando el archivo** (con confirmación en la fila), no a la papelera.

Revisión:
- Seguridad (HIGH): los enlaces simbólicos en `notes/` o `sessions/` se leían y llegaban a la hoja y
  al prompt. Arreglado en el `readFile` compartido; la re-revisión encontró lo mismo con la carpeta
  enlazada, arreglado en el único listado (`names(in:)`). Dos tests en rojo antes de cada fix.
  Aceptado: un enlace duro no se distingue de un archivo; explotarlo ya exige escribir en la carpeta.
- Código (HIGH): dos desplegables sin título en General compartían anclaje. `SettingsItem` tiene
  `id`; test en rojo antes. MEDIUM: Sistema relee el tamaño de adjuntos al entrar. LOW: un solo
  temporizador de iluminación.
