# UX de Companion frente a Incredible — investigación y propuesta

**2026-09-24. Documento de trabajo (no es spec).** Fuentes: binario e Info.plist
de `/Applications/Incredible.app` (v0.1.81), `~/.incredible/overlay.json`,
`~/Documents/Incredible-Debug`, y el código de `Sources/CompanionUI` +
`CompanionApp` con sus `Localizable.strings`. Seis agentes de lectura;
todo lo afirmado tiene archivo y línea en los informes originales.

Karen: "ni siquiera yo entiendo cómo configurar la app porque la UX es pésima…
fijar nuestra configuración y quitar opciones de personalización… puede ser
muchísimo más sencillo."

---

## 1. Diagnóstico en una frase

Companion expone **sus decisiones de ingeniería** como opciones (proveedor,
ejecutor, router, canales de contexto, tecla de dictado, VAD), y esconde
**lo único que hace falta para que funcione** (clave, Accesibilidad, tecla
globo del sistema). Incredible hace lo contrario: la IA es invisible y fija;
lo configurable es lo que un usuario entiende (micrófono, idioma, sonidos,
privacidad, atajos).

---

## 2. Qué hace Incredible (medido, no supuesto)

### 2.1 Lo que el usuario puede cambiar
Micrófono y altavoz (sistema / integrado / específico), idiomas, nombre y
avatar, tecla de activación y 4 atajos, dictado (tecla, nivel, estilo,
diccionario propio, importar de Wispr), sonidos del sistema, silenciar voz,
subtítulos, brillo de pantalla, indicador en reposo, mantener despierta la Mac,
modo creador de contenido, recordatorios solo texto, y privacidad: contexto de
pantalla, apps, contactos, reuniones, diagnósticos. `model_tier: minimal |
balanced` es la única decisión de IA visible.

### 2.2 Lo que NO puede cambiar
Proveedor de transcripción, modelos (usan ~15 roles distintos internamente),
claves, proveedor de voz. Todo pasa por su servidor; el kernel Python tiene un
candado mecánico contra llamadas directas a OpenAI/Groq.

### 2.3 Primer arranque (orden inferido de los recursos y prompts)
1. Permisos, con **una ilustración por permiso** (`accessibility-permissions.png`,
   `screen-reading-permissions.png`) y textos de una línea:
   "Incredible needs microphone access to hear your voice commands."
2. Nombre, correo y rol; investiga tu empresa mientras tanto.
3. Un tour que **toma la pantalla** y muestra un documento, una hoja y una
   presentación con voz en off personalizada (te llama por tu nombre).
4. **Primera orden guiada:** "hold [tecla] and say: …" con una invitación
   hablada de una frase.
5. Un PDF de una página: "Talk, and it happens. There is no syntax to learn
   and no menu to find."

### 2.4 Estados y feedback
- Sin texto de estado: barras de audio, brillo y contorno de pantalla en
  ventanas propias (`screen-glow`, `screen-outline`, `ListeningBars`).
- Transcript parcial visible mientras se mantiene la tecla.
- "No te oí" es una **tarjeta que se va sola a los 6 s**, y el sistema vuelve
  a reposo.
- La respuesta hablada **apunta a una tarjeta** en pantalla cuando hay datos
  ("I've put the full summary on your screen"); la voz nunca recita la tarjeta.
- Errores con frase completa y salida: "You're offline", "Your session
  expired.", "This needs your browser… Open Chrome and connect…, then try again."
- Cerrar la ventana no cierra la app; icono monocromo en la barra de menús con
  5 entradas: Cancel Current Action (Esc) · Show · Settings… · Check for
  Updates… · Quit.

### 2.5 Tono
Segunda persona, frases cortas, habla de sí en tercera persona ("Incredible
needs…"), promete control ("It never changes anything without asking"), admite
límites ("cannot control desktop apps **yet**"), cero jerga en la UI. Prompt de
voz: honesto, 2 frases, noticia primero, nunca "You're absolutely right!".

### 2.6 Visual
Geist + Geist Mono variable, marca "glass", fondos fotográficos en la bienvenida
(nubes, escritorio de noche, laptop), Mermaid/KaTeX para tarjetas con
diagramas y fórmulas.


### 2.7 Visto en capturas (22 pantallas de Karen, 2026-09-24)

**Flujo real de bienvenida (stepper de 10 puntos arriba):**
1. Portada: logo, "Talk to your Mac. It does the rest.", un solo botón negro
   "Get started". Fondo degradado suave (lavanda → durazno) con hairlines
   verticales casi invisibles.
2. Login en el navegador (Google o correo de trabajo) y vuelta a la app.
3. Activación: beta por invitación, presentada **como conversación** (orb +
   burbujas, opciones como chips a la derecha: "I don't have a code").
4. "Meet Incredible": el orb **habla el saludo mientras prepara** ("Have a
   listen. Incredible is saying hello while we get things ready.").
5. "A bit about you": nombre, teléfono (opcional), web de la empresa
   (opcional), rol en chips.
6. "What will you use Incredible for?": un campo libre; el botón se activa al
   escribir.
7. "Languages you speak": chips, máximo 5, precargadas con las del sistema;
   promete "only replies in the languages you pick".
8. **"Grant permissions": una sola pantalla, 4 filas** (Microphone,
   Accessibility, Keyboard input, Screen reading) con icono, estado
   "Granted" y check verde. Continuar solo cuando están concedidos.
9. "Help us make Incredible better": diagnósticos con tres líneas claras
   (What we get / How often / Switching it off) y dos botones iguales.
10. "Turn your volume on" → "Your microphone" (selector de dispositivo +
    **barra de nivel en vivo**) → modal "A quick intro… Sit back and watch.
    Move your mouse any time and a skip button appears" → tour.

**Tour:** toma toda la pantalla con una ilustración (habitación acogedora),
el orb y **una burbuja a la vez**, en primera persona ("you hold a button on
your keyboard, say what you need, and I take care of it"). Muestra widgets
del sistema reales (batería, disco, carga), iconos de apps instaladas
(Figma, Slack, Teams), y tres documentos falsos personalizados (Brief.docx,
Competitors.xlsx, Strategy.pptx, "A place to start with Karen"). Pide
Accesibilidad **en el momento en que la necesita** (diálogo de macOS para
controlar Safari). Cierra con "I live up here, at the top of your screen.
Hold fn when you want to talk to me… move your mouse up here to open it".

**"It's your turn":** la pantalla se oscurece, un glifo `fn` grande y la
frase exacta a decir ("Hold fn and say: 'Summarize what files I have on my
desktop'"), con "Skip to summary" arriba a la derecha. **La bienvenida no
termina hasta que el usuario hace un hold real.**

**Píldora de escucha:** en el centro superior, estilo notch: fondo negro,
**solo barras de onda blancas** y un anillo azul; sin texto. Nuestra isla
mostraba "Escuchando…" al lado, en la misma zona.

**Sistema visual:** sans geométrica (Geist), negro sobre blanco, botón
primario = píldora negra, secundario = píldora con borde, chips grises para
elegir, inputs gris claro sin borde, tarjetas radio ~24 px, orb azul con
textura granulada como identidad, toast de actualización oscuro con
"Not now" en texto y "Update & restart" en píldora blanca.


### 2.8 El widget del notch (3 capturas más, 2026-09-24)

**Es la app.** Un panel negro permanente en el notch que se abre al pasar el
ratón; la ventana principal es secundaria ("Open app" está en su menú).

- **Cabecera:** "Results" con icono de historial a la izquierda; a la derecha
  un icono de ajustes (sliders) que abre un menú de 5 entradas: Settings ·
  Open app · Keyboard Shortcuts · Give feedback · **Clear history** (en rojo,
  separado).
- **Cuerpo:** el orb como avatar, un campo "Ask Incredible anything…",
  adjuntar (clip) y enviar (flecha). Es decir: **escribir y hablar viven en el
  mismo sitio**; no hay "modo voz" ni "modo texto".
- **Resultados apilados debajo**, como tarjetas: "Your desktop · Files 3 ·
  Folders 6 · Total size 51 KB · 2 weeks ago" con un botón "Show →". La voz
  apunta a la tarjeta; la tarjeta abre el detalle.
- Radio grande, negro puro, texto blanco y gris, un solo acento (rojo para
  borrar). Sin etiquetas de estado.

**Contraste con Companion:** nuestra isla ya tiene cinco tamaños (pebble,
nudge, bar, card) pero es un indicador, no una superficie: no se escribe en
ella, no lista resultados, no tiene menú, y la respuesta hablada no se ve. La
ventana principal, con cabecera de ejecutor / modo / carpeta / historial, es
donde vive todo.


### 2.9 Su documentación pública (incredible.one/learn, 17 secciones, 2026-09-24)

**Arquitectura de información de la app:**
- **Barra en el notch** = la interfaz de diario: "Move your mouse to the top
  edge and it opens." Muestra lo que oyó, el estado de trabajo y avisos.
  Todo lo que necesita decirte es **una tarjeta**: pregunta, plan para
  aprobar, borrador, resultado. Luz de estado: **ámbar = te necesita, verde =
  terminado.**
- **Ventana (sidebar):** Home (tareas por día con estados *Working · Needs
  you · Upcoming · Done* y log de actividad), Apps, Browser, Knowledge,
  Scheduled, Autopilot, Saved tasks, Dictation.
- **Ajustes** (clic en tu nombre al pie del sidebar): Account · Billing and
  usage · Shortcuts · General (idioma de dictado) · Incredible (Experimental:
  "Hey Incredible"; Automatic passive mode) · Memory · Contacts · Vocabulary.
  **Ni un solo ajuste de modelo, proveedor o clave.**

**Principios escritos en su documentación:**
- "The microphone opens while you hold the key and closes the moment you
  release it." / "It only reads your screen while you're holding the talk key."
- "Everything you ask is a task." Resultado en tarjeta; **espera aprobación
  antes de cualquier cosa que llegue a otras personas o no se pueda deshacer.**
- "Two ways to talk": mantener `fn`, o `⌥ Space` para escribir en la misma
  barra. Manos libres: toque en `fn + Space`. Dictado: `Ctrl + Shift` (Mac).
- Contexto explícito: `⌥ C` toma texto o archivo, `⌥ X` captura pantalla,
  `⌥ ⇧ ⌫` limpia lo adjunto. "Hand Incredible what you're looking at before
  you ask." Puedes decir "this" y se refiere a la pantalla.
- **Modo pasivo automático** a los 10 min sin hablar: deja de hablar y avisa
  en silencio bajo la barra; vuelve la voz al hablarle. Se puede apagar.
- **Memory** = notas que toma cuando la corriges; se gestionan en Ajustes.
- **Vocabulary** = "the list of words Incredible should get right when you
  speak": nombres, jerga, "Say → write" (btw → By the way). Por defecto trae
  tu nombre, correo, dominio y contactos. Es el `keyterms` del oído.
- Dictado con niveles de limpieza (None/Light/Medium/High) y tono
  (Formal/Casual/Very casual); historial con "Copy what you said".
- Cuota: "Incredible pauses until it resets" al agotar el plan.

**Lo que confirma para Companion:** la voz y el texto comparten una sola
barra; el resultado siempre es una tarjeta con luz de estado; el vocabulario
es una función de usuario, no un detalle técnico; el silencio tras 10 min es
producto (nosotros ya tenemos el rollover de 5 min de 15a).

---

## 3. Qué hace Companion (medido en el código)

### 3.1 Opciones: 32 cambiables + 7 ocultas; necesarias para un hold: 4
| Bloque | Opciones | Necesarias | Técnicas |
|---|---|---|---|
| Tú | 4 | 0 | 0 |
| Voz | 7 (5 solo afectan manos libres, no el hold) | 0 | 5 |
| Apariencia | 5 | 0 | 0 |
| Hablar | 3 + permiso Accesibilidad | 1 (Accesibilidad) | 1 (tecla de dictado) |
| Contexto | 4 + 2 permisos | 0 | 4 |
| Sonido | 2 | 0 | 0 |
| Sistema | 1 ("Decidir en local") | 0 | 1 |
| Claves | 3 | 1 (una clave) | 3 |
| Cabecera | ejecutor, modo voz/texto, carpeta | 0 | 2 |
| Ocultas | `COMPANION_DECISION`, `voice.mode` (se guarda y nunca se lee), orden de proveedores, OpenRouter/Brave, `mcp.json`, 5 atajos no reasignables | | |

### 3.2 Primer arranque hoy: 6 pasos (nube) u 8–10 (local), 3 decisiones, 2 fuera de la app
1. Elegir "En tu Mac" o "Con OpenAI" (decisión 1). Local sin modelo = instalar
   Ollama y bajar un modelo **fuera de la app**.
2. Pegar clave OpenAI (se verifica).
3. Ventana principal: "Toca el orb de abajo para empezar a hablar" — eso abre
   manos libres, **no menciona FN**.
4. Accesibilidad: la bienvenida nunca la pide. La isla dice "FN está apagada.
   Clic para permitirla", pero el clic abre la ventana, no el permiso. Hay que
   encontrar Ajustes → App → HABLAR → "Pedir ahora".
5. Tecla globo de macOS → "No hacer nada": solo lo dice un subtítulo.
6. Primer hold: diálogo de micrófono (y de Reconocimiento de voz si no hay
   clave). Sin fila en la app para ninguno de los dos.

**La bienvenida cubre 1 de las 4 cosas necesarias.**

### 3.3 Cosas que no hacen nada o engañan
- "Velocidad", "Tono", "Fin de turno", "Paciencia", "Avidez", "Cancelación de
  eco": solo manos libres; el hold FN no los lee. El texto promete "aplican en
  tu próxima conversación".
- La voz elegida y la cancelación de eco se fijan al arrancar (requieren
  reiniciar, nadie lo dice).
- Accesibilidad aparece dos veces, y en HABLAR se titula "Deja que Companion
  vea tus documentos abiertos".
- Manos libres tiene 4 nombres: "Iniciar/terminar turno", "Atajo de manos
  libres", "Inicia o cuelga el turno de voz", "Hablar".
- Dos formas de hablar (FN y orb/⌘⌥Space) corren **dos tuberías distintas** con
  ajustes distintos; la UI no lo dice.
- Sin clave OpenAI: dictado y "Lo que se ve" se apagan en silencio.
- Errores de proveedor (clave inválida, límite) solo en rojo dentro del hilo;
  la isla no los muestra. La respuesta hablada tampoco se ve en la isla.
- Jerga en etiquetas: "Nativo", "el especialista", "Encargo", "TTS", "JPEG …
  modelo de voz", "Decidir en local vía Ollama".
- 8 cadenas muertas; menús y cabecera en español fijo aunque el idioma sea
  inglés; formatos de atajo inconsistentes ("⌘⌥Espacio" vs "Cmd+Opt+Space").

---

## 4. Principios que salen de la comparación

1. **La IA no es una preferencia.** El usuario elige *si* quiere nube o local,
   no proveedores, modelos ni routers. Los roles (oído, cerebro rápido, boca,
   vista) los fija el producto.
2. **Solo se configura lo que se entiende sin explicación:** micrófono,
   idioma, voz (nombre y muestra), atajos, sonidos, apariencia, privacidad.
3. **Lo obligatorio va en la bienvenida, con ilustración y botón**; nada
   obligatorio vive en Ajustes.
4. **Un solo camino para hablar.** FN es la app. Manos libres es una función
   secundaria con el mismo nombre en todas partes, o se retira hasta que
   comparta tubería.
5. **El estado se ve, no se lee.** Barras, brillo, transcript parcial; texto
   solo para lo que necesita palabras ("no te oí", errores con salida).
6. **Cada error dice qué pasó y qué hacer**, en la isla, no solo en el hilo.
7. **Tono:** segunda persona, frases cortas, sin jerga, admitir límites.

---

## 5. Propuesta: configuración fija con claves propias

Companion no tiene servidor, así que la "IA por defecto" son **claves del
usuario con roles fijos**. Propuesta de kit:

| Rol | Fijo a | Clave | Sin esa clave |
|---|---|---|---|
| Cerebro rápido (hold) | Cerebras gpt-oss-120b → Groq | Cerebras (recomendada) | cae a OpenAI |
| Oído final | Groq Whisper turbo | Groq (recomendada) | oído de Apple |
| Boca, vista, manos libres, chat escrito | OpenAI | **OpenAI (obligatoria)** | — |
| Local | Ollama si está instalado | — | — |

La bienvenida pide **una clave** (OpenAI) y ofrece un paso opcional "Hazlo más
rápido" con Cerebras y Groq (dos campos, una frase de por qué). Nada más de IA
aparece en la app. `Decidir en local`, el orden de proveedores, el picker de
ejecutor, los canales de contexto como tal, `voice.mode`, OpenRouter y Brave
**desaparecen de la UI** (quedan en `Config` para desarrollo).

### 5.1 Bienvenida propuesta (stepper, 7 pantallas, nada obligatorio fuera)
1. **Portada.** "Habla con tu Mac. Ella hace el resto." Un botón.
2. **Hola.** El orb saluda por voz mientras prepara (usa la voz de Apple si
   aún no hay clave). Nombre y, opcional, "cómo responder".
3. **Claves, las tres de frente** (decisión de Karen 2026-09-24): OpenAI
   (obligatoria: voz, vista, chat), Cerebras (cerebro rápido) y Groq (oído
   Whisper), cada una verificada en vivo con "¿Dónde la consigo?". Con solo
   una de las dos últimas la app funciona degradada: solo Groq → el cerebro
   choca con su límite gratuito de 8k tokens/min; solo Cerebras → el oído
   final es el de Apple. Por eso las dos son "recomendadas", no obligatorias.
4. **Permisos, una pantalla, 4 filas** con icono, estado y check: Micrófono ·
   Accesibilidad (tecla FN y escribir por ti) · Grabación de pantalla (ver lo
   que ves) · Reconocimiento de voz (solo sin clave). Cada fila tiene
   "Permitir" que abre el panel exacto; la app ya detecta el cambio.
5. **La tecla.** "Mantén FN para hablar." Si macOS tiene la tecla globo
   asignada, botón "Abrir Teclado en Ajustes del Sistema" con la instrucción de
   una línea. Alternativa: Opción derecha.
6. **Tu micrófono.** Selector + barra de nivel en vivo, y "Sube el volumen".
7. **Tu turno.** Pantalla oscurecida, glifo `fn`, "Mantén FN y di: *abre
   Safari*". La píldora muestra las barras; al soltar, la respuesta. No
   termina hasta que un hold funciona. "Saltar" arriba a la derecha.

Sin tour ilustrado en esta etapa: es lo más caro de Incredible y lo menos
necesario para que funcione. Queda como wave aparte si se quiere.

### 5.2 Ajustes propuestos (3 pestañas, ~14 opciones)
- **Tú:** nombre, foto, sobre ti, cómo responder. (igual que hoy)
- **Voz y teclas:** voz (nombre + escuchar), idioma, tecla para hablar (FN /
  Opción derecha), tecla de dictado (apagada / Command derecho), manos libres
  (atajo), micrófono, sonidos de interfaz.
- **Privacidad y sistema:** ver la pantalla (on/off), documentos abiertos
  (on/off), permisos con estado, claves (OpenAI · Cerebras · Groq, enmascaradas),
  apariencia (tema, tamaño, énfasis), buscar actualización, vaciar adjuntos.

Fuera: Velocidad, Tono, Fin de turno, Paciencia, Avidez, Cancelación de eco
(hasta que el hold los use), Decidir en local, ejecutor, portapapeles, carpeta
de trabajo en la cabecera (pasa a una pregunta cuando un encargo la necesite).

### 5.3 La isla como app (y estados)
Adoptar el modelo del notch: la isla es la superficie principal; la ventana
queda para historial largo y ajustes.

- **Reposo:** marca discreta (ya existe). **Hover:** se abre el panel: campo
  "Pídele algo a Companion…", adjuntar, enviar; icono de ajustes con menú de
  5: Ajustes · Abrir ventana · Atajos · Enviar comentario · Borrar historial.
- **Mantener FN:** solo barras de onda y anillo; transcript parcial debajo;
  sin "Escuchando…".
- **Pensando:** pulso, sin texto. **Hablando:** la frase que dice, en el panel.
- **Resultados:** tarjetas apiladas bajo el campo (título, una línea de datos,
  "Ver →"). Las tarjetas de 9e ya existen; falta que vivan aquí y que el
  prompt de voz apunte a ellas en vez de leerlas.
- **No te oí:** tarjeta que se cierra sola en 6 s; mic apagado (spec 15d-4).
- **Error:** una línea con salida ("Sin conexión.", "La clave de OpenAI no es
  válida. Abrir Claves"), en el panel.
- Desaparecen de la cabecera: ejecutor, modo voz/texto, carpeta de trabajo.

### 5.4 Texto y tono
- Reescribir las ~12 etiquetas con jerga (tabla en el informe de Companion §5).
- Un solo nombre para manos libres. Un solo formato de atajo.
- Menús y cabecera pasan por `Localized` (hoy español fijo).
- Prompt de voz: 2 frases, noticia primero, sin markdown (spec 15d-9).

---

## 6. Qué haría primero (orden propuesto)

| Orden | Wave | Qué resuelve |
|---|---|---|
| 1 | 15d (spec en borrador) | oír completo, boca rápida, mic apagado tras silencio, reglas de voz |
| 2 | 15e — Bienvenida y permisos | las 4 cosas obligatorias dentro de la app, con ilustración y botón |
| 3 | 15f — Ajustes fijos | quitar ~18 opciones, 3 pestañas, claves con verificación, textos sin jerga, i18n de menús |
| 4 | 15g — La isla como app | panel en hover con campo de texto, menú y resultados; respuesta visible; errores con salida; "no te oí" auto-cierre |

Cada una es una spec corta con criterio de done medible: pasos hasta el primer
hold (meta ≤ 5 y todos dentro de la app), opciones visibles (meta ≤ 15), cero
etiquetas técnicas, cero cadenas muertas.

---

## 7. Lo que falta para cerrar esta investigación

- Capturas de Incredible: **recibidas** (bienvenida, tour, píldora, widget del
  notch con menú y tarjeta de resultado). Falta solo la pantalla de Ajustes.
- **Los tres momentos de mayor confusión de Karen**, con sus palabras.
- Decisión tomada: tres claves de frente (§5.1). Orden de waves confirmado:
  oído (15d) primero, la interfaz al final.
