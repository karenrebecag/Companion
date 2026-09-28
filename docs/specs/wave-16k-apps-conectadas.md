# Wave 16k — Apps conectadas, como Incredible

**Estado: APROBADO (2026-09-25, "vamos"). 16k-0 CERRADA EN CÓDIGO (§7).** Karen: "ayúdame a trabajar en la sección de integraciones con
otras apps. Mira cómo funciona a totalidad en Incredible." Karen ya tiene cuenta y proyecto en
Pipedream. Evidencia: su grabación de las 19:11 (página Apps y Browser), sus capturas "Connecting
Slack" y "We use Pipedream to connect your account", dos investigaciones de la documentación
pública de Pipedream (§3) y los nombres de archivos de `~/.incredible` (sin abrir credenciales).

## 1. Cómo funciona en Incredible (observado)

**Página Apps** (barra lateral › Customize › Apps):
- Cabecera en tarjeta: "Apps" y "Every app you connect makes Incredible faster, more accurate, and
  able to do more.", con un collage de iconos (Notion, Excel, Slack, Docs, Teams, Sheets) y una esfera
  azul a la derecha.
- Buscador "Search for your apps" a todo el ancho.
- "Featured apps" con el total a la derecha ("1,700+ apps").
- Rejilla de dos columnas de tarjetas: icono en un cuadro redondeado, nombre, una línea de uso que
  termina casi siempre en "by talking" ("Draft replies, find a thread, and clear your inbox by
  talking."), y el botón gris "+ Connect".
- Orden de las destacadas: Teams, Slack, Excel, Gmail, Outlook Email, Google Calendar, Outlook
  Calendar, Google Drive, OneDrive, SharePoint, Google Sheets, Google Docs, Notion, Granola…; luego
  Asana, Trello, Stripe, Zendesk, GitHub, Zoom, Airtable, Dropbox, Google Forms, Todoist, Shopify,
  Intercom, ClickUp, monday, Calendly, Amazon SES, Klaviyo, WooCommerce, Snowflake, MongoDB, Apollo,
  Zoom Admin, Twilio, YouTube Data, Spotify, Typeform, Jotform.
- Abajo: "Show more (1,654 left)" y "Have your own MCP server? **Add it here**."

**Conectar** (capturas de Karen):
1. "+ Connect" abre un modal blanco: "Connecting Slack", los dos iconos (Incredible → Slack) unidos
   por una línea con un punto naranja que viaja, "We've opened Slack's sign-in page in your browser.
   Finish signing in there and this window updates on its own.", botón "Open it again" y la nota
   "Incredible only uses this connection for the things you ask it to do. Your data is never used to
   train a model."
2. En el navegador, la página de Pipedream: "We use Pipedream to connect your account", tres iconos
   (Incredible · Pipedream · Slack), "Connect securely" y "Connect instantly", los términos y
   "Continue". Luego el login de Slack.
3. Al terminar, una página local "You're connected — You can close this tab and head back to
   Incredible." (texto visible en la app) y el modal se actualiza solo.

**Usarla**: la voz busca la app y, si no está conectada, pone en la isla una tarjeta para conectarla
(en sus datos hay una herramienta que crea "connect cards"). Hay una lista de servidores MCP
permitidos (`mcp_allow_list`) y un ajuste de contexto de apps (`apps_context_enabled`).

**Lo que no se ve en ninguna grabación** (§6): cómo se ve una app ya conectada (¿"Connected"?,
¿menú para desconectar?), qué pasa si falla o se cancela, cómo es la tarjeta de conectar en la isla,
y el formulario de "Add it here".

## 2. Qué haría Companion (misma interacción)

1. Barra lateral: **Apps** entra en "Personalizar", como en Incredible.
2. Página Apps idéntica en estructura: cabecera, buscador, destacadas con total, rejilla de dos
   columnas, "Mostrar más (N restantes)", "¿Tienes tu propio servidor MCP? Añádelo aquí".
3. Conectar: modal "Conectando Slack" con la línea animada, "Abrir de nuevo" y la nota de
   privacidad; el navegador del sistema abre el enlace de Pipedream; la app pregunta cada pocos
   segundos hasta ver la cuenta y el modal pasa a "Conectado" solo.
4. Conectada: la tarjeta muestra "Conectada" y un menú con "Desconectar" (a confirmar con la
   grabación de §6).
5. Voz: la app conectada da herramientas al cerebro en los dos modos (clásico y realtime). Lo que
   escribe (enviar un Slack, crear un evento) pasa por la hoja de aprobación que ya existe; lo que
   solo lee, no. Si la app no está conectada, la isla muestra la tarjeta "Conectar Slack".
6. "Añádelo aquí": usa lo que ya existe (servidores MCP remotos de 9j-3) con un formulario de
   nombre y URL.

## 3. Arquitectura y seguridad (no negociable)

- **La clave secreta del proyecto de Pipedream nunca toca esta Mac**: ni en la app, ni en
  argumentos, variables de entorno, archivos ni logs. Vive solo como variable de la función.
- **Una función propia** (Vercel, equipo personal `karenrebecags-projects`, repo aparte; despliega
  Karen) con cuatro rutas, todas autenticadas con una clave de la app que vive en el Llavero:
  - `GET /apps?q=&cursor=`: el catálogo (nombre, slug, descripción, icono).
  - `POST /connect`: devuelve el enlace de conexión de una app para Karen.
  - `GET /accounts` y `DELETE /accounts/:id`: qué está conectado y desconectar.
  - `POST /tools` y `POST /tools/call`: listar y ejecutar las herramientas de una app conectada vía
    el MCP de Pipedream.
- Entorno `development` de Pipedream: gratis, hasta 10 usuarios, y exige estar conectada a
  pipedream.com en el navegador donde se conecta. Un solo usuario (Karen) por ahora.
- Hoy los servidores MCP de Companion solo funcionan en realtime (los ejecuta OpenAI). El hold
  clásico necesita su propio camino: las herramientas de la app entran como herramientas del padre
  (`ParentToolExecuting`) que llaman a `/tools/call`.
- Desconectar borra la cuenta en Pipedream y avisa de que el acceso se revoca también en la app
  (Slack, Google): Pipedream no lo hace.

### 3b. La API de Pipedream que usa la función (documentación pública, 2026-09-25)

- Catálogo: `GET /v1/connect/apps` con `q`, `limit`, cursor (`after`), `sort_key=featured_weight`,
  `has_actions`. Devuelve `name_slug`, `name`, `description`, `img_src`, `auth_type`, `categories`,
  `featured_weight`, `scope_profiles` y `page_info.total_count` (de ahí "1,700+"). Iconos en
  `pipedream.com/s.v0/app_<id>/logo/orig`.
- Conectar: `POST /v1/connect/tokens` con `external_user_id`, `success_redirect_uri`,
  `error_redirect_uri` y `webhook_uri`; devuelve `connect_link_url` (vale 4 h). Si un esquema
  `companion://` sirve como redirección no está documentado: se prueba en 16k-0 y, si no, se
  consulta hasta ver la cuenta.
- Cuentas: `GET /v1/connect/{project}/users/{external_user_id}/accounts` (con `healthy`, `dead`,
  `error`: una cuenta `dead` o no sana pide reconectar) y `DELETE /v1/connect/{project}/accounts/{id}`.
- Herramientas: MCP en `remote.mcp.pipedream.net/v3` con `x-pd-project-id`, `x-pd-environment`,
  `x-pd-external-user-id` y `x-pd-app-slug`; `tools/list` y `tools/call`, nombres `app-accion`. No
  hay filtro de "solo lectura": la función marca cada herramienta como lectura o escritura por su
  nombre y anotaciones, y la app pide aprobación para todo lo que no sea lectura clara.
- Sin documentar (se verifica en 16k-0 antes de depender de ello): el contenido del webhook, los
  esquemas propios en la redirección y la licencia de los logos.

## 4. Sesiones

1. **16k-0 Función** (repo aparte, Node/TypeScript en Vercel): las rutas de §3 con tests y la
   autenticación de la app. Instalar dependencias y desplegar son de Karen.
2. **16k-1 Página Apps**: catálogo, búsqueda, destacadas, estados por app. Sin la función configurada,
   la página explica cómo configurarla en vez de mostrar botones que no hacen nada.
3. **16k-2 Conectar y desconectar**: modal, enlace en el navegador, consulta hasta ver la cuenta,
   estado conectado, desconectar con confirmación.
4. **16k-3 Por voz**: herramientas de las apps conectadas en ambos modos, aprobación para las que
   escriben, tarjeta "Conectar X" en la isla cuando falta.
5. **16k-4 Tu propio MCP**: formulario "Añádelo aquí".

## 5. Riesgos

- El entorno `development` no sirve para otras personas; producción en Pipedream es de pago.
- Las herramientas de Pipedream pueden ser muchas por app: se filtran por la app que el pedido
  nombra, para no llenar el contexto del modelo.
- Los iconos de apps son marcas de terceros: se cargan de la URL del catálogo, no se copian al repo.

## 6. Lo que falta ver en Incredible

Una grabación de Karen haciendo en Incredible, de principio a fin:
1. Conectar Slack (u otra) hasta ver la app conectada en la página Apps.
2. Abrir el menú de esa app conectada (¿desconectar, ajustes?).
3. Pedirle algo por voz que use esa app (y ver la isla).
4. Pedirle algo de una app **no** conectada (para ver la tarjeta de conectar en la isla).
5. Abrir "Add it here".

## 7. Cierre de 16k-0 (2026-09-25)

Repo `~/Desktop/SoftwareDevProjects/companion-apps` (sin git: lo inicia y commitea Karen). Sin
dependencias: módulos ES de Node en Vercel, 21 tests con `node:test`. Rutas `apps`, `connect`,
`accounts` (GET/DELETE), `tools`, `call`; clave de la app comparada en tiempo constante; límite de
llamadas antes de la clave; errores solo como códigos; iconos solo de pipedream.com.

Revisiones:
- **Seguridad HIGH:** adivinar lectura/escritura por el nombre dejaba pasar escrituras. Ahora solo
  es lectura lo que el servidor marca como tal, y `/api/call` no ejecuta una escritura sin
  `approved: true` ni una herramienta que el servidor no liste.
- **Seguridad MEDIUM:** el cuerpo de la petición ahora tiene tope de 64 KB.
- **Seguridad LOW:** el límite de llamadas ahora va antes de la clave.
- **Código HIGH:** las cuentas llegan como lista directa (todas parecían desconectadas).
- **Código HIGH:** las respuestas MCP se emparejan por id entre notificaciones.

Todas con test.

Pendiente de Karen: variables en Vercel (README), desplegar, y la verificación en vivo de la lista
"Not yet verified" del README. Sigue 16k-1 (página Apps en Companion).

## 8. Cierre de 16k-1 (2026-09-25)

Barra lateral › Personalizar › **Apps**. La página: cabecera en tarjeta, buscador (espera 0,3 s al
teclear), "Apps destacadas" con el total, rejilla de dos columnas (icono, nombre, descripción,
"+ Conectar" / "Conectada" / "Volver a conectar"), "Mostrar más (N restantes)". "+ Conectar" abre
el Connect Link de Pipedream en el navegador; el modal, la consulta hasta ver la cuenta y
desconectar son 16k-2. Sin función configurada la página pide dirección (https, sin ruta) y clave
(la clave va al llavero, `COMPANION_APPS_KEY`; la dirección a `companion.apps.endpoint`).

Piezas: `CompanionCore/ConnectedApps.swift` (tipos, contrato, lectura estricta de la función),
`CompanionServices/HTTPAppsService.swift`, `CompanionUI/AppsModel.swift`, `CompanionUI/AppsPage.swift`;
ediciones mínimas en `MainSidebar`, `CompanionRootView`, `CompanionMain`, `Config` y los textos.

Revisiones (todas con test en rojo antes del arreglo):
- **Seguridad CRITICAL:** el cliente usaba la sesión compartida sin política de redirecciones: un
  302 a otro host se seguía con la clave en la cabecera. Ahora va por `URLSessionChatTransport`
  (misma política que el resto de la app). Comprobado que el test falla con el camino viejo.
- **Seguridad MEDIUM:** respuestas de más de 1 MB se rechazan antes de leerlas.
- **Código HIGH:** un Conectar fallido tapaba toda la página; ahora el fallo se dice en una línea
  y la rejilla sigue.
- **Código HIGH:** dos toques en "Mostrar más" duplicaban la página; ahora uno a la vez y el botón
  se apaga mientras carga.
- **Código MEDIUM:** volver a Apps perdía la búsqueda; la vista arranca con la del modelo (sin
  test: es estado de la vista).

Fuera de alcance, anotado: `OpenAITranscriber` usa la misma sesión sin política de redirecciones
(host fijo `api.openai.com`, riesgo menor); los iconos los carga `AsyncImage` con su propia caché.

Gates 0 fallos; instalada. Pendiente de Karen: desplegar `companion-apps`, pegar dirección y clave
en la página, probar en vivo, y la grabación de §6. Sigue 16k-2.

## 9. Spec 16k-2: conectores como Incredible (CERRADO 2026-09-28; D1/D2 auditadas contra el binario)

**Cierre**: 16k-2a/2b/2c construidas test-first, doble review por sesión (hallazgos corregidos
vía tdd-guide: carrera del spinner, epoch de intentos de conexión, guard del doble DELETE),
gates 0 fallos, 471 tests. Desviaciones: la ruta real de borrar es `DELETE /api/accounts?id=`
(query, no path); el panel sin conectar muestra solo la descripción (auditoría §9.6), así que
no hizo falta `/api/tools` sin cuenta; la función hoy solo manda `read|write` — el grupo
Borrar queda cableado para cuando declare `destructive`. Deuda anotada: extraer el flujo de
conexión de `AppsModel` (435 líneas) a un colaborador `ConnectFlow` (nota LOW del review).
Falta el E2E en vivo de Karen con la función desplegada.

Rama `feat/16k-2-conectores`, worktree `../companion-next-16k2` (la otra sesión sigue en la carpeta
principal sin pisarse). Karen: "replicar la UI de los conectores de Incredible sobre Companion".

### 9.1 Lo observado (nuevo desde §1)

Fuente: documentación pública `incredible.one/learn?section=app-connectors` (2026-09-28), más las
capturas de §1. Solo comportamiento y textos visibles.
- **Tocar una app abre su panel**: nombre, qué puede hacer agrupado en **Read** (solo mirar),
  **Create and change** (redactar, enviar) y **Delete** (borrar, siempre con confirmación), y el
  botón **"Connect Gmail"** (con el nombre de la app). Nota: "Incredible works with a partner
  service called Pipedream to power its app connections".
- **Conectar**: el modal "Connecting Slack" de §1 (dos iconos, línea con punto que viaja, "Open it
  again", nota de privacidad); al terminar en el navegador se vuelve y se pulsa **"Let's go"**.
- **La página Apps muestra primero tus apps conectadas** y debajo el catálogo.
- **Desconectar** está en el panel de la app: "Your account isn't touched, and you can reconnect
  anytime." Gmail y Outlook tienen además "Settings" (firma de correo).
- Etiqueta **Beta** en conexiones nuevas.

### 9.2 Qué hace Companion

1. **Panel de la app** (hoja sobre la ventana, como la de tareas): icono, nombre, descripción,
   botón "Conectar Slack", y las acciones de la app en tres grupos: **Leer**, **Crear y cambiar**,
   **Borrar**. El grupo sale de lo que el servidor declara (`readOnlyHint` → Leer,
   `destructiveHint` → Borrar, el resto → Crear y cambiar); sin declaración cae en Crear y cambiar,
   nunca en Leer. Nota de Pipedream y la de privacidad.
2. **Modal "Conectando Slack"**: los dos iconos (Companion → app) unidos por una línea con un punto
   que viaja (reducir movimiento: punto quieto), "Abrimos el inicio de sesión de Slack en tu
   navegador. Termina ahí y esta ventana se actualiza sola.", "Abrir de nuevo", nota de
   privacidad. La app consulta `/api/accounts` cada 3 s mientras el modal está abierto (tope 10
   min, luego "¿No terminó? Abrir de nuevo"). Cuando aparece la cuenta: "Slack conectado" y
   **"Vamos"**, que cierra el modal y deja el panel en estado conectado.
3. **Página**: sección "Tus apps" arriba con las conectadas (y las que piden volver a conectar),
   catálogo debajo sin repetirlas.
4. **Conectada**: en el panel, "Conectada" con la cuenta si la hay, y **"Desconectar"** con
   confirmación: "Companion deja de usar Slack. Tu cuenta de Slack no cambia y puedes volver a
   conectarla cuando quieras." Llama a `DELETE /api/accounts`, que ya existe y comprueba que la
   cuenta es tuya.
5. **Fuera de 16k-2**: "Settings" de firma (no hay dato), etiqueta Beta (Pipedream no la da), la
   tarjeta "Conectar" en la isla y usar las apps por voz (16k-3), "Añádelo aquí" (16k-4).

### 9.3 Piezas

- Core `ConnectedApps.swift`: `AppAction` (nombre, grupo), lectura de `/api/tools`,
  `ConnectPoll` puro (intervalo, tope, cuándo parar) con tests.
- Services `HTTPAppsService.swift`: `tools(app:)`, `disconnect(account:)`.
- UI nuevos: `AppPanel.swift` (panel), `ConnectingSheet.swift` (modal); `AppsModel` gana
  `connecting`, `poll()`, `disconnect()`, `actions(of:)`; `AppsPage` gana "Tus apps" y abre el
  panel al tocar una tarjeta. Textos es/en.
- Función `companion-apps`: `/api/tools` hoy exige app conectada. Si Pipedream lista herramientas
  sin cuenta, el panel muestra las acciones antes de conectar (como Incredible); si no, antes de
  conectar muestra solo la descripción. Se prueba en vivo en la primera sesión, antes de depender
  de ello. Cambios en la función: test primero, despliegue con tu OK.

### 9.4 Sesiones

- **16k-2a**: panel de la app + acciones agrupadas (+ la prueba en vivo de `/api/tools` sin cuenta).
- **16k-2b**: modal de conexión con consulta y "Vamos".
- **16k-2c**: "Tus apps" arriba, desconectar con confirmación, volver a conectar.

Cada una: tests en rojo primero, gates verdes, code-reviewer + security-reviewer, instalar, docs.

### 9.5 Decisiones (auditadas contra el binario, 2026-09-28)

- **D1 RESUELTA — hoja/diálogo, confirmado**: Karen eligió hoja y el código real de Incredible
  hace exactamente eso: `connector-detail-dialog` con `aria-modal`, backdrop negro al 40 %,
  X de cierre arriba a la derecha, tamaño `max 1000×700 px` (86 vh máx). Dos columnas a partir
  de 880 px: izquierda 430 px (icono 44 px, nombre, estado, Desconectar, Website), derecha con
  scroll propio para las acciones. Nunca navega a otra página.
- **D2 AJUSTADA — cada 3 s sí; el tope real es ~2 min, no 10**: constantes del binario:
  intervalo `3e3` (3 s), máximo `40` intentos (~2 min) y un timeout global duro de `15e4`
  (2.5 min) que corre desde `initiating`. Al agotarse: "no terminó" con **Reintentar** y
  **Abrir de nuevo** (el enlace de Pipedream vale 4 h, así que reintentar es barato). Companion
  adopta los números de Incredible: 3 s × 40 intentos + timeout global de 2.5 min.

### 9.6 Auditoría del binario (2026-09-28, solo lectura)

Método: assets del frontend extraídos del binario Tauri (slice arm64, mapa phf con punteros
chained-fixup, brotli), 1607 archivos; grep sobre `main-*.js` y `firstRun-*.js`. Solo se leyó
código de UI; jamás `auth.json` ni `bridge-secret`. Hechos nuevos que cierran huecos de §6:

- **Máquina del intento** (una función pura, como el `ConnectPoll` planeado): fases
  `initiating → waiting(attempts) → complete | timed_out | failed`. `initiating` muestra
  "Opening your browser…" (o "macOS is asking for permission…" si la app es de tipo `device`).
  Si `initiateConnection` no trae `redirect_url` pero la cuenta ya está `ACTIVE`, salta directo
  a `complete`. Con `waiting` y varios intentos, aparece el hint "Still waiting on the browser.
  If nothing came up, open the link again."
- **Título del modal por fase**: "Connecting X" → "X is connected" / "X didn't finish
  connecting" / "Couldn't connect X". En `complete`: palomita sobre la línea animada, copy
  "You're all set…" y botón "Let's go".
- **Grupos de acciones**: el servidor declara `gravity` = `Read` | `Write` | `Destructive`; la UI
  solo agrupa (nada de adivinar por nombre — valida el diseño de la función 16k-0). Notas
  exactas: Read "Only reads. Nothing in the app changes."; Create and change "Changes something
  in the app. Incredible shows you what before it does."; Delete "Removes something. Incredible
  always asks first." Orden alfabético dentro de cada grupo y un buscador "Search N actions"
  dentro del panel.
- **Sin conectar, el panel NO lista acciones**: estado vacío "Connect X to see everything it can
  do."; conectada pero sin lista: "X didn't list any actions just now. Try Check, or reconnect
  it." (esto responde la duda de §9.3: no hace falta `/api/tools` sin cuenta para la paridad).
- **Desconectar**: botón fantasma "Disconnect X" con spinner "Disconnecting…"; los servidores
  MCP propios usan "Remove" (tono peligro) y muestran salud (punto de color + host).
- **Ajuste por app** visto en el panel: toggle "Run look-ups without asking" (lecturas sin
  aprobación) — dato útil para 16k-3.
- **Conectores nativos además de Pipedream**: apps con `auth_method` `api_key`/`basic` abren un
  formulario local (Username/Password o API key). Fuera de alcance de 16k-2; anotado.
