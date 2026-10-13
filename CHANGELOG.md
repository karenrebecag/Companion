# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es/1.1.0/). Una
entrada por wave cerrada; sin releases versionados hasta Wave 5.

## [Unreleased]

### Fixed
- **El hilo de la isla ya no desvanece el mensaje de arriba sin motivo (2026-10-12).** El borde superior solo se difumina cuando hay mensajes más arriba a los que puedes subir; en reposo el mensaje más viejo se lee completo.
- **Probado en vivo que la voz en tiempo real puede cambiar de velocidad (2026-10-01).** Una
  prueba contra el servicio real confirmo que acelera y frena entre respuestas. Tambien encontro
  un problema escondido: ciertas velocidades, como 0.8, se mandaban con demasiados decimales y el
  servicio rechazaba la configuracion completa de la voz. La velocidad ya no se cambia desde Ajustes,
  asi que hoy no pasaba, pero queda anotado y se corrige con esta funcion.
- **Las manos y la vista dicen que permiso o estado les falta al actuar (2026-10-02).** Con la Mac
  bloqueada, manos, vista y aperturas (`open_app`, `open_url`, `open_file`) se niegan antes de actuar
  (`screen_locked`); si se bloquea a mitad de una accion, dicen que el resultado es desconocido, y una
  captura de `see` que choca con el bloqueo se descarta. `see` sin Grabacion de pantalla responde
  `screen_recording_required` con la ruta en Ajustes del Sistema, y una ventana que no se quedo
  delante responde `foreground_unavailable`.
- **Si interrumpes a Companion mientras espera tu permiso, ya no hace nada después (2026-10-01).**
  Cuando Companion pedía permiso (por ejemplo, para abrir una página que no dijiste) y tú lo
  interrumpías, un "sí" que llegara justo después todavía podía hacerlo, y la tarjeta se quedaba
  en pantalla sin servir para nada. Ahora, al interrumpir, la tarjeta desaparece, no se hace nada
  y la isla te dice por qué: "Me detuve sin hacerlo". Pasa igual al cerrar la sesión de voz en
  tiempo real.
- **Un clic tardío ya no puede contestar un permiso distinto (2026-10-03).** Si un clic llegaba
  tarde a la hoja de permiso de una petición y, mientras tanto, ya había aparecido otra, ese
  clic podía aprobar o negar la nueva sin que la hubieras visto. Ahora cada respuesta lleva el
  identificador de la petición que estabas viendo; si ya no es la pendiente, se ignora y queda
  una línea en el registro. La espera de 0,6 s antes de poder responder se conserva.
- **La direccion de Apps acepta el esquema en mayusculas (2026-10-03).**
  "HTTPS://..." (pegado o con autocapitalizacion) se rechazaba como direccion invalida aunque es https.
  Ahora el esquema se compara sin distinguir mayusculas y se guarda en minusculas; "HTTP://" sigue
  rechazado porque la clave nunca viaja sin cifrar.
- **Una clave o direccion equivocada ya no borra la configuracion de Apps que funcionaba (2026-10-03).**
  Antes, al guardar, la clave nueva iba al llavero y la direccion a las preferencias antes de que la
  funcion respondiera, asi que un error de tipeo desconectaba Apps sin vuelta atras. Ahora, si ya habia
  una configuracion (o una clave guardada para esa direccion), la funcion tiene que aceptar la nueva primero; si la rechaza, no responde o esta
  caida, se conserva la anterior y el formulario dice por que. Mientras se comprueba, Guardar queda
  bloqueado, y una respuesta tardia de la funcion anterior ya no se pinta sobre la nueva. La primera
  configuracion se guarda como antes.
- **Una busqueda escrita mientras Apps carga ya no se pierde (2026-10-03).**
  Si se escribia en el buscador antes de que terminara la primera carga del catalogo, la carga llegaba
  despues y reemplazaba la lista filtrada por el catalogo completo, con la busqueda todavia escrita. La
  carga ahora recuerda que se pidio y no pinta si la busqueda cambio mientras esperaba.
- **Sin permiso de Automatizacion, la hoja de calculo responde `permission_required` (2026-10-03).** Como
  Incredible, un permiso de privacidad que no es Accesibilidad ni Grabacion de pantalla usa un solo
  codigo, `permission_required`, con la ruta exacta: activar la app bajo Companion en Ajustes del
  Sistema > Privacidad y seguridad > Automatizacion. El codigo entra en la lista permitida del puente.
- 2026-10-06: Companion ya no se cierra cuando el puntero pasa sobre la isla mientras escucha; la prueba de accesibilidad fuera del hilo principal no toca la UI.
- **Los tests de UI vuelven a compilar en main (2026-10-02).** El helper de colores de los tests de la
  etiqueta chocaba por nombre con el de los tests de botones y rompía la compilación de la suite.
- **Borrar el historial ya no deja reanudar las tareas borradas (2026-10-04).** Borrar el
  historial de chats, desde Ajustes o desde el menu de la isla, ahora borra tambien las
  sesiones de los especialistas, cierra el proceso de Claude Code que seguia abierto y olvida
  la sesion que guardaba en memoria. Una tarea que termina despues del borrado ya no puede
  volver a escribir su sesion. La isla pide confirmacion y hace el mismo borrado real que
  Ajustes, como en Incredible. El texto aclara que Claude Code y Hermes guardan su propio
  historial.
- **El puente rechaza por nombre un argumento mal escrito o fuera de medida (2026-10-03).**
  Companion declara en el hello los limites de cada argumento (texto de 1 a 16000 bytes UTF-8 en
  `type_text` y `browser_type`, direcciones validas de `scroll`) y los vuelve a comprobar al recibir
  la llamada. Un cliente que no pase por el shim recibe `invalid_args` con el argumento exacto, sin
  gastar presupuesto ni abrir la hoja de aprobacion.
- **Cada rechazo del bridge dice que hacer despues (2026-10-02).** `rate_limited` dice cuantos
  segundos esperar, `cooling_down` cuanto falta, una hoja abierta ya no se confunde con otro agente,
  el turno de voz tiene su propio codigo `paused` en vez de un `busy` falso, `needs_accessibility`
  nombra la ruta en Ajustes del Sistema y `target_changed` pide volver a mirar.
- **Una respuesta larga del puente ya no se pierde entera (2026-10-03).**
  Companion no limitaba el tamano de lo que devolvia una herramienta, y una salida de mas de 64 KB
  hacia que el shim cortara la conexion. Ahora la salida se recorta a 24000 bytes UTF-8 sin partir
  caracteres y termina con una nota que dice que el resultado es parcial y pide acotar la consulta.
- **Tras negar o dejar caducar la hoja de las manos, el agente sabe como volver (2026-10-02).** `session_closed`
  ya no dice solo "session is closed": explica que la sesion la cerro una negativa, una hoja caducada o "Detener
  manos", y que un hello nuevo vuelve a preguntar con otra hoja en la Mac.
- **Los tests del puente ya no tumban toda la corrida con SIGPIPE (2026-10-01).** CI moria
  sin resumen dentro de las suites del puente: los clientes de prueba escribian a un socket
  que el servidor ya habia cerrado, sin nada que convirtiera la senal en un EPIPE. Ahora
  cada cliente de prueba protege su socket, y la conexion del puente protege el suyo al
  construirse, no solo al aceptarse. La app ya estaba protegida en el camino real. Brief
  `docs/research/bridge-sigpipe.md`.
- **El bridge ya no entrega caracteres invisibles al agente (2026-10-02).** Lo que devuelve una tool
  es texto de pantalla que una pagina o un mensaje pueden escribir; los caracteres de etiqueta, bidi,
  ancho cero y controles se quitan antes de salir de Companion, para que el agente lea lo mismo que
  ve la persona. Los saltos de linea y tabuladores se conservan.
- **Un clic que no se puede confirmar ya no se reporta como pulsado (2026-10-05).** Si la página
  no veía la pulsación aterrizar en el elemento (por un overlay, por un control que se movió, o
  porque el clic se perdió), la extensión decía igualmente "clicked" o seguía tecleando. Ahora el
  clic, el doble clic y el clic derecho avisan al asistente de que la pulsación no se pudo
  confirmar y le piden volver a leer la pestaña antes de actuar, sin repetir el clic a ciegas;
  `browser_type` ni siquiera teclea si la pulsación no se confirmó (sería peor mandar las teclas
  al campo equivocado) y devuelve el error `press_unconfirmed`.
- **Los errores del navegador dicen qué hacer después (2026-10-03).**
  Cuando la persona cancelaba el control de la pestaña, el modelo solo leía "el navegador falló" y
  volvía a intentar. Ahora `debugger_revoked`, `debugger_unavailable`, `unreadable_page` y
  `not_typable` llegan con su propio texto en español e inglés (no reintentar y preguntar, cerrar las
  herramientas de desarrollo, avisar que la página no se puede leer, elegir otro elemento), y leer una
  pestaña que ya no existe libera el control de esa pestaña.
- **Leer un menu abierto en el navegador ya no devuelve una pagina vacia (2026-10-02).** `browser_read` con
  un selector como `[role=menu]` trae las opciones del menu; si nada coincide o todo esta oculto falla con
  `selector_no_match` o `selector_hidden` y un texto que dice que hacer: abrir el menu o leer sin selector.
- **Leer una página larga ya no pierde el menú o diálogo que se acaba de abrir (2026-10-03).**
  Los menús, diálogos y popovers se montan al final de la página, y el recorte de una lectura larga
  conservaba lo primero: en una página con cientos de enlaces, el menú abierto era justo lo que se
  perdía y el modelo concluía que no se había abierto. Ahora sus elementos y su texto van primero, y
  el aviso de recorte dice cómo llegar a lo que falta: volver a leer con un selector para esa parte.
- **Pulsar un elemento que se ocultó después de leer la página ya no responde "pulsado" (2026-10-03).**
  Si un menú se cerraba entre la lectura y el clic, sus opciones seguían numeradas: el clic real no
  encontraba dónde caer y la extensión pulsaba el nodo oculto por código, así que el modelo creía
  haber pulsado algo que la persona no ve. Ahora pulsar o escribir en un elemento oculto se rechaza
  y el modelo recibe que debe volver a leer la pestaña.
- **El navegador ya no pulsa un elemento que cambió desde la lectura (2026-10-03).**
  Entre leer la página y pulsar, una página podía reutilizar el mismo nodo con otro texto (de
  "Siguiente" a "Eliminar cuenta") y el clic se hacía sin hoja de aprobación. Ahora la extensión
  recuerda el rol, la etiqueta, el diálogo o formulario que lo contiene y el enlace de cada elemento leído y, si cambiaron, responde
  `stale_id` para que se vuelva a leer antes de actuar. Vale para clic y escritura, también dentro de
  iframes.
- **Pulsar dentro de un iframe ya no atraviesa lo que lo tapa (2026-10-03).**
  Dentro de iframes, y cuando el clic real no encontraba dónde caer, la extensión pulsaba el
  elemento por código sin mirar si un diálogo, un banner o una capa lo cubría, así que se pulsaba
  algo que la persona no podía ver. Ahora ese clic comprueba primero qué hay encima del elemento, en
  su propio iframe y en la página que lo contiene, y si algo lo tapa se rechaza y el modelo vuelve a
  leer la pestaña.
- **Escribir en el navegador ya no pierde los saltos de línea sin avisar (2026-10-03).**
  El tecleo tecla por tecla no puede enviar saltos de línea, y el host descartaba el aviso de la
  extensión, así que un correo de tres párrafos quedaba en uno y el modelo decía "escrito". Ahora el
  texto con saltos entra completo en un `textarea` en una sola inserción, comprobada al releer el
  campo. Si el campo no los conserva, el modelo recibe que el texto quedó en una línea y que debe
  avisar a la persona.
- **Abrir o navegar una pestaña ya espera a que la página cargue (2026-10-03).**
  `browser_open` y `browser_navigate` respondían antes de que la página cargara, así que una lectura
  inmediata veía una página vacía o la anterior y el modelo concluía que estaba vacía. Ahora, como
  Incredible, esperan a que cargue con un tope de cinco segundos; si se agota, el modelo recibe que
  la página sigue cargando y que espere un momento antes de leerla.
- **El test del chip de voz usa una tarjeta con datos reales (2026-10-06).** Su tarjeta de ejemplo quedó vieja cuando la isla empezó a mostrar resultados solo para respuestas que traen datos (#248), y main fallaba ese test en cada corrida.
- **Un especialista que se cae entre encargos ya no tumba la app (2026-10-01).** Si el CLI
  delegado moria entre dos encargos, mandarle el siguiente mataba Companion entera con
  SIGPIPE en vez de fallar y reintentar con un proceso nuevo, que es lo que el ejecutor ya
  esperaba. Ahora la entrada del especialista esta protegida y esa escritura falla como un
  error normal. Brief `docs/research/bridge-sigpipe.md`, opcion F.
- **La respuesta cortada por la red queda siempre antes del turno que la sigue (2026-10-01).**
  Si el usuario hablaba justo mientras la respuesta cortada entraba al hilo, su turno
  podia quedar arriba de ella. Ahora el turno espera a que esa respuesta termine de
  entrar. Brief `docs/research/drain-racing-orden-del-corte.md`.
- **Vaciar la papelera sin permiso de Automatización ya dice dónde activarlo (2026-10-03).** Si Finder
  rechazaba la orden porque Companion no tiene Automatización (error -1743 de macOS), el "sí" de la
  confirmación caía al modelo sin contexto, y si la respuesta específica no estaba en caché se oía
  "Listo." aunque la papelera seguía llena. Ahora Companion dice que no tiene permiso para controlar
  Finder y que se activa en Ajustes del Sistema, Privacidad y seguridad, Automatización, en el
  interruptor de Finder debajo de Companion. Ningún fallo de una acción del router vuelve a sonar a
  "Listo.".
- **Los colores de la app son los de su referencia (2026-10-03).** Cada color de la paleta se
  construía en un espacio de color genérico en lugar de sRGB, así que todo se pintaba un poco más
  claro y desviado que el valor que cita (Incredible, Tailwind, los colores del sistema): el gris
  de texto #727276 salía como #858589 y el fondo oscuro #1A1A1A como #232323. Ahora cada color se
  ve exactamente como su hex.
- **La tarjeta "Mantén fn" del inicio ya no parte el título letra por letra (2026-10-06).** El orbe le quitaba el ancho al texto; el título va en una línea y el texto tiene prioridad sobre el espacio.
- **Mientras actua, la isla dice "Pensando" y no nombra la app (2026-10-02).** Antes la linea decia
  "Abriendo Safari" con una pastilla por app, repitiendo lo que ya muestra el carrete de abajo. Ahora
  la app vive solo en el carrete, y pasar de pensar a actuar no hace salir y volver a entrar la misma
  palabra.
- **El carrete muestra la app donde Companion actua ahora (2026-10-03).** Si un turno volvia a una
  app ya tocada (Safari, Notas, Safari), el carrete se quedaba en Notas. Ahora la app repetida pasa
  al final y el carrete muestra Safari.
- **El carrete de apps tocadas muestra una sola, la ultima (2026-10-02).** Antes pintaba una
  pastilla por cada app tocada, vacias incluidas. Ahora muestra solo la ultima app con nombre y el
  cambio entra con el ritmo de Incredible.
- **VoiceOver lee la app del carrete (2026-10-03).** Desde que la linea dice "Pensando" al actuar,
  el carrete es el unico lugar que nombra la app, pero VoiceOver solo leia "Apps tocadas en este
  turno". Ahora lee ese nombre y despues la app.
- **El hilo de la isla se lee parejo (2026-10-12).** Las respuestas de Companion ya no tienen el interlineado casi doble frente a tus mensajes, y el hilo deja un respiro bajo el campo en vez de pegar el mensaje más viejo al borde.
- **La isla ya no dibuja barras vacías mientras Companion trabaja (2026-10-02).** Cuando Companion
  miraba o pulsaba algo en otra app, aparecía un chip sin texto que se estiraba como una barra. Ahora
  solo se muestran los chips con nombre, y cada uno mide lo que su texto.
- **Los encargos ya no muestran nombres internos (2026-10-12).** Los pasos como "ToolSearch: select:WebSearch" dejan de aparecer y las herramientas desconocidas se leen como una frase corta en vez de su nombre.
- **El hilo de la isla ya no muestra markdown crudo (2026-10-12).** Las viñetas de una respuesta salen una por línea en vez de pegadas en un párrafo, y la lista de fuentes con enlaces se convierte en chips como en la tarjeta de resultado.
- **Menos negro vacío en la isla (2026-10-12).** La tarjeta de resultado pega su cabecera justo bajo la banda del notch, y el hilo del panel con el cursor encima toma el alto de su contenido en vez de dejar unos 250 pt vacíos entre el campo y el primer mensaje.
- **Los chips de la tarjeta se leen como persona (2026-10-12).** Una dirección aparece como "google.com" en vez de la URL completa y las apps de macOS salen con su nombre en el idioma de la app ("Notas" en vez de "Notes").
- **La isla ya se cierra sola aunque un agente este usando tus manos (2026-10-12).** Mientras una sesion del puente estaba abierta, la isla se quedaba con el panel y el chat desplegados y no se cerraba al quitar el mouse. Ahora en reposo vuelve a su tamano normal; el aura de pantalla sigue avisando que las manos estan prestadas.
- **La respuesta de la tarjeta de la isla se lee igual que en el hilo (2026-10-12).** Antes la tarjeta "Listo" pintaba la respuesta en 16 pt con 4 de interlineado y el hilo en 13 pt con 3; ahora las dos usan el mismo escalon e interlineado.
- **La isla ya no muestra los tres circulos punteados sin un encargo (2026-10-02).** Las ranuras
  de tareas se dibujaban siempre arriba a la derecha, aunque no hubiera nada corriendo, y se leian
  como piezas vacias. Ahora aparecen solo mientras corre un encargo, como en Incredible.
- **La isla muestra la respuesta entera, no solo su principio (2026-10-02).** Antes cortaba la
  respuesta en el primer párrafo o a mitad de palabra con "…". Ahora muestra todos sus párrafos,
  hasta sus últimas 600 palabras, y si no caben se desplaza dentro de la isla.
- 2026-10-13: «Seguir en el chat» (y tocar el documento) trae la ventana del chat al frente; antes se quedaba detrás de la app activa y el toque abría un popup con el mismo texto.
- **La isla ya no escribe "Hablando" mientras responde en voz (2026-10-02).** El orbe y la voz ya
  lo dicen, y la etiqueta sobraba al lado. VoiceOver la sigue leyendo: en la fila de estado como un
  elemento que no ocupa lugar y, con el campo abierto, como valor del orbe.
- **Subtitulos de la isla con espacio entre frases y "Pensando" legible (2026-10-12).** Una frase que terminaba en comilla de cierre y punto (`tty??”.`, `5b”.`) se pegaba a la siguiente (`Es la ventana`, `¿Qué deseas`); ahora lleva su espacio, sin tocar decimales ni dominios. El "Pensando…" de la isla se apagaba hasta casi desaparecer en el barrido del shimmer; ahora su punto mas tenue sigue cumpliendo contraste AA sobre el negro de la isla.
- **Las tarjetas "Ver →" de la isla salen solo para respuestas con resultado (2026-10-02).** Antes
  cada respuesta anterior se apilaba como tarjeta aunque fuera solo texto. Ahora solo la trae una
  respuesta con una tarjeta de datos; una tarjeta mostrada por su propio canal, que antes nunca
  salia, ahora si sale.
- **El objetivo de las manos es la ventana, no la app que está al frente (2026-10-05).** Desde la terminal, Companion sólo sigue actuando en una app que ya hayas mirado con `look`; si la app cambió, la ventana cambió, o el pid se recicló a otro bundle, la llamada se rechaza con `target_lost` y hay que volver a `look` o usar `focus_window` para re-pinear. La app no se inventa un destino: la pides tú o se acabó.
- **Las manos ya no escriben ni leen en un navegador sin la extension de Companion (2026-10-05).**
  Una web en un navegador Chromium era un blanco para `type_text` y `read_focused`:
  Accessibility devuelve exito y el campo lo ignora, asi que el agente creia haber escrito.
  Para los navegadores que Companion aun no hostea (Brave, Edge, Opera, Arc, Vivaldi,
  Chromium, y los canales beta/dev/canary de Chrome y Edge) las dos herramientas devuelven
  `browser_unsupported` y el mensaje dice que no se reintente ahi. Para Chrome y Comet sin
  la extension cargada devuelven `browser_not_connected` y el mensaje nombra al navegador
  y dice que se cargue la extension y se arranque con `browser_tabs`. Con la extension
  cargada pero apuntando a otro navegador devuelven `browser_not_connected` con el nombre
  del navegador conectado y la regla de "un navegador a la vez". Con la extension cargada
  en ese mismo navegador devuelven `use_browser_tools` y apuntan a `browser_tabs` seguido
  de `browser_type` / `browser_read`. Las apps nativas y Safari no cambian.
- **Escribir en una app nativa dice si el texto entro (2026-10-05).** Despues de escribir, Companion
  relee el campo; si la app ignoro el texto lo pega una vez y vuelve a leer, y si sigue sin entrar
  lo dice en vez de contar letras que no llegaron.
- **Un campo de texto vacío ya no se confunde con "no hay campo" (2026-10-05).** Cuando Companion leía el campo enfocado y estaba vacío, respondía "no hay campo" aunque el clic hubiera sido correcto, y al escribir no tenía con qué comparar para saber si el texto llegó. Ahora un campo editable vacío se reporta como "(empty field)" para que sepas que está ahí y vacío, y al escribir sobre uno vacío Companion ya puede confirmar que el texto entró.
- **Abrir y navegar ya no piden permiso (2026-10-12).** Companion pedia una hoja "Abrir www.google.com" hasta para buscar el clima. Ahora abrir una pagina http(s) o una URL, y navegar a otro sitio, ocurren sin hoja. Las hojas se quedan donde hay consecuencia: enviar un formulario, borrar, pagar, subir archivos, comandos de shell, clics por pixeles y las peticiones de otras apps por el puente MCP.
- **Los números de elemento del navegador ya no caducan con cada lectura (2026-10-05).** Companion guarda
  las últimas 20 lecturas de cada pestaña, así que un número visto en una lectura reciente sigue sirviendo
  mientras el elemento siga en la página y sin cambios; una lectura lenta que termina tarde ya no invalida
  los números de la más nueva, un marco oculto (como un video embebido) ya no llena la lectura con código
  de la página, y cada `stale_id` queda en el registro con el motivo exacto del rechazo.
- **La lectura del navegador ya no ofrece controles escondidos por un contenedor (2026-10-02).**
  Antes solo se miraba el estilo del propio elemento, asi que un boton dentro de un bloque oculto
  o de un `details` cerrado le llegaba al modelo como si se pudiera pulsar. Ahora se usa la
  visibilidad real del navegador (`checkVisibility`).
- **Si interrumpes a Companion mientras espera tu permiso, ya no hace nada después (2026-10-01).**
  Cuando Companion pedía permiso (por ejemplo, para abrir una página que no dijiste) y tú lo
  interrumpías, un "sí" que llegara justo después todavía podía hacerlo, y la tarjeta se quedaba
  en pantalla sin servir para nada. Ahora, al interrumpir, la tarjeta desaparece, no se hace nada
  y la isla te dice por qué: "Me detuve sin hacerlo". Pasa igual al cerrar la sesión de voz en
  tiempo real.
- **En la voz en tiempo real, hablarle encima a Companion también retira la tarjeta de permiso
  (2026-10-01).** Si Companion estaba hablando y esperaba tu permiso, y tú le hablabas encima o
  le decías que parara, un "sí" posterior todavía hacía la acción y Companion volvía a hablar
  encima de ti. Ahora la tarjeta desaparece, no se hace nada, la isla dice "Me detuve sin
  hacerlo" y Companion te escucha.
- **La app ya no dibuja cuando nadie la ve (2026-10-13).** El orbe de voz respira
  incluso en reposo y redibujaba a 60-120 fps aunque la ventana estuviera oculta,
  minimizada o tapada: ahora la ventana avisa cuando sale de pantalla y los orbes
  (voz, pensando) y el brillo de texto se detienen hasta que vuelve. La pila de
  avisos dejaba un reloj de dos ticks por segundo encendido sin avisos y repintaba
  aunque nada caducara; ahora duerme. La animación visible no cambia.
- **`see` ya no confunde un permiso roto con un fallo de vision (2026-10-03).**
  Las manos leian solo el interruptor de Grabacion de pantalla, que puede seguir encendido aunque
  toda captura falle. Ahora leen el estado verificado: sin permiso rechazan antes de capturar, y una
  captura vacia sin permiso verificado responde `screen_recording_required` con el panel exacto,
  en lugar del ambiguo `no_capture`.
- **Aviso de permiso cuando se pierde Grabacion de pantalla (2026-10-03).** Si la vista funcionaba y
  deja de poder capturar (permiso revocado o roto hasta relanzar), la isla muestra una tarjeta de
  permiso que nombra la ruta en Ajustes del Sistema y abre el panel de Grabacion de pantalla, una vez
  por ejecucion, en vez de que la vista se quede callada.
- **Grabacion de pantalla cuenta solo cuando una captura real funciono (2026-10-03).** El preflight del
  sistema puede seguir diciendo que si despues de revocar el permiso; ahora la vista espera un sondeo
  real con ScreenCaptureKit antes de la primera captura, y una captura que falla vuelve a sondear: si
  el permiso se perdio, la vista se apaga (estado `stale`) en vez de fallar en silencio en cada turno,
  y la siguiente captura vuelve a sondear (como mucho una vez cada 30 s) hasta que funciona otra vez.
  La causa de cada captura fallida queda en el log. El sondeo nunca pide el permiso ni muestra el aviso del sistema sin concesion previa.
- **La bienvenida verifica Grabacion de pantalla con una captura real (2026-10-03).** Como Incredible,
  la fila de Grabacion de pantalla solo se marca cuando el permiso esta concedido y una captura de
  prueba funciono; encendido sin captura queda como su propio estado. La prueba corre al entrar al
  paso, al volver la ventana al frente, despues de pedir el permiso y en el sondeo de cada segundo
  solo mientras no esta verificado. Si la app se reabre directo en el paso de permisos con el interruptor encendido y sin
  captura, pide el permiso una vez mas. Si se pierde un permiso en el paso siguiente (tecla o
  microfono), la bienvenida vuelve a permisos.
- **Detener a Companion ya no hace que tu siguiente pregunta parezca una corrección (2026-10-01).**
  Al decir "para", pulsar Stop o Esc en el modo clásico, el turno siguiente llegaba al modelo con
  una nota de "te corté para corregir el rumbo", aunque lo pidieras mucho después. Ahora solo
  dejan esa nota una pulsación o una interrupción hablando encima; un stop no la deja, ni
  siquiera si pulsas justo después. Lo que Companion alcanzó a decir sigue quedando en el chat.
- **Los tests de main vuelven a compilar (2026-10-04).** Dos PR mergeados el mismo dia declaraban un reloj de
  prueba con el mismo nombre en el mismo modulo; se renombra el de versiones de archivo.
- **Las pruebas de pausa de la tarjeta de dictado ya no fallan al azar (2026-10-05).** Esperaba el reloj equivocado cuando la maquina iba cargada, asi que a veces se agotaba sin que la app tuviera ningun error. Ahora espera exactamente el tramo que debe quedar del techo.
- **La voz entrega el documento por contrato, no por adivinanza (2026-10-12).** Al pedir por voz
  una tabla, cinco pasos o tres parrafos, el cerebro llama a `show_document` con la frase y el
  documento por separado: la voz dice solo esa frase, el hilo guarda frase y documento, y la isla
  muestra la tarjeta del documento al callar la voz, en hold y en manos libres. Antes el modelo
  escribia la estructura en markdown libre y cada respuesta tenia una forma distinta (tabla con y
  sin pipes, valla `companion:table`, prosa con punto y coma, una negativa), asi que la voz leia
  filas o no habia documento. Verificado en vivo con gpt-oss-120b en Cerebras: 15 de 15 peticiones
  con estructura llegaron por la tool y una pregunta corta nunca la uso. Fuera: `SpokenLead`,
  `ReplyRichness` y el desvallado de `markdown`, que eran las heuristicas que no convergian.
- 2026-10-13: el documento de una respuesta de voz sube en cuanto llega, mientras la voz dice su frase; antes el subtitulo leia la cola del documento hasta que la voz terminaba.
- 2026-10-12: el documento de una respuesta de voz se queda 12 s (el cursor encima lo sostiene); una tarjeta pegada a la frase o con un nombre inventado se pinta como tarjeta y no como codigo; Cerebras devuelve el razonamiento oculto (verificado en vivo, HTTP 200).
- 2026-10-12: la voz dice una frase y deja la tabla o la lista en el documento en vez de leerla; una tabla pedida en la charla ya no se vuelve un Excel en el Escritorio; la hora (y la de otra ciudad) se contesta desde el reloj del contexto sin mandar al especialista.
- **Decir "para" ahora para de verdad (2026-10-12).** Si interrumpes con la tecla y dices solo "para" (o "basta", "stop", "ya"), Companion calla, detiene lo que estaba haciendo, incluido un encargo en segundo plano, y no contesta nada. Antes lo tomaba como una pregunta nueva y describia la pantalla. Frases como "para manana" o "para que sirve esto" siguen siendo preguntas normales, y una hoja de permiso pendiente no se toca.
- **La respuesta rica de voz termina en el documento y los subtitulos ya no leen markdown (2026-10-12).** Una respuesta hablada con tabla, lista de 3 o mas items, dos o mas parrafos o mas de 320 caracteres queda en la tarjeta del documento cuando la voz termina, igual que una tecleada, y en manos libres el microfono sigue escuchando y la frase nueva la reemplaza. La voz y el subtitulo de la isla dejan de pronunciar pipes de tabla, vinetas y asteriscos, y ya no pegan palabras en los saltos de linea ("mAhCamara", "3.Vierte").
- **La bienvenida vuelve al paso donde se quedo (2026-10-03).** Como Incredible, cada paso reanudable
  que se alcanza (claves, permisos, tecla, microfono y tu turno) se guarda, y al relanzar la app la
  bienvenida abre en ese paso en vez de en la portada: macOS pide reiniciar la app despues de
  conceder Grabacion de pantalla, y ahora se vuelve directo a permisos. La portada y el saludo no se
  guardan (volver a ellos deja el ultimo paso alcanzado); terminar o reabrir la bienvenida borra el
  paso guardado.
- **Un test colgado ya no retiene la CI seis horas (2026-10-04).** El job de gates tiene un
  tope de 30 minutos y la salida de `swift test` sale al log mientras corre. Si pasan varios
  minutos sin salida nueva, un vigilante imprime el ultimo test que empezo, el arbol de
  procesos y una muestra de pila, y corta la corrida con un fallo claro de "test colgado"
  en vez de dejar la cola de merge esperando.
- **Un test de diagramas ya no falla en CI de vez en cuando (2026-10-01).** Solo tests: al
  cancelar un dibujo, el test revisaba de inmediato que el dibujo se hubiera enterado, pero el
  aviso llega en un turno posterior del main actor. Con el main actor ocupado, la revisión
  llegaba antes y fallaba. Ahora espera a que el dibujo registre la cancelación. La app no cambia.
- **El test de la pagina de diagrama colgada ya no apuesta contra el reloj (2026-10-01).**
  `diagramPageFailureTests` dormia 1 s y esperaba que el web view ya estuviera suelto, pero
  WebKit lo suelta cuando el recolector de JavaScript llega al script colgado, sin plazo fijo.
  Ahora espera a que se suelte, con el tope comun de 30 s. Solo tests; la app no cambia.
  Brief `docs/research/diagram-page-liberacion.md`.
- **Un test de permisos MCP ya no falla en CI de vez en cuando (2026-10-01).** Solo tests: con
  dos permisos en cola, el test exigía que las respuestas salieran al servidor en el orden de los
  clics. Pero cada respuesta sale por su lado y el protocolo las casa por id, así que dos clics
  seguidos pueden cruzarse. Ahora el test revisa que cada permiso lleve su propia respuesta, y uno
  nuevo cruza las dos a propósito. La app no cambia. Brief `docs/research/mcp-orden-veredictos.md`.
- **Dos tests del selector de @ esperan al diálogo de contactos, no a una señal vecina
  (2026-10-01).** Uno daba por abierto el diálogo en cuanto aparecían las apps y los archivos, y
  Swift no ordena esas dos cosas; bajo carga podía fallar. El otro podía pasar sin llegar a probar
  un diálogo retenido. La falla no se reprodujo en local: el arreglo sigue lo que Swift garantiza.
  La app no cambia.
- **Los tests del ejecutor nativo ya no fallan bajo carga (2026-10-01).** Solo tests: cuatro de
  ellos esperaban con un plazo de 5 s que ocupaba un hilo real, y con la Mac cargada el plazo
  vencía antes de que el trabajo tuviera turno. Otros leían los eventos del encargo justo después
  de cerrarlos, antes de que su lector los hubiera procesado, y a veces los veían vacíos. Ahora
  esperan directamente, y cada lectura espera a que el lector termine. La app no cambia. Brief
  `docs/research/native-executor-flakes.md`.
- **El test de esperas de procesos ya no depende del reloj (2026-10-01).** Solo tests y CI:
  exigía que dos esperas terminaran en menos de 0.75 s y fallaba cuando la Mac o el runner se
  congelaban un momento. Ahora las dos shells se esperan entre sí, y CI repite ese test con el
  pool cooperativo en modo estricto (un hilo), donde una espera que bloquee su hilo sí falla.
  La app no cambia.
- **El test del techo de procesos ya no depende del reloj (2026-10-01).** Esperaba 80 ms fijos a
  que dos shells de 0.3 s ocuparan el techo; si el proceso de tests se congelaba más que eso, las
  shells terminaban y el tercer encargo entraba. Ahora las shells viven hasta que el test las
  suelta y el tercero espera a que las dos ocupen su lugar. Un congelamiento de 1 s lo hacía
  fallar 5 de 5 veces; con el cambio pasa 10 de 10. La app no cambia.
- **Dos pruebas automáticas que fallaban con la Mac ocupada ya no dependen del reloj (2026-10-02).**
  En vez de cronometrar, ahora comprueban lo que importa: que el límite de tiempo gana y se cancela
  al proveedor lento, y que una conexión del navegador ya aceptada no se corta después. La app no
  cambia.
- **Los tests de reconexión toleran que la Mac se congele unos segundos (2026-10-01).** Solo
  tests: 17 esperas de `VoiceReconnectTests` tenían topes de 5 s y 2 s de reloj de pared, la misma
  causa que el arreglo de permisos (#74). Ahora usan el tope común de 30 s. La app no cambia.
- **Los dobles de test del core ya no tienen carreras de datos (2026-10-03).**
  El presentador, el transcriptor, la pantalla, el observador de cambios y el almacen de secretos
  falsos se leian desde un hilo mientras otro los escribia, sin lock. Ahora cada uno guarda su
  estado detras de un lock, con la misma API. Solo cambian tests.
- **Los dobles de la mano y del oido de los tests de servicios ya no tienen carreras de datos (2026-10-03).**
  El doble de las manos guardaba su configuracion y leia sus registros (inyectado, pulsado,
  elevado) sin lock mientras el ejecutor los escribia fuera del hilo principal, y el oido de
  prueba sacaba sus esperas de stop() de una lista compartida desde varias tareas a la vez: el
  mismo patron que ThreadSanitizer marco en los otros dobles. Ahora cada campo va detras de un
  lock y ninguna espera se duerme con el lock tomado. Solo cambian tests.
- **Los tests ya no borran la carpeta temporal de la Mac (2026-10-01).** Solo tests: tres tests
  del ejecutor nativo usaban la carpeta temporal de todo el usuario como si fuera suya y la
  borraban al terminar, así que cada corrida local intentaba vaciarla, con archivos de otras apps
  incluidos. Esa carpeta no se puede aislar desde fuera porque macOS ignora `TMPDIR` para ella.
  Ahora cada test usa una carpeta propia, y un test nuevo revisa las fuentes para que ninguno
  vuelva a borrar la temporal entera. La app no cambia. Brief
  `docs/research/native-executor-flakes.md`.
- **El llavero falso de los tests de voz ya no tiene una carrera de datos (2026-10-03).** Una boca
  de prueba borraba una clave desde la sintesis mientras el enrutador y el test leian el mismo
  llavero, sin lock: el mismo patron que ThreadSanitizer marco en CI en los dobles de la sintesis.
  Ahora cada campo va detras de un lock. Solo cambian tests.
- **Un test de procesos ya no bloquea el main actor de los demás (2026-10-01).** Al limpiar las
  shells esperaba en el main actor el margen del SIGTERM (unos 255 ms medidos), y los tests
  `@MainActor` que corren en paralelo se quedaban sin turno, un disparador plausible del flake de
  earReview. Ahora la limpieza corre fuera del main actor. La app no cambia.
- **El reloj falso de los tests de la tecla FN ya no tiene una carrera de datos (2026-10-02).**
  La cola que arma la tecla leia ese reloj mientras el test lo movia desde el hilo principal, sin
  lock, y ThreadSanitizer lo marco en CI. Ahora el reloj va detras de un lock. Solo cambian tests.
- **Los dobles de la voz en los tests de sintesis ya no tienen una carrera de datos (2026-10-03).**
  El fetch y la voz de respaldo falsos anotaban sus llamadas desde la sintesis mientras el test
  las leia, sin lock, y ThreadSanitizer lo marco en CI. Ahora cada campo va detras de un lock.
  Solo cambian tests.
- **Los tests de reconexion de voz ya no caen cuando la Mac esta cargada (2026-10-03).** En una
  corrida completa fallaba un test distinto cada vez: el arnes de pruebas daba solo 1 s al
  saludo del servicio, y con la maquina saturada la sesion se rendia y caia a la voz clasica
  antes de quedar escuchando. Ahora el arnes espera sin ese tope, igual que los de FanOut y
  rollover de conversacion que tenian el mismo 1 s, y un test nuevo lo cubre reteniendo el
  saludo mas alla de ese tiempo. Solo cambian tests; la app no cambia.
- **Un test de permisos ya no falla cuando la Mac se congela unos segundos (2026-10-01).** Solo
  tests: cuatro esperas de permisos MCP tenían un tope de 5 s de reloj de pared. Si el proceso
  quedaba parado más que eso, la espera fallaba antes de que llegara el rechazo automático. Ahora
  usan el tope común de 30 s. La app no cambia.
- **En el modo clásico, el turno nuevo espera al que cortaste (2026-10-01).** Si cortabas a
  Companion mientras usaba una herramienta lenta y hablabas de nuevo, tu turno nuevo arrancaba antes
  de que el viejo terminara: no sabía que lo habías interrumpido y el chat quedaba en desorden.
  Ahora espera hasta 2 s a que el turno cortado se detenga. Si una herramienta no lo deja, arranca
  igual y lo que el viejo diga tarde se descarta. Un turno que cortas antes de que tus palabras
  lleguen al modelo ya no deja rastro.
- **Los tests encuentran los textos aunque se compile en otra carpeta (2026-09-30).** Con
  `swift test --scratch-path` (el que usan los builds aislados y TSan) unos 555 tests veían
  claves como `island.hands.stop` en vez del texto, porque los recursos solo se buscaban en el
  `.build` por defecto. Ahora se buscan junto al bundle de tests cargado, y ya no queda ningún
  camino que evalúe `Bundle.module`, el único que podía cerrar la app si faltaba un bundle.
- **Si se corta la red mientras Companion habla, no pierdes lo que dijo (2026-09-30).**
  Lo que alcanzó a decir queda en el chat cuando termina de sonar, la voz vuelve a escucharte en
  vez de quedarse "hablando", y si dices "sigue" continúa donde se quedó sin repetir. Al
  reconectar nunca habla sola.
- **Instalar desde main ya no falla el smoke de empaquetado (2026-09-30).** Las 5 fuentes
  propietarias que solo viven en este Mac (ignoradas por git) hacían que `bundle.sh` rechazara la
  carpeta `Fonts`. Ahora una lista explícita las admite si están presentes; cualquier otro archivo
  ajeno sigue siendo un stray.
- **La isla avisa cuando la red corta a Companion a media respuesta (2026-09-30).** Ves
  "Se cortó la conexión a media respuesta" y cómo seguir. El aviso se va solo, no tapa un error
  ni un permiso pendiente, y no aparece si la voz está apagada o si ya hablaste encima.
- **Un aviso y tu siguiente turno ya no se pisan en el modo clásico (2026-09-30).** Si
  hablabas mientras Companion leía un aviso, o cortabas un turno y empezabas otro, los dos
  compartían el estado del turno: una tarjeta o una acción de uno podía colarse en la respuesta
  del otro. Ahora cada turno lleva su propio estado.
- **La voz sigue escuchando después de un corte de red (2026-09-30, #59).** Al reconectar,
  nadie leía la conexión nueva y la voz quedaba sorda; además arrancaba sin instrucciones, tools
  ni voz elegida, y volvía a encender el micrófono aunque lo hubieras silenciado. Ahora reanuda
  con su configuración y tu mute. Colgar durante una reconexión ya no revive la sesión, y un
  servidor que corta en bucle se rinde tras 3 reconexiones por minuto.
- **El puente con otros agentes no se queda "ocupado" para siempre (2026-09-30, #57).** Un
  cliente que cerraba al instante podía dejar el puente tomado hasta reiniciar la app.
- **Un texto sin traducir muestra el inglés, no la clave interna (2026-09-30, #58).** Antes una
  sola clave faltante en español pintaba algo como `chat.job.done` en pantalla.
- **La app instalada ya no depende de la carpeta de compilación (2026-09-30, #52, #54, #56).**
  Fuentes, mascota, skills y diagramas se buscaban primero junto al build de desarrollo; sin él,
  la app podía cerrarse al abrir. La extensión del navegador se empaqueta desde una lista fija de
  archivos, así un archivo ajeno no se cuela en la app.
- **Tu voz se ve en la isla mientras hablas (2026-09-25).** En el modo clásico la isla leía el oído
  de OpenAI, que ahí no recibe audio; ahora lee el oído que escucha.
- **Las respuestas se leen con formato (2026-09-25).** Negrita, cursiva y enlaces en párrafos y
  viñetas en vez de asteriscos; solo los enlaces web se abren.

### Changed
- **Cada PR exige su fragmento de changelog (2026-10-01).** El primer gate de `scripts/gates.sh` falla en segundos si el PR no agrega exactamente un archivo en `changelog.d/` o si edita `CHANGELOG.md` a mano; solo el ensamblado de wave puede tocarlo.
- **Cada cambio ahora trae su propia nota de changelog (2026-10-01).** Antes todos los cambios
  escribían en el mismo archivo y cada vez que uno se aprobaba, los demás chocaban y había que
  rehacerlos y esperar otros 10 minutos de pruebas. Ahora cada cambio deja una nota en su propio
  archivo, así que ya no se pisan; las notas se juntan en el CHANGELOG al cerrar cada wave. La app
  no cambia.
- **Companion usa el paquete privado de componentes Pro (2026-10-05).** La interfaz ya puede usar
  los componentes de Arc Pro (el primero es el orbe de voz) sin publicar su codigo: viven en un
  repo privado, fijado a un commit exacto, y CI lo descarga con una llave de solo lectura.
- **Nuevo orbe de voz en el inicio y en la bienvenida (2026-10-05).** La tarjeta "mantén fn" del
  inicio y las pantallas de bienvenida muestran un orbe que escucha, piensa y habla con tu voz y la de
  Companion; la isla se queda como está.
- **Los worktrees que crea Orca ya traen las fuentes propias (2026-10-03).** Solo
  herramientas: las cinco fuentes con licencia cerrada no estan en git, asi que un worktree nuevo
  arrancaba con Inter. `.worktreeinclude` le dice a Orca que las copie del checkout principal. La
  app no cambia.
- **El analisis de seguridad de Swift corre los lunes y a pedido (2026-10-02).** Ya no corre en cada
  merge: tardaba mas de una hora, perdia la conexion con GitHub y dejaba en cola los chequeos de los PR.
- **CI deja de hacer cola por el analisis de Swift (2026-10-01).** CodeQL de Swift tardaba hasta
  95 min en macOS y ocupaba la mayoria de los 5 runners en cada PR; ahora corre solo en main, cada
  semana y a mano. Actions y JavaScript se siguen analizando en cada PR. Un commit nuevo en un PR
  cancela su corrida anterior; las de main nunca se cancelan. Las actions quedan fijadas por SHA.
- **CI mas rapido y sin bloqueos por tests de reloj (2026-10-06).** Los PR ya no esperan el build release ni ThreadSanitizer (ahora corren de noche), el cache de SwiftPM acelera `gates`, y los tests que miden tiempo de pared quedan en cuarentena en CI pero siguen corriendo cada noche. Un fragmento de changelog ausente avisa en vez de fallar.
- **Brief y ADR 011 del texto tejido durante el hold (2026-10-05).** Queda aprobado como se tejeran la voz, lo
  seleccionado, lo copiado y lo escrito en el transcript mientras mantienes la tecla, como segmentos tipados.
- **El inventario de tests inestables, al día (2026-10-02).** Dos tests de tiempo que fallaban de vez
  en cuando ya fallan casi siempre con la Mac cargada y pasan a prioridad alta; entran dos nuevos, y
  los del ejecutor pasan a resueltos. Es un documento de trabajo: la app no cambia.
- **Un solo lugar para saber qué tests fallan a veces y por qué (2026-10-01).** Solo docs:
  `docs/inventario-flakes.md` lista cada test inestable conocido con su causa, su PR o su
  siguiente paso, y los dos known issues que no son flakes. La app no cambia.
Los documentos de investigacion ya no incluyen extractos del binario de Incredible; solo se consultan de forma local.
- **Los briefs de #68, #69 y #70 quedan ratificados por Karen (2026-10-01).** Su aprobacion la habia
  escrito un agente; ahora consta que Karen la confirmo. El codigo no cambia.
- **El README abre con el nombre en arte ASCII (2026-10-01).** "COMPANION" en la tipografía
  ANSI Shadow, con el marco del OG image de ASCII Motion, sobre el título.
- **Investigacion corregida contra la referencia (2026-10-04).** El modal que se listaba como
  "comentarios" es el de feedback y ya existe; el checklist de Incredible es un consejo fijo de
  grabacion, no un checklist de trabajos; el ancho base del aviso de diagnostico es min(520, 70vw); y
  la seccion de feedback refleja lo que Companion tiene hoy.
- **La revisión de Companion por un agente quedó probada en la app real (2026-10-02).** Con Companion al frente, un agente conectado por el puente pudo ver su estado, la isla, los ajustes, el hilo como metadatos y el log, sin leer lo que escribes y sin poder pulsar nada dentro de Companion. La evidencia queda en el repo.
- **Plan escrito para que las manos verifiquen lo que hacen (2026-10-05).** La especificacion de los cuatro arreglos de las manos: la web solo por la extension, escribir y comprobar que el texto llego, actuar sobre la ventana correcta y leer bien un campo vacio.
- **Ajustes se abre como una hoja centrada sobre la ventana, como en Incredible (2026-10-03).**
  El panel flotante oscuro de la esquina se fue: ahora un velo oscurece la app y la hoja entra
  desde arriba. Se cierra con Esc, con un clic fuera o con la X; si escribiste en el buscador,
  el primer Esc solo lo borra.
- **El rail de Ajustes se ve y se maneja como el de Incredible (2026-10-03).** Mas ancho, con su
  propio fondo, filas mas altas, la pagina activa resaltada y el grupo "Cuenta" con titulo. En el
  buscador, las flechas recorren los resultados, Enter abre el marcado y Esc borra lo escrito. El
  titulo de cada pagina es mas grande y el contenido tiene mas aire a los lados.
- **Al elegir un resultado del buscador de Ajustes, la fila queda centrada y resaltada (2026-10-03).**
  Como en Incredible: la pagina se abre, la fila elegida se centra en pantalla y una banda suave la
  marca un momento y se apaga. Elegir una pagina entera solo la abre.
- **Las tarjetas de Apps son las de Incredible (2026-10-03).** Cada app se ve en una fila: ícono de
  48 pt (con sus dos iniciales si no hay logo), nombre, una descripción de hasta dos líneas y, a la
  derecha, el estado: la pastilla verde "Conectada" con su palomita, o un botón ligero "Conectar" con su signo +.
  Al pasar el puntero el borde se oscurece. Las tarjetas grises de carga ocupan ahora el mismo
  tamaño que las de verdad, así que la lista ya no salta al llegar, y en modo oscuro se distinguen
  de la tarjeta en lugar de casi desaparecer.
- **Configurar la función de apps ya avisa qué falta y confirma cuando funciona (2026-10-03).**
  El formulario de dirección y clave dice en cada campo qué está mal, solo después del primer
  intento y al momento mientras corriges, y VoiceOver lo anuncia. Mientras comprueba la función
  el botón muestra que está trabajando y no se puede enviar dos veces. Si la función rechaza la
  clave o no responde, el formulario se queda con lo que escribiste y el error a la vista; si
  responde, se convierte en una confirmación breve y luego aparece el catálogo. El aviso de
  configuración gana título, icono y una acción clara, y con Reducir movimiento todo cambia sin
  desplazamientos ni desenfoque.
- **La página de Apps carga como Incredible (2026-10-03).** Mientras llega la primera página del
  catálogo ya no se ve un spinner suelto: aparecen ocho tarjetas con la silueta de una app (ícono y
  tres líneas) que laten suave hasta que llega la lista. Con Reducir movimiento quedan quietas, y
  VoiceOver las lee como un solo "Cargando apps". En el panel de una app, las esperas de cargar
  acciones y de desconectar usan el spinner de Incredible (un arco de 14 pt) junto a "Cargando…" y
  "Desconectando…".
- **Las tarjetas de adjuntos de la isla quedan como las de Incredible (2026-10-04).** Cada archivo
  pendiente es una tarjeta de 84 x 102 con su vista previa, y el boton para quitarlo es un disco de
  24 pt sobre la esquina superior derecha que aparece al pasar el puntero o al llegar con el
  teclado. Quitarlo saca el archivo del mensaje pendiente, y VoiceOver lo encuentra con el nombre
  del archivo.
- **La zona para soltar archivos de la isla dice por que rechaza uno y se oye con VoiceOver (2026-10-04).**
  El motivo del rechazo ya no se pierde, VoiceOver anuncia que la isla recibe el archivo, y con
  Reducir movimiento el resaltado no se anima. La forma no cambia: ya era la de Incredible.
- **Una actualización se anuncia una sola vez (2026-10-04).** En la tarjeta de la isla, o en un aviso de la
  ventana solo cuando la isla no puede mostrar esa tarjeta.
- **Primer paso para contestar de voz una hoja de permiso en voz clasica (2026-10-02).**
  El turno de voz ya sabe quedarse en pausa mientras una accion espera tu permiso, sin
  cortarse y sin que el boton de detener deje de alcanzarlo. Todavia no cambia nada de
  lo que oyes: la pregunta en voz alta y la respuesta llegan en los siguientes pasos.
- **El detalle de una tarea es una conversación que se puede seguir (2026-10-05).** Al abrir una
  tarea ves primero lo último que pasó, tus mensajes en burbujas suaves a la derecha y las
  respuestas como texto limpio a todo lo ancho, con las herramientas que usó Companion cuando
  quedaron registradas. Abajo hay un campo para escribir: lo que pongas sube al hilo y la isla
  sigue la tarea con ese mensaje; sin escribir nada, "Seguir" la retoma como antes.
- **El volumen de la isla se ve como el de Incredible (2026-10-03).** El slider nativo de macOS
  cambia por uno dibujado: pista de 6 pt, relleno azul hasta el valor y una perilla blanca de 12 pt
  que reposa pequeña y crece al pasar el puntero, al enfocarla con el teclado o al arrastrarla. Se
  mueve de 5 en 5 % con el puntero, con las flechas y con VoiceOver, que lo sigue leyendo como un
  valor ajustable. Con Reducir movimiento la perilla cambia de tamaño sin animación.
- **Los errores se anuncian y el diagrama de la isla falla con un aviso claro (2026-10-04).** El lector de
  pantalla dice "Error:" antes de un aviso de error, y con movimiento reducido los avisos aparecen sin
  deslizarse. Mientras dibuja, el diagrama muestra un esqueleto; si falla, un aviso con icono que el lector
  anuncia, y el codigo sigue debajo. Borrador pendiente de Karen.
- **Companion guarda versiones de tus archivos en un almacen privado, sin dejar copias a su lado (2026-10-04).**
  Documentos: una copia antes y otra despues de guardar; hojas: una antes de escribir. Se conservan hasta 20 copias por archivo, 30 dias, 50 MB por copia y 1 GB en total, en su carpeta privada; si no puede guardar una, la escritura sigue y el modelo lo dice. Ya no aparecen archivos `-backup-` junto a los tuyos.
- **Los ajustes de fin de turno ahora si cambian cuando Companion deja de escucharte (2026-10-02).** La pausa y la avidez que eliges en Ajustes mueven el cierre del turno en voz realtime; antes se guardaban y no hacian nada. El valor por defecto conserva los tiempos medidos.
- **El orb que sigue al cursor mientras se sostiene la tecla es ahora la pildora de Incredible (2026-10-03).** El orb real de 32 pt dentro de una pildora que acompana al puntero desde abajo a la derecha; aparece y se va en 180 ms desde 0,85 y se queda 1,2 s tras soltar. Ya sabe destellar lo que se toca y apilar lo que se entrega, aunque todavia no le llega nada: eso llega con el sensor del hold.
- **La respuesta escrita de la isla, como chat de Arc sobre la tarjeta de documento (2026-10-13).** Cuando
  ya hay conversación, el panel donde escribes se abre al ancho de la tarjeta de resultado (621) y pinta
  el hilo con el ai-chat de Arc: tablas de verdad, listas, negritas, citas [n] con sus fuentes, copiar y
  fundido por palabra mientras escribe. Tu mensaje va en burbuja, el composer es el de Arc (clip, orbe de
  voz y enviar que se vuelve parar), y el especialista se ve como su agent-run compacto. Lo que envías desde
  ahí se queda en el chat en vez de irse a la barra. El hilo largo hace scroll dentro de la tarjeta, sin
  cortar nada arriba. El subtítulo de voz sigue leyendo el texto plano de siempre.
- **El panel de la isla mide y se mueve como el de Incredible (2026-10-12).** La barra abierta pasa a 480 de ancho con esquinas de 28; el campo mide 38 con esfera de 38, crece con lo que escribes hasta 118 y deja lo de abajo alineado con las palabras. Cada bloque entra y sale 14 pt desde arriba con un pequeño rebote (sin movimiento, solo se desvanece).
- **La respuesta y el recibo de la isla ahora son un documento (2026-10-12).** La tarjeta de resultado se rehizo con piezas propias
  y las medidas del documento de Incredible: la isla se ensancha a 621 pt, la tarjeta tiene su propio fondo, esquina y brillo,
  el titulo es la pregunta, la prosa conserva parrafos, vinetas y tablas, las fuentes salen como chips con borde y el recibo
  es un libro de lineas con su marca de "Verificado". Cada bloque entra con su escalon, sin movimiento si el sistema lo pide.
- **La isla abre, se asienta y se cierra con los tiempos de Incredible (2026-10-05).** Pasar el puntero abre el notch a los 150 ms, o a los 300 ms si cruza rapido; al salir espera 250 ms, y nunca cierra antes de 300 ms desde que abrio, para no parpadear en el borde. Al terminar una respuesta sin tarjeta la isla se asienta en 200 ms; con el puntero encima espera, y al salir quedan al menos 1,5 s. Mientras hay un aviso, una hoja de permiso o una respuesta abierta no se asienta, y se asienta en cuanto se van; un turno nuevo cancela la espera. Las pausas bajo el puntero ya no tienen techo de 60 s: duran hasta que el puntero sale de la isla, y esa salida libera tambien la tarjeta de dictado y los avisos, incluso cuando la isla se oculta o cambia de pantalla.
- **"Ver →" en la isla solo abre lo que el popup puede mostrar (2026-10-04).** Una tarjeta de datos que llega aparte del texto ahora se dibuja en el popup; una galeria queda fuera a proposito hasta validar sus rutas, y un bloque de galeria o de opciones ya no genera una fila "Ver" que abria JSON crudo.
- **Una grafica abierta con "Ver" se ve igual que en la isla (2026-10-05).** Cuando la grafica llegaba aparte del texto, el popup la dibujaba como la tarjeta clara de la ventana; ahora usa la misma grafica oscura de la isla que cuando viene dentro de la respuesta.
- **La isla abierta alcanza el alto de la de Incredible (2026-10-02).** El lienzo de la isla crece
  de 620 a 656 de alto para que quepa la columna completa de Incredible (560) bajo cualquier banda
  hasta la suya (44); antes la forma se recortaba a 592 y una respuesta larga perdia alto.
- **La isla cierra cada turno con una sola tarjeta de resultado (2026-10-12).** La respuesta terminada ("Listo") y el recibo ("Hecho") ahora son la misma tarjeta grande: el título dice qué pediste, debajo va lo que dijo Companion y lo que hizo en pasos (plegados en "N pasos", se abren con un clic), y al pie las fuentes que se abren en el navegador o las apps que tocó, con "Cerrar" y "Seguir en el chat". Las gráficas y tablas de la respuesta siguen dentro de la tarjeta. Sube CompanionUIPro a 795f2c3.
- **La tarjeta de aprobacion entra y sale como las de Incredible (2026-10-03).** Sube 6 pt desde 0,98 de escala en 260 ms con la curva settle, creciendo desde abajo, y se va mas rapido: 200 ms, bajando 4 pt. Con reducir movimiento solo aparece en un fundido de 120 ms y se va al instante.
- **La linea de estado cambia como la cabecera de Incredible (2026-10-02).** Cuando la isla pasa de escuchar a pensar, la linea nueva sube desde abajo (120 % de su altura, 360 ms con la curva de la isla) mientras se aclara y enfoca, y la vieja sale por arriba en 220 ms. Cada propiedad lleva su propio tiempo, como en Incredible.
- **La isla abre y cierra como la de Incredible (2026-10-02).** La forma crece con la curva de la isla de Incredible (330 ms, un leve sobrepaso) y vuelve a la muesca en 280 ms sin rebote. Con la isla abierta, crecer usa la misma curva y encoger tarda 260 ms sin rebote. El contenido aparece con un fundido de 130 ms a los 60 ms de empezar a abrir, sin desenfoque ni subida, y al cerrar se va en el mismo tiempo.
- **El orbe del campo late con la voz, como en Incredible (2026-10-03).** Mientras Companion responde en voz, el orbe junto al campo crece hasta 28 % con su nivel, siguiendolo en 90 ms ease-out; el microfono lo deja quieto. Con reducir movimiento no crece.
- **La isla abierta aparece por partes, como la de Incredible (2026-10-03).** El campo entra a los 60 ms, la conversacion a los 90 y las tarjetas a los 120, cada una con su fundido de 130 ms; al cerrar se van todas juntas con la forma. Con reducir movimiento nada espera.
- **Las palabras de la respuesta se encienden como en Incredible (2026-10-03).** Mientras responde en voz, cada palabra espera en gris (blanco al 48 %) y al decirse pasa a blanco al 94 % en 220 ms con la curva settle. Con reducir movimiento cambia al instante.
- **La dona de la isla se mueve como la de Arc (2026-10-03).** La grafica de dona deja Swift Charts
  y pasa a un anillo propio: aparece con un barrido desde las 12, cambia de datos estirando cada
  segmento desde donde esta (sin saltos aunque el cambio llegue a medias), conserva el color de
  cada etiqueta entre datos, junta las partes de menos del 4 % en "Otros" (seis segmentos como
  maximo) y muestra el total al centro con cifras de ancho fijo que cuentan hasta el valor nuevo.
  VoiceOver oye cada parte con su porcentaje y quien forma "Otros"; con Reducir movimiento todo
  salta al estado final.
- **Manos libres suena igual que mantener fn (2026-10-12).** Antes, abrir la voz sin mantener tecla
  usaba otra voz y otro cerebro (el modo en vivo de OpenAI) cuando habia clave de OpenAI. Ahora
  usa el mismo cerebro y la misma voz que configuraste, asi que es un solo asistente.
- **Companion mira primero la barra de herramientas de una ventana (2026-10-02).** Es para que, en
  apps con listas largas como Notas con muchas notas, botones como "Nueva nota" no se queden fuera
  por falta de tiempo. Falta confirmarlo en vivo en Notas y en Chrome.
- **Escribir en una nota nueva y cerrar apps con cuidado (2026-10-02).** Cuando Companion quiere
  escribir y la app no tiene dónde (Notas sin una nota abierta), ahora sabe que primero tiene que
  crear el documento desde el menú, en vez de reintentar sin salida. Y salir de una app o cerrar
  una ventana o pestaña desde el menú ahora pide tu aprobación, salvo que se lo hayas dicho tú
  ("cierra Notas"); un botón "Cerrar" de un aviso sigue funcionando como antes.
- **La pantalla del nombre en el onboarding se ve mas cuidada (2026-10-03).** El campo donde
  escribes tu nombre ahora es mas alto (50 px), con fondo gris suave, y al enfocarlo se marca con
  un borde oscuro y un aro de 3 px, asi se ve claro donde estas escribiendo. El titulo y el texto
  de apoyo tambien se reacomodaron, y la esfera de esta pantalla es mas chica para que todo quepa
  en la ventana minima sin recortarse. Los textos no cambian.
2026-10-03: La pantalla de Permisos del welcome pasa a dos columnas (WIN-10). A la izquierda, cada permiso es un grupo con su paso numerado en un círculo de 24 px que se pone verde con un rebote al concederse; a la derecha, una guía dibuja el permiso activo (el que el usuario está atendiendo o el primero sin conceder) y cambia con un fundido. Con "reducir movimiento" el cambio es instantáneo y no hay rebote.
- **En modo pasivo una respuesta de Companion ya no abre la isla, como en Incredible (2026-10-03).** La isla queda en reposo; una hoja de aprobacion, un aviso, el deshacer o las manos siguen abriendola, y un dictado siempre se ve. El chip que lleva la linea de voz llega en el siguiente paso.
- **Los pasos de un encargo ya llevan datos reales (2026-10-04).** Cada paso guarda cuándo
  empezó y cuándo terminó, y su fin se empareja con su inicio por el id de la herramienta, así
  que dos llamadas paralelas a la misma tool cierran cada una su fila. Con Claude Code, un paso
  ya no se marca terminado al aparecer: se cierra con su `tool_result` (fallido si trae
  `is_error`), y todos los `tool_use` de un mensaje cuentan, no solo el primero. Los pasos
  nativos muestran su argumento principal en vez de "Executing x". Prepara la tarjeta de
  ejecución de Incredible 0.2.36; esta entrega no cambia la interfaz.
La tarjeta de ejecucion de la isla ahora aparece al pasar el cursor (o con el campo enfocado) y es una sola: muestra todos los pasos del trabajo, cada uno con su estado real (hecho, fallido o en curso).
Cada paso lleva su duracion real y el trabajo un cronometro en vivo; si un paso no tiene dato de tiempo, no se inventa un numero.
La lista de pasos largos con su contador "3/7" desaparece.
- **El brillo de pantalla es el de Incredible (2026-10-03).** Mientras escuchas, los bordes se iluminan con el mismo shader que usa Incredible por defecto: olas que corren en diagonal, la paleta que gira alrededor del marco, el lienzo a 1,25 pixeles por punto y el conjunto girado 180 grados. Entra en 260 ms y sale en 900 ms, lineal. Esperando una respuesta se atenua a la mitad y se encoge un pelo. Al encenderse sale de la muesca una onda de 850 ms. Esperar ya no enciende el brillo si estaba apagado. Con reducir movimiento queda quieto, sin onda y sin transicion del contenedor.
- **Sin esfera: marcas quietas en lugar de orbes animados (2026-10-13).** Karen prefirió
  rendimiento sobre la esfera decorativa. La isla, la portada de la ventana, la bienvenida, el chip
  de voz y la píldora del cursor ya no dibujan orbes ni partículas cuadro a cuadro: el composer
  tiene un botón de micrófono (mantener habla, clic abre la ventana, VoiceOver lo activa), la
  columna de estado muestra un micrófono al escuchar, una onda al hablar y un punto quieto al
  pensar o trabajar (el texto de estado dice cuál), y la portada lleva un glifo del estado de la
  voz. La isla conserva sus tamaños. Se borró el código de los orbes (Orb, ThinkingOrb, IslandOrb)
  y sus tests.
- **La isla dibuja tu voz como una linea de tiempo (2026-10-03).** Las cinco barras fijas del
  microfono pasan a ser una onda que corre hacia la izquierda, como en Incredible: barras mientras
  hablas, puntos en silencio, con ganancia automatica para que una voz baja tambien se vea. Mientras
  Companion habla ya no hay barras: el orbe lleva la voz.
- **La voz de ElevenLabs se elige con tarjetas en Ajustes › Voz (2026-10-03).**
  El menu desplegable pasa a una lista de tarjetas, una por voz, con la elegida marcada por un anillo y
  un punto (no solo por color); Ana Maria dice "Predeterminada". Las flechas recorren las voces, Inicio y
  Fin saltan a los extremos, y VoiceOver las lee como botones de opcion. La tarjeta "Personalizada"
  muestra el voice id guardado completo y abre el campo para cambiarlo; elegirla no cambia la voz hasta
  usar un id valido, y el error se lee en el campo. Con Reducir movimiento el anillo salta sin deslizarse.
- **La onda del micro ya no dibuja el ruido de la sala (2026-10-03).** Como en Incredible, mientras
  no hablas la onda de la isla son puntos: el ruido de fondo (el zumbido del cuarto, el ventilador
  bajo) ya no levanta barras. Las barras aparecen desde la primera sílaba y se sostienen un instante
  después de la última, para que una pausa entre palabras no parpadee. Con Reducir movimiento la
  columna fija sigue lo que pasa ahora (barra si hablas, punto si callas) en vez de quedarse en la
  barra más alta desde que apareció.
- **Ajustes como panel flotante (2026-10-02).** Ajustes ya no es una ventana modal: es un panel de
  336 px abajo a la derecha, oscuro como el de Incredible, con tres estados (flotante, anclado al borde
  derecho y plegado en una píldora). La ventana de atrás sigue usable mientras está abierto.
- **Apariencia como selector segmentado (2026-10-02).** En Ajustes, Apariencia (claro, oscuro, auto) es
  ahora un selector segmentado como el de Incredible: el segmento activo es una pastilla blanca con texto
  negro que se desliza en .22 s, y se maneja también con las flechas.
- **El brillo de pantalla ya no se enciende cuando un agente usa las manos, como en Incredible (2026-10-03).** Decision de Karen: el brillo es solo de la voz. Una sesion de manos se detiene desde la barra de menu ("Detener manos").
- **Las tarjetas con cuenta atras de la isla se pausan con el puntero encima, como en Incredible (2026-10-04).** El anillo y el reloj se detienen juntos y al salir siguen donde iban; un aviso nuevo arma su propio reloj. La tarjeta de dictado dura 4,9 s en vez de 12.
- **La isla usa los bloques reales de Arc (2026-10-06).** Mientras habla, la isla muestra
  el bloque de voz de Arc: el orbe del paquete centrado, la respuesta en dos lineas debajo y
  el boton de parar en su propia pastilla. Antes era un cuadro rojo suelto con la respuesta a
  pantalla completa. La conversacion es el mismo hilo de la ventana de tareas (AIThread) y
  reemplaza las tarjetas de resultado. El orbe y el loader vienen de CompanionUIPro.
- **Las graficas y tablas se ven dentro del notch (2026-10-06).** Una respuesta con grafica,
  tabla o cifras la muestra debajo de sus palabras, dentro de la isla, en vez de abrir un
  panel aparte con "Ver". Su tamano sale del espacio del notch: ya no ocupa media pantalla.
- **La isla con el lenguaje de Arc (2026-10-05).** El notch se rediseña sobre los bloques de Arc:
  un orbe de voz que respira en reposo, ondula al escuchar, se contrae en remolino al pensar
  (pensar por fin tiene un visual propio) y late al hablar; un encargo se ve como un run en vivo,
  con cada paso sobre un riel que se llena, el titulo en presente mientras corre y en pasado al
  terminar, los pasos viejos plegados y un loader que se dobla en check o en cruz; la
  transcripcion entra palabra por palabra desde un blur suave. Todo comparte un grid: el orbe,
  los nodos, los iconos de los avisos y los checks del recibo viven en una columna guia y todo
  texto empieza en la misma x. La isla es la superficie: el run, el recibo, los avisos, el
  dictado y la aprobacion son filas, no tarjetas anidadas. Un tono por significado (exito,
  atencion, peligro, informacion) en vez de cuatro verdes y tres rojos; solo pesos 400 y 500;
  esquinas concentricas; el borde de la columna se desvanece solo donde hay mas que leer.
  Los controles tambien son de Arc: chips con borde que ceden al presionar, un menu elevado con
  filas concentricas, tooltip invertido, la pregunta como tarjetas de radio que conservan su
  numero de atajo, borrar el historial y deshacer como una sola pildora que confirma, el campo
  como input con borde, adjuntos y zonas para soltar con los tonos del dropzone de Arc (el
  borde discontinuo se cierra cuando el archivo esta encima), el chip de referencia como badge
  de informacion, el check de copiado en verde y los graficos con la serie oscura de Arc.
- **El micrófono abre más rápido al mantener fn (2026-10-12).** Entre una pulsación y la siguiente la app conserva el motor de audio ya preparado en vez de reconstruirlo, así que la voz empieza a escucharse unos 26 ms antes. El micrófono sigue cerrándose al soltar.
- **Decidido como un agente prueba a Companion sin tocarse a si misma (2026-10-01).** Cinco
  briefs de research: el puente puede mirar y consultar el estado de Companion pero no pulsarla,
  solo con metadatos; cada aprobacion critica pedira Touch ID; un pedido de cambiar un ajuste
  traera ese control a la isla; y la velocidad de voz sera por conversacion. Todavia no cambia la app.
  La spec de la velocidad ya esta firmada: "habla mas rapido" vale hasta colgar, tambien entre
  pulsaciones de FN, y nunca se guarda en Ajustes. Tambien quedan firmadas las specs de lo que
  sigue: que un agente pueda revisar a Companion sin tocarla, Touch ID en cada aprobacion critica
  (si no se puede verificar, nada critico se aprueba) y los ajustes que se cambian desde la isla.
- **Cuando los tests se caen a mitad de camino, el gate dice cuál y por qué (2026-10-01).** Solo
  gates: si el proceso de tests moría sin resumen, Gate 4 y la corrida de TSan solo mostraban el
  final de la salida, sin el test que estaba corriendo ni la señal, porque `swift test` sale con 1
  igual y la señal se imprime miles de líneas más arriba. Ahora el reporte imprime el código de
  salida, la señal si la hay y los tests que arrancaron sin terminar. La app no cambia.
- **El gate de capas rechaza un test suelto en `Tests/` (2026-10-01).** Un `.swift` directo en
  `Tests/`, fuera de toda carpeta de target, no lo compila ningún target y sus tests nunca
  corren; ahora el gate falla y lo nombra.
- **El gate de capas detecta tests que nadie compila (2026-10-01).** Solo gates: un `.swift` bajo
  `Tests/` que `exclude:`, `sources:` o un `path:` propio dejaban fuera nunca corría, y el build
  solo lo avisaba de pasada, o ni eso. Ahora el gate le pregunta a SwiftPM
  (`swift package describe`) qué compila cada target y falla si sobra un archivo. La app no cambia.
- **El gate de capas ya no depende de cómo se llame un target de soporte (2026-10-01).** Todo
  target bajo `Tests/` que no sea de test cuenta como soporte, se llame como se llame y aunque la
  ruta se escriba distinto (`./Tests/x`, `tests/x`); un target de producción tampoco puede
  depender de un target de test, y si un target de la tabla de capas desaparece del manifest el
  gate falla en vez de saltarse sus chequeos.
- **La voz también vive en el target de su capa (2026-10-01).** Los tests de voz pasan a Services
  e integración y el target de transición `CompanionTests` desaparece; los imports de soporte son
  explícitos en todos los archivos.
- **CI corre ThreadSanitizer sobre toda la suite (2026-09-30).** Un job `tsan` aparte busca
  carreras de datos en cada PR; fue la única herramienta que destapó las del puente y del modo
  clásico. Por ahora es informativo: un aviso lo pone en rojo sin bloquear el merge, y pasa a
  requerido tras 5 corridas limpias seguidas. En local se corre igual con `scripts/tsan.sh`.
  Para que arranque en verde se arreglaron dos carreras que solo existían en los tests (el
  contador de SIGPIPE y el motor falso del transcriptor); la app no cambia.
- **Los tests se dividen en un target por capa (2026-09-30).** Core, Services, UI e integración
  tienen su propio target y un gate impide que uno importe la capa que no le toca; la voz sigue
  en `CompanionTests` y se mueve en el paso siguiente.
- **Los gates de capas cubren más (2026-09-30).** Tienen casos negativos para cada dependencia
  prohibida entre targets de test, y rechazan que código de test aparezca en un producto del paquete.
- **Código ordenado por dominio y API interna de paquete (2026-09-30, #50, #51).** Las carpetas
  siguen el dominio de cada pieza y las librerías ya no exponen nada `public`; un gate lo impide.
- **La suite de tests dejó de fallar al azar (2026-09-30, #53).** Carreras en los dobles de test,
  esperas con reloj real y un hook global compartido hacían fallar 3 o 4 de cada 10 corridas;
  ahora pasan 10 de 10.
- **Specs aprobadas de los siguientes pasos (2026-09-30, #55):** tests por módulo, catálogo
  único de textos y división de VoiceSession, cada una con su research verificado.

### Added
- **Como rehacer los Ajustes de Companion como la hoja real de Incredible (2026-10-03).**
  Describe la hoja centrada, el rail con busqueda, el mapa de paginas, el aviso de guardado y los
  sub-dialogos, y lista lo que Incredible tiene y Companion todavia no. Es un documento de trabajo:
  la app no cambia.
- **Como leera Companion la seleccion de Finder, el texto seleccionado y los clics en modo pasivo (2026-10-03).**
  Compara Accesibilidad, Apple Events y event taps, y que aviso de permiso dispara cada uno, contra Incredible 0.2.36.
  Es un documento de trabajo: la app no cambia.
- **Por que la isla de Companion no se cierra y corta los textos largos, y como lo hace Incredible (2026-10-02).**
  Describe cuando abre, cuanto espera y como pausa al pasar el puntero, y deja once decisiones para Karen.
  Es un documento de trabajo: la app no cambia.
- **Las medidas exactas de la isla de Incredible y por que en Companion aparecen barras vacias y textos cortados (2026-10-02).**
  Mide ancho, alto, radios, rejilla y limites de cada widget, explica los dos errores que se ven en las capturas
  y deja diez decisiones para Karen. Es un documento de trabajo: la app no cambia.
- **Un mapa de cada movimiento de la isla de Incredible contra el de Companion (2026-10-02).** 34 movimientos con
  su duracion, curva y orden, y como escribir cada uno en SwiftUI; deja doce decisiones para Karen. Es un
  documento de trabajo: la app no cambia.
- **Por qué el log repite líneas al arrancar (2026-10-02).** Un estudio confirma que Companion no
  registra dos veces sus atajos de teclado ni sus conexiones: las llamadas que se repiten no crean
  nada nuevo y solo vuelven a escribir en el log. Es un documento de trabajo: la app no cambia.
- **Un estudio a fondo de como Incredible usa la computadora y que le falta a Companion para igualarlo (2026-10-02).**
  Describe sus tres formas de actuar (AppleScript, accesibilidad en segundo plano y control experimental),
  propone ocho specs pequenas en orden y deja las decisiones de seguridad a Karen. Es un documento de
  trabajo: la app no cambia.
- **Un estudio de por qué "abre Notas y escribe hola" abre Notas pero no escribe (2026-10-02).** Encuentra
  tres causas y propone cómo igualar a Incredible en atajos de teclado sin dejar que Cmd+Q o Cmd+W
  cierren apps sin aprobación; deja cinco decisiones para Karen. Es un documento de trabajo: la app no cambia.
- **Un plan para mejorar el control del navegador, comparado con Incredible y con seis proyectos open source (2026-10-02).**
  Doce specs chicas ordenadas por gravedad, a partir de la auditoria de la extension, y nueve decisiones para Karen.
  Es un documento de trabajo: la app no cambia.
- **Un estudio de los dos tests de tiempo que más fallan con la Mac cargada (2026-10-02).** Explica por
  qué caen y propone cómo probarlos sin depender del reloj; deja dos decisiones para Karen. Es un
  documento de trabajo: la app no cambia.
- **Eliges con qué micrófono te escucha Companion (2026-10-04).** En Ajustes, General, la fila
  Micrófono abre la lista de entradas como en Incredible: el micrófono integrado (recomendado),
  Detección automática con el que tiene elegido tu Mac y cada dispositivo conectado. Al abrirla, si
  ya diste permiso, las barras muestran si te está llegando la voz; si algo falla aparece el aviso y
  "Intentar de nuevo". La lista se actualiza sola al conectar o desconectar. La elección se guarda por el
  identificador del dispositivo, no por su nombre, y la captura de voz y la prueba de micrófono de
  la bienvenida usan ese mismo. Si lo desconectas, Companion pasa al del sistema, también a mitad de
  una conversación, y vuelve a él cuando lo conectas otra vez.
- **Companion acomoda tus ventanas y lo deshace (2026-10-03).** Pídele "pon Safari y Code lado a
  lado" y usa uno de 11 layouts (mitades, tercios, cuadrícula, centrada...) en la pantalla que digas.
  Primero puede mostrarte el plan sin mover nada; mover de verdad o deshacer siempre pide tu permiso.
  Antes de cada acomodo guarda dónde estaba cada ventana, y "deshaz" las regresa; las que cerraste
  mientras tanto se saltan y te lo dice. Si una app no se deja achicar, la mete dentro de la
  pantalla y avisa dónde quedó. Necesita el permiso de Accesibilidad; sin Stage Manager por ahora.
  Deshacer no vuelve a minimizar las ventanas que salieron para acomodarse, y no alcanza ventanas
  de otros Escritorios (Spaces).
- **Ajustes ya puede borrar de verdad el historial de chats (2026-10-04).**
  En Sistema, seccion Datos, "Borrar historial de chats" pide confirmacion y borra de este equipo
  los chats con Companion, las tareas iniciadas en ellos y las copias de adjuntos que la app guardo
  para esos chats. Una tarea que seguia corriendo se detiene y no puede volver a escribir el chat
  borrado. Las apps conectadas, el dictado y tus archivos se quedan como estan. No se puede deshacer.
- **El navegador ya no se queda atascado con un dialogo de la pagina (2026-10-05).**
  Cuando Companion tiene el control de una pestana y la pagina abre `alert`, `confirm`, `prompt` o
  `beforeunload`, la extension contesta por CDP: las alertas se descartan, los `confirm` siempre
  valen "no" (y si la pregunta incluye borrar, pagar, enviar, transferir o cualquiera de sus
  equivalentes en espanol, el modelo recibe una linea avisandole), los `prompt` reciben su valor
  por defecto, y un `beforeunload` mantiene la pestana donde esta. Entre acciones, la misma politica
  se aplica en un guion en el mundo MAIN que envuelve `window.alert/confirm/prompt/print` para que
  la pagina no se bloquee aunque nadie este mirando. La siguiente accion o lectura de esa pestana
  lleva una linea mas en su `done` o en el texto leido, contando que decidio Companion y pidiendo
  que la persona lo confirme.
- **El navegador ya arrastra y pulsa un punto de la página (2026-10-03).** Dos herramientas nuevas,
  como las de Incredible: `browser_drag` arrastra un elemento de la última lectura sobre otro, o
  unos píxeles, con el botón real del ratón en pasos, para reordenar listas, mover tarjetas o
  deslizadores. Sobre un elemento pide permiso si cualquiera de los dos extremos lo pediría para un
  clic, y el sí queda atado a los dos elementos y sus etiquetas; por píxeles siempre pide permiso.
  `browser_click_at` pulsa un punto x, y de la página visible, para lo que no tiene número (un
  lienzo, un mapa), y siempre pide permiso. Las dos solo valen sobre una lectura de hace menos de un
  minuto, que se comprueba al pedir permiso y otra vez justo antes de pulsar; si la pestaña navegó o
  se volvió a leer, el sí ya no vale y la llamada vuelve como desactualizada, sin reintentar. Nunca
  se suelta ni se pulsa sobre un marco incrustado de otra página. Los arrastres HTML5 nativos
  (`draggable`) todavía no se completan.
- **La lectura del navegador dice el estado de cada control (2026-10-03).**
  Un desplegable abierto y uno cerrado se leían igual, y un botón deshabilitado parecía pulsable,
  así que el modelo no sabía si su clic había abierto algo. Ahora cada elemento lleva su estado
  junto a la etiqueta: deshabilitado, expandido o contraído, marcado, desmarcado o mixto, pulsado,
  seleccionado y si abre un menú. Solo pasan palabras fijas, nunca texto de la página.
- **El navegador ya hace doble clic y clic derecho (2026-10-03).** Dos herramientas nuevas,
  `browser_double_click` y `browser_right_click`, como las de Incredible: el doble clic abre o
  selecciona lo que un clic no alcanza, y el clic derecho abre el menú contextual de la propia
  página. Pulsan con el ratón real en el centro del elemento, con las mismas comprobaciones que el
  clic (nada encima, que siga en su sitio) y piden permiso exactamente donde lo pediría un clic en
  ese elemento: borrar, enviar o pagar, un enlace a otro sitio o un marco ajeno. El permiso de un
  clic no vale para un doble clic.
- **Companion ya pulsa teclas en el navegador (2026-10-03).** `browser_press` pulsa Enter, Escape, Tab,
  las flechas, Espacio, Retroceso, Suprimir, Inicio, Fin y las de página, como `el.press` de
  Incredible, con eventos de teclado reales y solo después de comprobar que el elemento tiene el foco.
  Un Enter o un Espacio se juzga como un clic: en un campo, sobre el botón que envía el formulario, así
  que un Enter que mandaría un mensaje pregunta antes, y uno que busca no. Sin botón con nombre (un chat
  que envía con Enter) también pregunta. Moverse con Tab o las flechas, o cerrar con Escape, nunca pregunta.
- **Leer el navegador ya busca como Incredible: por texto, por rol y dentro de un elemento (2026-10-03).**
  `browser_read` solo leía la página entera o lo que nombrara un selector CSS. Ahora acepta un texto
  (los controles y líneas que lo dicen, entero si se pide `exact`), un rol con su nombre, un elemento
  de la lectura anterior dentro del cual buscar, y topes de elementos y de caracteres. Si nada
  coincide, o solo coinciden cosas ocultas, el modelo recibe cuál de las dos es y qué hacer.
- **La lectura del navegador puede listar también lo oculto (2026-10-04).**
  Con `hidden: true`, `browser_read` incluye los controles que no se muestran, como los items
  de un menú cerrado, y cada uno va marcado `hidden` para que el modelo no lo tome por visible.
  Actuar sobre uno se sigue rechazando mientras siga oculto, su texto no entra al texto de la
  página y su valor no viaja. Sin la opción, la lectura es exactamente la de antes.
- **El navegador ya desplaza la página y pasa el puntero (2026-10-03).** Dos herramientas nuevas,
  como las de Incredible: `browser_scroll` desplaza una pestaña unos píxeles (con la rueda real, en
  el centro de la vista, así que también mueve listas y paneles con su propio scroll) o trae a la
  vista un elemento de la última lectura, y `browser_hover` pasa el puntero sobre un elemento para
  abrir los menús o ayudas que solo aparecen al pasar por encima. No piden permiso porque no
  cambian nada de la página, pero exigen controlar la pestaña, y el puntero solo va a un elemento
  que no tenga nada encima. Un desplazamiento tiene un tope de 20 000 píxeles por eje.
- **Companion ya elige opciones en las listas desplegables del navegador (2026-10-03).** Antes, una
  lista `<select>` (país, mes, cantidad) no se podía usar: escribir en ella fallaba y el modelo solo
  podía pedir a la persona que eligiera. Ahora `browser_select` elige la opción por la etiqueta que
  muestra la página, como en Incredible, y si no existe responde con las etiquetas que sí hay. Elegir
  una opción que borra o envía, o en una lista de otro sitio, pregunta antes; una lista sensible
  (vencimiento de tarjeta) se rechaza. Solo por etiqueta: el modelo nunca ve los valores internos, y
  un valor dejaría elegir una opción cuya etiqueta nadie revisó.
- **Base para que Companion suba un archivo a una pagina web (2026-10-03).** Solo la parte de la app:
  la regla que decide que archivos se pueden subir (bajo tu carpeta personal, nunca `Library`, Fotos,
  llaves ni archivos ocultos, hasta 20 MB) y la hoja de aprobacion que lo pregunta cada vez. La herramienta
  todavia no esta conectada; borrador pendiente de las decisiones de Karen (ADR 010 propuesto).
- **La extension del navegador ya sabe poner un archivo en un campo de subida (2026-10-04).** Solo la parte
  de la extension: encuentra el campo de la ultima lectura (un solo campo en todo el documento, nunca dentro
  de un frame), comprueba que sea un campo de archivo y le pasa la ruta al navegador, que lee el archivo. Si
  la pagina navego a otro documento u otro origen en el medio, no sube nada; si falta el permiso de acceso a
  archivos lo dice. Todavia no esta conectada a Companion; borrador. `browser_read` ahora reporta los campos de archivo con el rol "file".
- **Companion puede pedir subir un archivo tuyo a una pagina (2026-10-04).** La herramienta `browser_set_files`
  pone un archivo en un campo de subida de la ultima lectura, siempre tras la hoja de aprobacion, sin recordar
  el si ni aceptar un si hablado, y nunca envia el formulario. No se ofrece a agentes externos por el puente.
  Borrador pendiente de las decisiones de Karen sobre como se ata la subida al campo correcto.
- **El trabajo del especialista es una línea de tiempo, en el chat y en el notch (2026-10-13).**
  Mientras el especialista trabaja, la conversación de la ventana muestra el agent-run de Arc en
  lugar de chips sueltos: "Trabajando" con su punto, el tiempo y los pasos en orden sobre un riel
  que se llena, cada uno con lo que hizo y cuánto tardó. Al terminar todo se pliega en "Trabajó
  36s · 5 pasos" (o "Detenido · ..." si se paró) y se despliega con un clic. La tarjeta de
  resultado del notch muestra la misma corrida en compacto: los tres pasos más nuevos y el resto
  plegado. No hay botones de pausar ni reintentar porque Companion no tiene esas acciones. La
  corrida vive mientras dura la sesión: una tarea abierta desde el disco no la muestra.
- **La conversación de la ventana es el ai-chat de Arc (2026-10-13).** "Seguir en el chat" ya no
  deja la ventana en Inicio: abre la conversación de esa respuesta. Ahí cada respuesta se lee
  como en Arc: el texto llega palabra por palabra, la altura crece con un resorte, las tablas,
  listas y código se ven como tales (y las tarjetas `companion:` siguen dibujándose), las
  herramientas que usó son chips que se abren con su detalle, lo que pensó el especialista se
  pliega en "Pensó X s", y las fuentes son citas numeradas con su tarjeta y una lista de
  "N fuentes". Copiar la respuesta funciona; no hay botones de regenerar ni de modelo porque
  Companion no los tiene.
- **En voz clasica puedes contestar de voz a la pregunta de permiso (2026-10-02).**
  Cuando Companion ya te pregunto en voz alta por un permiso, mantener la tecla otra vez
  contesta esa pregunta en vez de cortar lo que estaba haciendo. Si dices "si", te recuerda
  que hace falta tu clic y la hoja sigue ahi esperandolo: un "si" hablado no aprueba nada
  por su cuenta. Si no dices nada, la hoja sigue igual. Si dices otra cosa, la accion no se
  hace, la hoja se retira y Companion atiende lo que dijiste. La tecla de dictado sigue
  escribiendo, no contesta.
- **Una prueba de la respuesta por voz a un permiso ya no falla al azar (2026-10-02).** La app no
  cambia: la prueba asumia un solo orden entre tu clic y soltar la tecla, y con la Mac cargada
  llegaba el otro, que tambien es correcto (la accion se hace una vez y lo que dijiste llega
  como un turno nuevo).
- **En voz clasica, Companion pregunta en voz alta cuando una accion espera tu permiso (2026-10-02).**
  Si mantienes la tecla y Companion necesita tu permiso para algo (abrir una pagina que no
  dijiste, usar tus manos), ahora se calla y te lo pregunta en una frase, en vez de quedarse
  pensando en silencio frente a la hoja. Cuando haces clic, sigue y te dice el resultado. Si
  pulsas y dices otra cosa, o lo detienes, la accion no se hace y la hoja se retira. Un "si"
  hablado todavia no aprueba nada: el permiso sigue siendo tu clic.
- **Las lecturas de terminal corren sin hoja, como en Incredible (2026-10-03).** `ls`, `cat`, `git status` y
  otras lecturas simples ya no piden aprobacion; todo lo que puede cambiar algo, lo compuesto y lo que toca
  secretos (`.ssh`, `.aws`, `.env`, llaveros) sigue pidiendo hoja, y `git` solo pasa si la config del repo
  no puede ejecutar nada.
- **Companion puede listar y restaurar las versiones guardadas de un archivo.** `list_file_history`
  muestra, de la mas nueva a la mas vieja, cada version con su id, la hora y si se guardo antes o
  despues de un guardado, sin revelar nunca la carpeta privada. `restore_file_version` devuelve una
  version anterior sobre el archivo existente despues de que apruebes la hoja; antes guarda una copia
  de lo que hay ahora para poder deshacerlo, y si esa copia no se puede hacer no restaura nada.
- **Las manos ahora abren y esperan, aceptan atajos y respetan la pantalla bloqueada (2026-10-02).** `open_app` espera a que la app tenga ventana y fija el turno a ella (plazo 10 s, luego `window_not_ready`); `press_key` acepta un puñado de atajos seguros (cmd+n, cmd+f, cmd+l, cmd+t, cmd+z, cmd+shift+n) y rechaza el resto con la ruta por menu; un item de menu en gris da `menu_disabled` en vez de un falso exito; `scroll` va tambien a izquierda y derecha y trae un control a la vista; y con la Mac bloqueada ninguna mano actua (`screen_locked`).
- **Companion ya puede borrar un archivo o carpeta, siempre despues de que lo apruebes (2026-10-03).**
  La nueva herramienta `delete_file` lo manda a la Papelera, donde puedes recuperarlo; solo si macOS
  no deja moverlo a la Papelera lo borra de forma permanente, y la hoja de aprobacion y el modelo lo
  dicen. Nunca recuerda el si: cada borrado pregunta. No toca carpetas directas del home, `Library`,
  entradas ocultas ni la memoria, las skills y el conocimiento de la propia app.
- **Las manos ahora dicen que cambio despues de actuar (2026-10-02).** Tras un clic, un menu, escribir o pulsar una tecla, Companion espera cerca de 1 s a que la app se asiente y agrega al resultado una linea: ventana o dialogo nuevo, titulo distinto, o "no se observo cambio, no repitas la accion". Antes el modelo solo recibia "mira de nuevo".
- **Lo que se toca mientras se sostiene la tecla ya tiene modelo (2026-10-03).** Cada observacion (pestana, ventana, clic, texto seleccionado, archivos, copiado, dialogo) se vuelve un item como en Incredible; archivos, selecciones y copias se apilan de a tres y se tejen en la transcripcion donde llegaron.
- **El hold ve tambien la pagina del navegador y los dialogos que se abren, como Incredible (2026-10-03).** Pasar a otra pestana destella con su titulo o su sitio; un dialogo que se abre (Guardar, Imprimir) destella sin contar como otra ventana. De la direccion solo se guarda el sitio: ni ruta, ni consulta, ni fragmento, ni credenciales.
- **Mientras se sostiene la tecla, Companion ve a donde vas y que copias, como Incredible (2026-10-03).** Cada cambio de app o ventana destella en la pildora del cursor y cada texto copiado se apila sobre ella y entra en la transcripcion donde iba la voz. Solo durante el hold; lo que marca un gestor de contrasenas nunca se lee, y nada de lo observado va a los logs.
- **La isla muestra que clase de trabajo hace, y sus palabras se transforman (2026-10-13).** Mientras
  espera, piensa, actua o corre una tarea, el orbe de la isla pasa a ser el orbe de particulas de Space UI
  con una forma por estado: un anillo que respira al enviar, una esfera que gira por rebanadas al
  pensar, un globo que barre al buscar en apps y hebras que se trenzan durante una tarea; la voz conserva
  su orbe al escuchar y hablar, y el cambio entre uno y otro es un fundido, sin saltos. La linea de
  estado pasa de "Enviando…" a "Pensando…" a "Listo" letra por letra (text-morph de Arc) y el destello
  sobre "Pensando…" es el de text-shimmer de Arc: una banda tranquila que descansa entre pasadas y se
  asienta en texto solido al terminar. Con Reducir movimiento el orbe queda quieto y las palabras cambian
  sin animacion.
- **Nuevo ajuste "Silenciar el sonido mientras hablas" (2026-10-03).** En Ajustes, junto a los
  sonidos, puedes pedir que la musica y los videos se callen mientras Companion te escucha y vuelvan
  cuando sueltas la tecla. Viene apagado. Todavia no silencia nada: el ajuste, la decision y el
  cableado ya estan; el silenciado real llega en el siguiente paso.
- **Dibujos que explican cada permiso (2026-10-03).** Hay un dibujo propio, sin imágenes, para micrófono, accesibilidad, grabación de pantalla y reconocimiento de voz. Muestra dónde se concede cada uno y quedan listos para acompañar las filas de permisos de la bienvenida.
- **La barra lateral muestra los modulos que faltan, como en Incredible (2026-10-05).**
  Debajo de "Personalizar" aparecen Navegador y Conocimiento, y un grupo nuevo "Superpoderes" con
  Tareas guardadas, Programadas, Autopilot y Dictado. Cada uno abre una pagina honesta: su icono,
  para que servira y "Todavia no esta en Companion", sin botones que no hagan nada. Al pasar de un
  modulo a otro el texto sube y el icono cambia con un desenfoque breve (estado vacio de Arc); con
  Reducir movimiento solo se funden. Si la lista de apps no esta disponible, Apps vuelve a mostrar
  Inicio como antes.
- **Companion pasa a modo pasivo tras 10 minutos sin interaccion, como Incredible (2026-10-03).** Cualquier interaccion (sostener o tocar la tecla, pasar sobre la isla, escribir, responder una hoja, detener) lo vuelve activo; lo que Companion hace por su cuenta no cuenta. Todavia no cambia nada en pantalla: es la base de que una respuesta en pasivo no abra la isla.
- **Accion "Restablecer permisos de Companion" lista para Ajustes (2026-10-03).**
  Borra, servicio por servicio, los permisos de privacidad que Companion pidio (microfono, reconocimiento de voz, grabacion de pantalla, accesibilidad, monitoreo de entrada, contactos y automatizacion) y reinicia la app para pedirlos de nuevo; si un reinicio de permiso falla, no reinicia. Falta que Ajustes monte la fila.
- **El puente ya deja pasar las preguntas de un agente sobre Companion (2026-10-02).** Las seis
  consultas de solo lectura entran en la lista del puente, gastan del cupo de lectura y piden la
  misma hoja de sesión que cualquier otra herramienta. Con Companion al frente responden, y las manos
  siguen sin poder tocarlo. La app todavía no las conecta, así que nada cambia para ti.
- **Base para que un agente revise a Companion sin tocarla (2026-10-01).** Queda definido, en
  el núcleo, qué podrá ver un agente conectado por el puente: el estado de la sesión, lo que
  pinta la isla, tus ajustes no secretos y el hilo activo solo como metadatos. Nunca verá lo que
  escribes ni lo que dices, ni claves; solo si tu último mensaje es igual a un texto que él ya
  conoce, con tope de 10 consultas por minuto. Todo es de solo lectura. Todavía no se sirve nada:
  la app se comporta igual. Se registra como ADR 009.
- **La isla y la ventana anotan lo que muestran (2026-10-02).** Cada vez que la isla se pinta, o que
  cambias de página o de pestaña de Ajustes, Companion guarda una copia de eso para que, más adelante,
  un agente pueda revisar lo que de verdad se vio. Guardarla no redibuja nada, y nadie la lee todavía,
  así que la app se ve y se comporta igual.
- **La pieza que contesta las preguntas del agente sobre Companion (2026-10-01).** Ya existe la
  parte que lee el estado, la isla, los ajustes, el hilo y las últimas líneas del log principal, y
  responde solo con metadatos. Del log salen como mucho 200 líneas, siempre marcadas como datos y
  nunca como instrucciones; el log de transcripciones no sale nunca. La comparación con tu último
  mensaje gasta su cupo aunque la consulta venga mal formada, y los nombres que llegan de fuera (el
  del agente y el de una herramienta MCP) se recortan. Todavía no está en la lista del puente, así
  que la app se comporta igual.
- **La parte de la ventana que deja leer a Companion por dentro (2026-10-02).** Ya existe la pieza
  que junta el estado de la sesión, tu hilo, tus ajustes y un espejo de lo que la isla y la ventana
  muestran. Lo que escribes solo viaja como dato interno que nunca sale tal cual, y el título de la
  conversación no entra. Nadie la usa todavía, así que la app se comporta igual.
- **Con 'Prestar las manos' encendido, un agente puede revisar Companion aunque esté al frente (2026-10-02).** Solo mira: no pulsa, no escribe y no ve lo que escribes. Las manos siguen sin tocar Companion.
- **Las caras de ánimo del formulario de comentarios ya son caras, como en Incredible (2026-10-03).**
  "Frustrado", "Decepcionado" y "Neutral" se mostraban con un signo de exclamación, una mano hacia
  abajo y un signo menos, porque SF Symbols no tiene esas caras. Ahora son caras dibujadas al estilo
  de SF: círculo, ojos y una boca cuya curva dice el ánimo (cejas fruncidas en la enojada, boca recta
  en la neutral, arco hacia abajo en la triste). Tienen el mismo tamaño y grosor que la cara sonriente
  a su lado y siguen el color del texto.
- **Etiqueta de estado con el estilo de shadcn (2026-10-02).** "Conectada" en las tarjetas y el panel
  de Apps ahora es una etiqueta (badge) de cápsula con su punto de estado, con las variantes de
  shadcn disponibles para el resto de la app.
- **Conversación con el estilo de shadcn (2026-10-02).** En el detalle de una tarea, tu mensaje es una
  burbuja negra a la derecha y la respuesta una burbuja gris a la izquierda (80 % del ancho máximo), y
  el hilo abre con un marcador de hora con filetes.
- **Botones con el estilo de shadcn (2026-10-02).** Los botones de la ventana principal, Ajustes y
  Apps pasan a las variantes de shadcn (principal, secundario, borde, fantasma, destructivo y
  enlace) con sus tamaños, hover, foco con anillo de 3 pt y estado deshabilitado, todo sobre los
  tokens de espaciado y color que ya existen. Los botones de quitar en Ajustes ahora son rojo sólido.
- **Orbe de pensamiento de Space UI en Inicio (2026-10-02).** La tarjeta "mantén fn" de Inicio ahora
  muestra una de las nueve orbes de partículas de Space UI según lo que hace la voz (reposo, conectando,
  escuchando, pensando, hablando o error); con reducir movimiento queda quieta.
- **Companion ya distingue un "no" hablado claro (2026-10-02).** Es la base para que puedas
  rechazar de voz una peticion de permiso: reconoce respuestas cortas como "no", "no gracias",
  "mejor no" o "cancela", y no confunde con un rechazo un "no se", un "¿no?" ni una frase larga.
  Todavia no cambia nada de lo que ves ni oyes: el rechazo de voz se conecta en el siguiente paso.
- **En voz clasica puedes rechazar de voz un permiso (2026-10-02).** Cuando Companion ya te
  pregunto en voz alta por un permiso, mantener la tecla y decir un "no" claro ("no",
  "no gracias", "mejor no", "cancela") lo rechaza sin clic: la accion no se hace y Companion
  te contesta con una sola frase, sin seguir hablando. Un "no se" o un "¿no?" no cuentan como
  rechazo: se toman como algo nuevo que dijiste. Si rechazas con el boton de la tarjeta, todo
  sigue como antes.
- **Tareas vivas en Inicio y en el detalle (2026-10-06).** Cada tarea muestra su estado real (en curso, hecho o falló) y cuánto duró o lleva, en su fila de Inicio y en "Detalles" de su hoja. Antes la conversación no guardaba su estado de trabajo; las tareas anteriores no muestran nada.
- **Base para pedirle a Companion que hable más rápido o más lento (2026-10-01).** Todavía no
  cambia nada en la app: esta entrega solo deja listas las piezas internas (cuánto se acelera
  cada voz, sus límites y el aviso corto que dirá al cambiar). La función completa llega en los
  siguientes cambios.
- **En modo pasivo, lo que dice la voz aparece en un chip bajo la isla, como en Incredible (2026-10-03).** Muestra una oracion a la vez, enrolla a la siguiente mientras habla, se expande con el puntero y un clic abre la isla en el mismo turno. Se queda 6 s al terminar y sale en 260 ms.
- **Música suave durante la bienvenida, con botón para callarla (2026-10-03).** En las
  pantallas de claves, permisos y la tecla suena un pad ambiental generado por la propia app
  (sin archivos de audio ni licencias), con entrada y salida suaves; no suena en la portada, el
  saludo, la prueba de micrófono ni en "Tu turno". Un botón de 40 pt abajo a la derecha la
  silencia; con VoiceOver activo empieza callada. Respeta el volumen y el silencio del sistema.
  Como la música de la bienvenida de Incredible 0.2.36.
- **Un destello de señal cuando Companion saluda por primera vez (2026-10-03).** Al empezar el
  saludo de la bienvenida, un halo azul suave sale del borde superior de la ventana y se
  desvanece en 0,7 s, como el `fr-burst` del momento en que habla el orbe en la intro de
  Incredible 0.2.36. Con Reducir movimiento no aparece. No intercepta clics ni lo lee
  VoiceOver.
- **La bienvenida revisa que se oiga antes de hablar (2026-10-03).** Si el volumen de la Mac
  está por debajo de 15 de 100 (o en silencio), antes del saludo aparece una tarjeta oscura con
  un slider que mueve el volumen del sistema, suena un "Pop" al soltarlo, y se quita sola al
  llegar a 30 o con "Ya escucho a Companion" / "Continuar de todos modos". El silencio del
  sistema se respeta: el slider no lo quita. Igual que la prueba de sonido de Incredible 0.2.36.
- **Testimonios junto a las claves en la bienvenida, listos pero apagados (2026-10-03).** Con la
  ventana de 720 pt o más, la pantalla de claves se parte 9:11 y a la derecha aparece una
  tarjeta con citas que rota cada 10 s, se pausa con el puntero encima, con el foco dentro, con
  la app en segundo plano y siempre con Reducir movimiento; los puntos eligen la cita. Como el
  carrusel junto al registro de Incredible 0.2.36. Sale apagado: las cuatro citas son de ejemplo
  y `welcome.testimonials.enabled` se pone en "1" solo cuando haya citas reales, con permiso de
  quien las dijo.
- **La respuesta se enciende cuando la voz dice cada palabra (2026-10-03).** Con la voz en vivo, cada
  palabra de la isla se enciende en el momento en que de verdad se escucha, no a tres palabras por
  segundo; la respuesta aparece desde la primera palabra, se asienta 600 ms despues de que termina el
  audio y se borra al interrumpirla. La voz en vivo no da tiempos por palabra, asi que se estiman del
  audio y se calibran con cada respuesta. Sin voz (respuestas escritas, voz clasica) sigue el ritmo fijo.
- **Documentos, hojas y gráficas (Wave 20, 2026-09-28).** "Hazme un PDF del
  informe" termina en un PDF de verdad, con tablas y gráficas, sin instalar
  nada; lo mismo en `.xlsx`. Companion lee y escribe en el Excel o el Numbers
  que tienes abierto, con tu aprobación, una copia del libro antes y la
  relectura de lo escrito después; rechaza fórmulas que llaman a la red o
  ejecutan algo, también disfrazadas con `+`, `-` o `@`. Las cifras, tablas
  y series llegan al chat como tarjetas con gráfica.
- **Conectores como Incredible (Wave 16k-2, 2026-09-28).** Tocar una app abre
  su panel: descripción y Conectar sin cuenta; con cuenta, las acciones en
  Leer / Crear y cambiar / Borrar según lo que el servidor declara, con
  buscador y la descripción remota visualmente distinta del copy propio.
  Conectar abre el modal con los dos iconos y el punto que viaja, consulta
  cada 3 s (40 intentos, tope duro 2.5 min — números auditados del binario
  de Incredible) y termina en "Vamos"; Reintentar pide enlace fresco. La
  página pone "Tus apps" arriba sin repetirlas en el catálogo, y Desconectar
  confirma avisando que el grant del lado de la app no se revoca solo. Cada
  intento y el panel llevan su epoch: dobles taps y respuestas tardías ya no
  pisan al intento vivo ni duplican DELETEs.
- **Las manos para Claude Code (Wave 17, 2026-09-28).** Nuevo ajuste en
  Privacidad, "Prestar las manos a otros agentes" — apagado por defecto en
  todo build. Encendido, la primera acción de una sesión del puente abre la
  misma hoja de aprobación de siempre ("quiere usar tus manos"); aprobada, la
  isla muestra el chip "Manos: Claude Code" y parpadea con cada acción de
  escritura, y "Detener manos" (en el chip y en el menú de la barra) cierra
  la sesión en un gesto. Presupuesto de 30 acciones de escritura por minuto;
  un turno propio de Karen pausa el puente y lo retoma al terminar. El shim
  que Claude Code arranca vive en el repo hermano `companion-mcp`, no aquí.
- **Página Apps (Wave 16k-1, 2026-09-25).** Personalizar › Apps como en Incredible: buscador,
  destacadas con el total, rejilla de dos columnas y "Mostrar más". "+ Conectar" abre la conexión
  de Pipedream en el navegador. La primera vez pide la dirección y la clave de tu función
  `companion-apps`; la clave queda en el llavero y nunca sigue una redirección a otro sitio.
- **La ventana como la de Incredible (Wave 16j-1/2, 2026-09-25).** Barra lateral, Inicio con la
  tarjeta "Mantén fn", primeros pasos y las tareas por día; cada tarea abre su conversación y
  "Seguir" la pasa a la isla con la etiqueta TAREA. Sin chat en la ventana ni líneas internas. La ventana es horizontal 16:10 (1120×700) como la de
  Incredible, en vez de la columna 2:3 del chat.
- **La isla más útil, primera parte (Wave 16i-1, 2026-09-25).** El panel ya no se ve abierto y
  vacío: el contenido entra con el panel y se va con él. Al pasar el ratón la muesca se asoma con
  rebote y sombra como NotchNook, y solo abre si el puntero se queda 150 ms. El menú "…" y el nuevo
  volumen de la voz son popovers propios, oscuros, que crecen desde su botón; tooltips en hablar,
  enviar y volumen. Mientras habla, el orb es el botón rojo de parar, y al parar sale "Cancelado".
  "No te oí" y los avisos con salida son tarjetas con icono, anillo de cuenta atrás y botón.
- **Movimiento suave en toda la app (Wave 16f-2, 2026-09-25).** Ocho reglas de smooth motion
  (spec 16f §9) con test: una sola curva de entrada, resortes casi sin rebote, cerrar más rápido
  que abrir, desenfoques y desplazamientos chicos, escalonado de 40 ms y reducir movimiento como
  fundido corto. En la isla, la línea de estado cambia con un deslizamiento suave, las palabras se
  aclaran una a una, las tarjetas entran escalonadas, la luz de "hecho" aparece con un rebote leve y
  la hoja de aprobación sube. Ninguna vista puede escribir su propia curva.
- **La isla nace del notch (Wave 16f, 2026-09-25).** En reposo es la muesca; al pasar el ratón se
  estira en dos tiempos (píldora y panel) con los resortes medidos en la grabación de Incredible, y
  el contenido entra después con fundido y desenfoque; al cerrar, al revés. La ventana ya no se
  mueve: crece la forma. Los clics pasan a la app de atrás fuera de la forma. La respuesta se lee en
  grande y sus palabras se aclaran al ritmo de la voz; tres huecos de tareas arriba a la derecha.
- **Ajustes con la forma de Incredible (Wave 16g, 2026-09-25).** Hoja con barra lateral y buscador
  (sin acentos, es/en, salta a la fila y la ilumina); siete páginas: General, Voz, Vocabulario,
  Memoria, Tú, Privacidad, Sistema; tarjetas blancas de filas con el control al final. Vocabulario
  como lista con ejemplo y "Añadir palabra". Memoria nueva: ves lo que Companion guardó y olvidas lo
  que quieras. Sistema con zona de peligro. Siguen 14 opciones. Seguridad: la memoria ya no lee
  enlaces simbólicos (ni archivos ni carpetas), que podían meter cualquier archivo tuyo en el prompt.
- **UX como Incredible (Wave 16c–16e, 2026-09-25).** La isla es la app: al pasar el ratón,
  campo "Pídele algo a Companion…", adjuntar, enviar, menú de 5 y tus últimas respuestas como
  tarjetas; luz ámbar cuando te necesita y verde al terminar; al escuchar solo barras y lo que va
  oyendo; "no te oí" se va a los 6 s; los errores traen su salida. Bienvenida de 7 pantallas con
  los 4 permisos en una, medidor de micro y un hold real al final. Ajustes en 3 pestañas con 14
  opciones y sin jerga; palabras que el oído debe entender bien; menús en tu idioma; icono en la
  barra de menús. Geist como tipografía. Permitir en una hoja ya no responde a Return.
- **Vista y click como Incredible (Wave 16a, 2026-09-25).** `look` lee la ventana de delante como
  una lista numerada de sus controles y texto; `click` pulsa por número (acción del elemento, foco
  o click de ratón enviado a esa app, sin mover tu puntero); `scroll`, `menu` ("Archivo > Exportar
  como PDF…") y `see` (captura descrita, solo cuando se pregunta por algo visual). Las apps Electron
  y Chromium se preparan al pasar al frente para que muestren su contenido. Pulsar "Permitir" o
  "Aceptar" va directo; borrar, pagar, suscribir, enviar o publicar piden confirmación salvo que lo
  pidieras con esa palabra; un icono sin nombre o el "Sí" de un diálogo de borrar también la piden.
  La visión ya no corre en cada turno (ahorra 3,3–3,7 s). El asistente puede encadenar hasta 8
  acciones por turno.
- **El especialista ya no pide permisos (Wave 16b).** Claude Code corre en modo `auto` con una lista
  de prohibidos (sudo, git push, borrar el disco o tu carpeta, curl/wget a una shell, AppleScript);
  lo que aún pregunte se niega solo, sin hoja.
- **Manos sobre la pantalla (Wave 15g, 2026-09-25).** El asistente escribe,
  pulsa una tecla, trae una ventana al frente y lee el campo enfocado de la
  app que tenías delante (`type_text`, `press_key`, `focus_window`,
  `read_focused`), por Accesibilidad y sin subagente ni AppleScript. Se
  ofrecen solo con Accesibilidad concedida y nunca con Companion delante.
  Lo que escribe o envía se ata a lo que dijiste: en terminales y apps de
  agentes, Return siempre pide confirmación y solo se escribe sin preguntar
  una línea que dijiste; en el resto, Return va directo si pediste enviar y
  una dirección que no dijiste pide confirmación. Actúa sobre la app que
  tenías delante al hablar (salvo que en el turno pidas abrir otra). El
  prompt dice actuar en vez de instruir, y la visión ya no bloquea cada
  turno: si llega tarde viaja al siguiente, solo en la misma app y 30 s.
- **Boca sin huecos, con voz de verdad, y sin leer JSON (Wave 15f, 2026-09-25).**
  ElevenLabs (Flash v2.5, voz Ana María, elegida a ciegas entre 6 candidatas)
  como boca del hold cuando hay clave: primer byte en 180–210 ms frente a
  500–700 de OpenAI; OpenAI (alloy, `speed 1.1`, `instructions`) de respaldo,
  con cortacircuito de 60 s si ElevenLabs falla y pausa hasta clave nueva en
  401. La frase N+1 se pide mientras suena la N (una en vuelo por delante).
  Un `{"goal":…}` escrito como texto por el modelo ya no se pronuncia: si es
  eco de la pantalla o del portapapeles se descarta; si no, se propone
  ("¿Lo delego?") y solo corre con tu sí. Una frase de razonamiento en otro
  idioma se descarta; las citas, errores y traducciones se respetan. El
  encargo al especialista se anuncia con una frase fija y un resumen de dos
  frases, nunca con el prompt literal. Ajustes: fila ElevenLabs en Claves y
  selector de voz con 6 presets, id libre y muestra. Timeline: `firstCut→
  ttsRequest`, `ttsRequest→firstByte`, `firstByte→audible`. Cerebro: se
  queda Cerebras gpt-oss-120b (banco: 299 ms TTFT, cero fugas con frases
  sueltas). Medido en vivo: soltar→audio 1,0–1,2 s en turnos sin tool.

### Security
- **El reposo de 0,6 s de la hoja de permiso ahora cuenta desde que termina de aparecer (2026-10-03).**
  Antes arrancaba al llegar la peticion, y como la isla crece primero (unos 120 ms), el contenido
  aparece despues y la hoja se revela encima (hasta 0,3 s), parte del reposo se gastaba con la hoja
  invisible o a medio mostrar: veias los botones menos de 0,6 s antes de que aceptaran clics. Ahora
  el reloj arranca cuando el contenido es visible con una peticion pendiente y ha acabado la
  revelacion; si se oculta y reaparece, o llega otra peticion, empieza de nuevo. Ademas, la guarda
  solo responde a la peticion para la que se armo. Un clic con la hoja invisible sigue ignorandose.
- **La hoja de permiso ya no recibe clics mientras es invisible (2026-10-03).** Al crecer la isla
  (unos 120 ms) el contenido aparece desde transparente, y los botones de permiso ya aceptaban
  clics sin que pudieras verlos. Ahora un clic con el contenido aun invisible se ignora, no
  responde ni gasta la espera, y la hoja no recibe clics hasta que se ve. La espera de 0,6 s y
  el ligado al identificador de la peticion se conservan.
- **Las lecturas del navegador salen sin secretos ni instrucciones ocultas (2026-10-05).**
  Antes, la extension de Companion enviaba la URL de la pagina y los enlaces tal cual, asi que un
  token, un codigo de un solo uso o una firma podian aparecer en cualquier lectura. Ahora el valor
  de un parametro sensible se cambia por `redacted`, en la consulta y en el fragmento (tambien en
  rutas con `#/ruta?token=...`). Cuenta el nombre completo o su final (`token`, `access_token`,
  `apikey`, `client_secret`, `sessionid`, `code`, `state`, `sig`, `otp`...) y cualquier nombre que
  contenga `token`, `secret`, `passw`, `credential` o `signature`; se lee aunque venga codificado,
  con `[]` o separado por `;`. Tambien se oculta cualquier valor con forma de JWT y las URLs
  anidadas dentro de otro parametro (hasta dos niveles), y se borra `usuario:clave@`. Lo mismo se
  aplica a las URLs escritas dentro del texto visible (etiquetas, contexto, valores, titulos y
  texto de la pagina).
  Los textos que vienen de la pagina (etiquetas, contexto, valores, nombres de campo, rol, titulos,
  texto y mensajes de error) pasan por un limpiador que quita caracteres invisibles o que
  reordenan el texto, para que un sitio no esconda instrucciones al modelo ni falsifique el
  encabezado de un marco. Limites conocidos: un secreto dentro de la ruta de la URL (que no sea un
  JWT) no se detecta, y un secreto sin forma de URL dentro del texto visible no se cambia. El
  control de `stale_id` sigue usando la URL real del elemento.
- **Escribir en un campo ya no deja caer el texto en otro si la página le quita el foco (2026-10-03).**
  La extensión comprobaba que el campo no fuera sensible (contraseña, tarjeta) antes de enfocarlo,
  pero no que el foco se quedara ahí: un manejador de foco de la página podía moverlo a otro
  campo, incluso a uno sensible, y el texto se escribía en ese. Ahora, justo antes de escribir, se
  verifica el elemento activo (también dentro de shadow roots; un contenteditable acepta que el
  cursor esté en un hijo) y, si el foco se movió, no se escribe nada: `secure_field` si fue a un
  campo sensible, `stale_id` si no. Vale para el texto de una línea, el multilínea y las teclas
  de confianza. Queda una ventana de milisegundos entre la preparación y la primera tecla
  (anotada como HACK en el código).
- **Un permiso que diste para una acción que interrumpiste ya no queda guardado (2026-10-01).**
  Si decías "sí" a una acción y justo después la interrumpías (o cerrabas la conexión que la
  pidió), Companion no la hacía, pero ese "sí" seguía valiendo hasta un minuto para otra
  petición idéntica. Ahora el permiso se descarta junto con la acción, en voz clásica, en
  tiempo real, en el chat escrito y en el puente con otras apps.
- **El carrete limpia el nombre que elige el modelo (2026-10-03).** Quita los caracteres invisibles
  (de control, bidi, de ancho cero y glifos en blanco), que podian esconder parte del nombre a la
  vista o a VoiceOver. Los saltos de linea pasan a ser espacios, y el nombre se corta a 60 caracteres
  con "…" y con un tope para las marcas combinantes. La pastilla y VoiceOver muestran lo mismo.
- **Campos de contraseña de verdad detectados (15g).** El dictado (12e), la
  lectura de pantalla y las manos comparaban el rol con `AXSecureTextField`,
  que es un subrol: un `NSSecureTextField` real nunca se reconocía. Ahora se
  miran rol y subrol en un solo sitio.
- **El portapapeles de un gestor de contraseñas no entra al contexto (15g).**
  Contenido marcado `org.nspasteboard.ConcealedType` o `TransientType` se salta.
- **La red ya no deja claves en disco (15f).** `URLSession` guardaba en
  `~/Library/Caches/<bundle>/Cache.db` las peticiones a OpenAI, Cerebras, Groq
  y ElevenLabs con sus cabeceras de autorización y cuerpos (conversación,
  texto de pantalla y portapapeles). Todos los caminos de red usan ahora una
  sesión sin cache ni cookies; el cache viejo se purga al arrancar y un gate
  estático impide que vuelva. Hay que rotar las claves que estuvieron ahí.
- El log de depuración de transcripts redacta también claves `sk_`; el id de
  voz de ElevenLabs se valida antes de tocar la red o el Keychain.

### Added
- **Oye la frase entera y sin Groq (Waves 15d y 15e, 2026-09-24).** El
  micrófono abre al bajar FN (antes esperaba 250 ms de umbral + 200 ms de
  arranque: media frase perdida) y deja una cola de 300 ms al soltar; un
  tap descarta el audio en memoria sin que nada salga de la máquina. El
  oído es `SpeechAnalyzer` de Apple en el dispositivo (final a 23–39 ms
  tras la cola; spike: 54 ms p50 frente a 430 ms de WhisperKit y 500–750 ms
  de Groq), con tu nombre y tus apps como vocabulario. Groq desaparece:
  ni oído, ni cerebro, ni fila en Ajustes; una clave guardada antes se
  purga sola del Keychain. Cerebro del hold: Cerebras gpt-oss-120b, y si
  falla OpenAI gpt-4o-mini. Un hold sin voz vuelve a reposo con el
  micrófono apagado. Instrucción de idioma delante del transcript, prompt
  de voz al estilo "router con voz" (dos frases, sin markdown), primer
  corte de la boca a la coma / 40 caracteres / 400 ms. Modo depuración
  opt-in `COMPANION_DEBUG_TRANSCRIPTS=1`: `heard=`/`said=` en
  `~/Library/Logs/Companion-transcripts.log` (0600, claves redactadas,
  borrado al arrancar sin la variable) con aviso en la barra de estado y
  la island. Plataforma mínima: macOS 26. Medido en vivo (22 holds):
  `release→earFinal` p50 360 ms; `release→audio` p50 1,65 s — el tramo que
  queda es la boca (TTS 730 ms p50), siguiente wave.

### Added
- **Dicta en el campo donde está tu cursor (Wave 12e).** La misma tecla,
  otro destino: con un campo de texto de otra app enfocado (Slack, Notas,
  Safari), mantener FN y soltar pega ahí lo que dijiste; la island dice
  "Dictando en Slack" con el parcial y luego "Pegado en Slack"; nada
  viaja a la conversación ni al log (solo cuántos caracteres y dónde).
  Sin campo, con una contraseña, con Companion delante o sin el permiso
  de Accesibilidad, el hold habla con Companion como siempre. Ajustes ›
  App › HABLAR gana "Al mantener FN": Automático (por defecto), Hablar
  con Companion, Dictar; cuando puede dictar y falta Accesibilidad, la
  fila del permiso aparece ahí mismo. El texto entra por Accesibilidad
  (texto seleccionado del elemento enfocado) y, si la app lo ignora, por
  el portapapeles con un Cmd+V, devolviendo después lo que había en el
  portapapeles, de todos los tipos y solo si nadie más lo tocó mientras
  tanto. Nunca en un campo seguro, nunca en una app distinta de la que
  estaba delante al pulsar. Preguntar por el campo no retrasa el
  micrófono: va en su propia tarea, con tope de 0,25 s por llamada.
- **La island ya no enseña una tecla muerta (12e).** Sin el permiso de
  Monitoreo de entrada, pasar el ratón dice "FN está apagada. Clic para
  permitirla" en vez de "Mantén FN para hablar"; el clic abre la ventana.
- **El oído deja de escribir lo que oye en el log (12e).** Las líneas
  `ear: hearing` y `ear: segment` cuentan caracteres, nunca palabras.
  Cierra la deuda abierta por la revisión de seguridad de 12b.
- **Mantén FN y habla (Wave 12b).** El micrófono ya no es un toggle dentro
  de la ventana: con Companion detrás, mantener FN abre la sesión y el
  micro, soltar envía lo que el oído nativo oyó (ForceEndpoint), un tap
  enseña el hold, mantener mientras Companion habla la calla. La tecla se
  oye con un event tap listen-only sobre `flagsChanged` (solo FN, nunca
  lo que escribes) que exige el permiso de Monitoreo de entrada, con su
  fila en Ajustes › App › HABLAR. La **island**: un `NSPanel` que no se
  activa, encima de todas las apps y en todos los Spaces, bajo la banda
  del notch: pebble en reposo (ocultable), nudge con "Mantén FN para
  hablar" al pasar el ratón, medidor en Listening, fase en Processing,
  fila del encargo con Stop, y la hoja de permiso hospedada ahí mismo.
  Cerrar la ventana principal ya no cierra la app; el Dock y el pebble la
  traen de vuelta. `Cmd+Opt+Space` sigue como manos libres.
- **Los contratos del HUD, ejecutables (Wave 12d).** Nada cambia en
  pantalla. Las puertas del auditor de la spec de producto (hold sin abrir
  main, la island solo escucha, cuatro kinds, Stop es Idle y los hijos
  mueren, las cards no son la conversación, el encargo tiene fila, sin
  cuerpo de skill en el historial, sin actor de permisos se deniega, una
  hoja tiene un solo anfitrión) viven en `conformance/hud-gates.json`: cada
  puerta cita los tests que la prueban y `hudGatesTests` falla si cita uno
  que ya no existe o que nadie llama, o si el libro pierde una puerta. La
  regla `session-kind-write` cubre los once campos de la proyección (y
  `+=`, subíndice, `insert`) y la nueva `main-activation` impide que la
  UI active la app por cualquiera de sus formas (`activate(options:)`,
  `makeKey()`, `orderFront(` incluidas). La denegación del padre es un
  `ContractError` (`denied_by_user`) con el mismo texto de siempre para
  el modelo, fijado como string literal en las pruebas.
- **Ver lo que oye (Wave 12c).** Mientras mantienes FN la island muestra
  el texto que el oído va reconociendo, y lo conserva en "Enviando…"
  hasta que Companion empieza a pensar. El oído arranca al pulsar, en
  paralelo con el socket: la primera palabra de un hold ya no se pierde
  en el handshake. Un hold es un solo turno: una pausa dentro del hold ya
  no envía (al soltar viaja lo que el oído lleva oído desde la
  pulsación: la tecla es dueña del turno y el VAD del servidor no cierra
  ni abre turnos mientras dura la sesión del hold). Cada hold deja en el
  log una línea `voice timeline:` con
  press→mic, press→ear, press→ready, press→partial, release→commit y
  commit→audio en milisegundos, y el arranque una línea `prewarm:` con lo
  que se preparó antes del primer hold (motor del micro si ya tiene
  permiso, red; nunca el llavero ni un permiso). La pista "Mantén FN para hablar" del hover se
  enseña hasta el primer hold completado; un tap la pide siempre.
- **Revisiones de la 12b (2026-09-06).** Seguridad: una sesión abierta
  por un hold que reposa con el micro cerrado cuelga sola a los 20 s (el
  micro físico seguía tomado con la ventana cerrada); el pebble no se
  oculta mientras la voz vive; la hoja de la island ignora el clic que ya
  iba en camino (0,6 s). Código: una pulsación durante una suelta manda
  (la suelta tardía se descarta); re-pulsar mientras conecta ya no deja
  el micro cerrado; la hoja tiene un solo anfitrión (main si es key, si
  no la island); el tap de FN guarda puerto y run loop bajo un lock y se
  para al salir.
- **El reductor de sesión (Wave 12a).** Un estado para toda la sesión, no
  tres: `SessionMachine` en Core (kinds Idle / Hover / Listening /
  Processing con fases Pending, Thinking, Speaking, ToolExecuting,
  SubAgentRunning, Completed) observa la máquina de voz y suma lo que ésta
  no ve: el turno tecleado, las manos del padre, el encargo del especialista
  y la cola de la hoja. `SessionModel` (UI) es el único que muta la
  proyección y ejecuta los efectos (`cancelJob`, `resolveApproval`, el timer
  de Completed, el log `session: a -> b`). `VoiceSession.events` es un solo
  stream hacia fuera donde había seis closures. Cancelar y fallar vuelven a
  Idle con un `InterruptReason`; un micrófono denegado ya no deja la voz en
  un modo "error": es una card con enlace a Ajustes. Regla de conformidad
  `session-kind-write`: ninguna vista escribe el kind.
- **Skills y knowledge (Wave 11a).** Companion es un cliente Agent Skills
  (agentskills.io): `~/Library/Application Support/Companion/skills/default/`
  lleva doce skills del sistema (texto propio, sembradas desde el bundle en
  cada arranque), `skills/custom/` las de la usuaria y `knowledge/` un
  hecho por carpeta. El prompt del padre y el encargo del especialista llevan
  el catálogo `<active_skills>` / `<active_knowledge>` (nombre — descripción
  — ruta, datos con topes); el cuerpo se lee bajo demanda: `read_skill` en
  la conversación, `read_file` en el encargo. `default/` es solo lectura para
  el modelo (`denied_path`); escribir en `custom/` o `knowledge/` pasa por la
  aprobación de siempre y el resultado termina con `Skill sync: saved |
  failed — por qué | already up to date`. La memoria apunta a la skill
  knowledge-builder; `notes/` sigue leyéndose. Las cuatro skills que
  dependen de capacidades que no existen (scheduling, browser-use,
  excel-live, premium-documents) dicen lo que Companion sí puede y cierran
  con "What Companion cannot do yet".

### Changed
- Los gates comprueban el build de release y que los tests respeten las capas (2026-09-30).
- Los fakes y helpers compartidos de los tests viven en cuatro targets de soporte, uno por capa (2026-09-30).
- `JobTimeline` vive en Core (la proyección lo lleva). `ChatViewModel.job` y
  `pendingApproval` son lecturas de `session.projection`; `approvalQueue` y
  `jobHasApprovedAction` desaparecen. Negar el primer paso o pulsar Stop
  niega también las peticiones que quedaban en cola, en vez de dejarlas al
  auto-deny de 120 s.

### Fixed
- **El "sí" hablado podía conceder otra petición.** La voz resolvía su
  propio "pendiente" (un slot que se sobreescribía) mientras la hoja
  mostraba otra petición; y aprobar un `open_url` del padre desarmaba la
  regla "negar el primer paso para el encargo" (security review
  2026-09-06). Ahora la voz manda `approvalSpoken` al reductor, que
  contesta lo que la hoja muestra con las reglas de la hoja, y solo las
  peticiones del especialista cuentan como acciones del encargo.
- **Un turno tecleado abandonado dejaba el chrome pegado.** Cambiar de
  conversación o de clave con una respuesta en vuelo no cerraba el turno en
  la sesión (code review 2026-09-06).
- **La memoria no llegaba al chat tecleado.** `makeRequest` la recibía y no
  la reenviaba a `makeBody`: solo la voz realtime la veía. Medido al cablear
  el catálogo por el mismo hueco; test de regresión en
  `ChatProviderClientTests`.
- **Nada se pierde (Wave 10c).** Dos tool calls en una respuesta se fundían
  en `"read_filewrite_file"`; ahora se cosen por `index` (spec 07) y viajan
  juntas en `ChatDelta.toolCalls`: un `assistant` con todas, un `tool` por
  cada una, deduplicadas. Los argumentos rotos se evitan con `strict: true`
  en OpenAI y se reparan (lista de json_repair) para el resto; lo
  irreparable devuelve `invalid_args` con lo que el modelo mandó, nunca
  `[:]`. Los permisos esperan en una continuation (sin polling), la hoja
  tiene "Recordar durante esta sesión" (clave `Tool(patrón *)`, deny gana,
  muere con el proceso) y negar devuelve `denied_by_user`, una instrucción
  que el modelo no reintenta. `open_url` pide permiso por la misma hoja
  cuando la URL no salió de las palabras de la usuaria (3D).
- **El turno lleva contexto y fuente (Wave 10a).** El modelo recibía el
  string crudo y nada más: "resume esto" no tenía *esto*. Ahora cada turno
  viaja con un bloque `<context>` — fuente (voz/tecleado), hora, app enfrente,
  documentos abiertos y, solo si se enciende, portapapeles — enmarcado como
  DATOS, nunca instrucciones, escapado, con topes visibles, y **solo en el
  turno actual**: el historial y la memoria guardan una línea compacta
  (`[voz · Safari · 2 docs]`); el disco no guarda nada de lo sensado. Los
  sensores corren bajo un presupuesto de 150 ms y nunca retrasan el turno:
  lo que no llegó, no viaja. Accesibilidad es el único permiso nuevo, se
  muestra en Ajustes › Contexto como una fila con "Abrir Ajustes del
  Sistema" (nunca un diálogo sorpresa), y sin ella el producto es el de hoy
  más el nombre de la app enfrente. La negativa del mic también gana botón.
  Se borran `Escalation.voicePreamble` / `voiceTurnPrompt` (cero llamadores
  desde Wave 8): la pista "máximo 2 frases, sin markdown" viaja ahora en
  `<how_to_reply>` de cada turno de voz.
  Revisiones (2026-09-05): la nota de sesión lee `memoryTurns()` (palabras, sin la línea compacta ni la app al frente); los topes cuentan lo escapado y el bloque entero degrada hasta caber; los documentos se leen de la última app que no es Companion (`lastOtherPID`); el prompt dice que lo que hay en `<context>` nunca abre una URL, archivo o app por sí solo.
- **El padre actúa (Wave 10b).** El turno conversacional tenía una sola tool,
  `delegate`, así que "abre Safari" era un encargo: cola, especialista, hasta
  diez rondas de modelo, `run_shell` y una hoja de permiso para algo que la
  usuaria acababa de pedir en voz alta. Ahora el padre tiene manos propias
  — `open_app`, `open_url`, `open_file`, `list_apps` (y `find_places`, que
  ya no necesitaba disco) — sin permiso, sin subproceso: todo por
  `NSWorkspace` detrás de un puerto. Los validadores vienen de Relay con las
  dos correcciones de su review (home canonicalizado, symlink a oculto), y
  el error viaja como contrato: `denied_path: …` para que el modelo pida otra
  ruta en vez de rodearla. Chat y voz clásica hacen un loop de hasta tres
  rondas; en realtime el server ya lo hace y el cliente responde en línea.
  Cada acción deja su línea en el hilo y su `Recall` de tool en la memoria,
  como el encargo deja el suyo. El prompt deja de decir "nunca digas que no
  puedes ver el disco — delega".
- **Voz híbrida (Wave 9i): el oído transcribe, el modelo lee y habla.** El mic
  ya no llega al modelo conversacional: `gpt-live-transcribe` (sesión realtime
  de solo transcripción, con buffer de arranque para no perder ni el primer
  fonema) produce el texto, y ese texto — fiel — arma el turno. Apple es-MX
  queda como oído del pipeline clásico. Los turnos los deciden las palabras
  (el transcript crece/se asienta), no el volumen; el barge-in sigue siendo
  local y vetado. Medido en uso real: "crea un archivo de prueba en mi
  escritorio" termina en archivo real, y los turnos siguientes continúan el
  encargo.
- **El especialista alcanza toda la cuenta.** El default de alcance de 9h se
  revocó por decisión de la dueña: sin carpeta elegida, el workdir es el home
  — como el CLI. Los edits pasan solos; los comandos siguen pidiendo permiso.

### Changed
- **Un solo dueño del ciclo de respuesta realtime.** Cinco call sites de
  `response.create` corrían a ciegas contra un server que sostiene UNA
  respuesta; un turno commiteado a media respuesta era rechazado y quedaba
  huérfano. Ahora hay un embudo con prioridad: el turno del usuario preempta,
  tools y anuncios esperan.
- **El especialista actúa en vez de interrogar.** Su rol exige completar con
  defaults razonables y anotar la decisión — cada encargo moría en una
  pregunta aclaratoria que el bucle de voz no sostiene.
- **La voz no canta victoria por un rechazo.** El acuse de encargo se remite a
  lo que el especialista respondió; la orden incondicional de "di que terminó"
  convertía un "no pude" en un "listo".
- **Companion arranca sin clave.** Chat, encargos y voz por turnos funcionan
  con lo que ya corre en la Mac. La escalera de proveedores ya degradaba sola;
  el muro estaba en tres lineas del arranque y en un tag de Ollama escrito a
  mano que casi ninguna Mac tiene instalado — el probe decia que si y el primer
  mensaje moria en un 404. Ahora el modelo local se resuelve leyendo lo que hay
  (Wave 9b).
- **`list_directory`.** El especialista podia leer un archivo si sabia la ruta
  y no podia mirar alrededor sin pedir permiso por comando. Pidio "busca una
  carpeta en el escritorio" y contesto que no existia una carpeta que estaba
  ahi: no le faltaba inteligencia, le faltaban ojos.
- **`find_places` sobre MapKit**, y las tarjetas nacidas de una consulta viajan
  por su propio canal: el modelo lee nombres y direcciones, nunca coordenadas,
  asi que no puede reescribirlas mal. Las que escribe el modelo en un fence
  siguen pintandose y **dicen que Companion no las verifico**.
- **`web_search` de verdad** (Brave), como clave secundaria. Era un munon que
  siempre fallaba y aun asi se anunciaba: capturaba la intencion y se moria.
- **Parar un encargo**, con boton y por voz. `JobRunner.cancel()` existia desde
  la Wave 4 sin un solo llamador.
- **Reintento en limite de tasa** antes de bajar de peldano.

### Changed
- **Lo que se ve deja de ser lo que se recuerda.** El informe completo del
  especialista entraba en el historial como algo que el modelo de charla habia
  dicho: se comia el contexto, le ensenaba a escribir informes contra su propio
  prompt, y le dejaba releer un resultado que nunca produjo. Medido en una
  sesion real, un solo informe era el 23% del historial. Ahora vuelve como
  resultado de tool, acotado, y atado a la llamada que lo pidio (Wave 9d).
- **El trabajo va al carril que tiene herramientas**, no al que dice el
  desplegable. El prototipo ya lo hacia; el rebuild corria el encargo en lo
  seleccionado, y el default era el mas debil.
- **Pedir otra cosa mientras trabaja encola**, no cancela. La primera version
  rechazaba y salio peor: el mensaje de rechazo ofrecia "dime para", el modelo
  lo leyo como instruccion y mato el encargo vivo. Copy que llega a un modelo
  no es copy, es prompt.
- **Negar el primer paso para el encargo entero.** Negar uno posterior solo
  acota: para entonces va donde tu lo mandaste.
- **La carpeta personal deja de ser el alcance por defecto.** Se repartia el
  home entero desde el primer arranque sin preguntar. Elegirlo sigue siendo
  posible y **no se recuerda entre sesiones**, que es donde la referencia
  tambien traza la linea.
- **El historial se comprime en vez de truncarse.** Lo que salia de la ventana
  desaparecia sin rastro.
- **Una tool que no puede correr no se le ensena al modelo**, y el prompt dejo
  de prometer busqueda web sin condicion.

### Fixed
- **"No hay conexion a internet" con la red perfecta.** `noProvider` — la
  escalera agotada — se contaba como red caida, y mandaba a arreglar lo que no
  estaba roto. Mismo defecto que un 429 leyendose como "no hay proveedor".
- **Un fallo salia dos veces con dos redacciones**, una desde Services con
  texto cableado y otra desde el catalogo. Un solo dueno, y es el del catalogo.
- **El especialista perdia el disco al caer a batch.** El respaldo corria sin
  una sola bandera de permisos: sin manos y con boca, contestaba "no encontre
  nada" a preguntas que si tenian respuesta.
- **`temperature` iba cableada** y los modelos de razonamiento la rechazan con
  400. Latente hoy, garantizado en cuanto el panel deje elegir modelo.
- **El llavero prometia lo que no cumplia:** `kSecAttrAccessible` no aplica al
  llavero de archivo, que es el que usamos. Se quitaron los atributos muertos y
  el comentario dice lo que de verdad pasa.
- **Una lectura del llavero por proveedor y por turno** eran hasta cinco
  dialogos de contrasena por mensaje. Ahora una por clave.
- **El registro de un encargo no decia nada si lo corrio el ejecutor nativo:**
  solo conocia los nombres de herramienta de Claude Code.
- **La app anunciaba que "el especialista llega en una proxima version"**
  mientras el especialista trabajaba: copy vieja reutilizada sin leerla.
- **Salida de shell mayor que un pipe (~64 KB)** se reportaba como timeout: se
  leia despues de esperar, asi que el hijo se bloqueaba escribiendo.
- **Los subprocesos morian sin su descendencia**, y ninguno moria al cerrar la
  app. Ahora cada uno vive en su propio grupo, con escalada a SIGKILL.
- **La suite era intermitente** y nadie lo habia medido: `pumpUntil` esperaba
  2 s ocupando el main actor, con todos los tests en el main actor.

### Changed
- **El encargo es UI asistiva: no habla por su cuenta.** Decision de producto.
  El resultado vuelve una sola vez — el texto del especialista es el mensaje
  del hilo, con su codigo, sus rutas y sus cards, y la voz solo acusa que
  termino en vez de releerlo. Antes eran dos mensajes por un resultado, y el
  que sonaba era una parafrasis del que estaba escrito. Es la forma en que
  OpenAI cierra una tool — vuelve como salida, no como un segundo mensaje —
  aplicada hasta donde no cuesta producto: copiarla del todo habria borrado
  del hilo el texto integro del especialista, y con el las cards.
- **El permiso del especialista deja de preguntarse en voz alta.** Vive en la
  hoja. `resolve_approval` sigue declarada, asi que quien la ve y dice "si,
  autorizalo" resuelve sin tocar el trackpad; lo que se pierde, y es el precio
  elegido, es que un permiso que nadie mira muere en el auto-deny de los 120 s
  sin que la voz lo mencione. Revierte la parte hablada de la Wave 8.

### Fixed
- **La tool de permiso ya no se condiciona a un anuncio que no ocurre.** Al
  callar el anuncio, `resolve_approval` seguia diciendole al modelo que la
  usara "solo despues de que el sistema anuncie": se le prohibia la unica via
  que quedaba para aprobar hablando.
- **La voz ya no intentaba leer una card.** Un encargo que devolvia un mapa o
  una galeria hacia que el modelo recibiera «```companion:locations» como
  texto a narrar.
- **Un encargo que falla dice por que.** Los dos ejecutores de CLI devolvian
  una salida vacia cuando el proceso no arrancaba o terminaba sin reportar, y
  una salida vacia dejaba a la voz sin motivo: rellenaba el hueco diciendo que
  el encargo "fallo o se quedo sin tiempo", un reloj que nunca corrio. Misma
  familia que el bug que la Wave 8 creyo cerrar.
- **Un permiso negado se reporta como permiso.** Negar el reconocimiento de
  voz mandaba al usuario a "revisar el TTS": el lugar equivocado para un
  permiso de entrada. Ahora manda a Ajustes del sistema.
- **Lo que no puede ser una clave se responde sin salir a la red.** Pegar la
  URL de donde se sacan las claves, o media clave, costaba un viaje a OpenAI
  para volver como "esta clave no es valida", que culpa a la clave.
- **La voz tambien habla el idioma del usuario.** Wave 9 llevo el idioma a la
  interfaz y a los prompts de texto, pero el plano de voz se quedo atras: el
  reconocedor escuchaba siempre en es-MX, asi que quien hablaba ingles era
  transcrito como si fuera espanol; y el permiso del especialista se
  preguntaba en voz alta siempre en ingles aunque la hoja lo mostrara en
  espanol. Las dos veces la decision existia y nadie la invocaba — el patron
  de bug de este repo — y dos tests que ya existian daban por buena la
  omision, fijando "es-MX" sobre un arnes en ingles. El tercer punto donde se
  decidia un locale a mano — la voz sintetizada sin red — quedo derivado del
  mismo idioma: era el que contestaba en espanol a quien eligio ingles justo
  cuando no queda otro canal.

## [0.10.0] — 2026-08-22

Primera version publicada. Sin notarizar (no hay cuenta de Apple Developer):
al abrirla la primera vez hay que sortear Gatekeeper — el README dice como,
en macOS 14 y en macOS 15+, que ya no son lo mismo.

### Added
- La app habla el idioma de quien la usa, ingles o espanol, y **el modelo
  contesta en ese idioma**: no era barniz de interfaz, los prompts fijaban el
  idioma de las respuestas. Se elige en Ajustes o se sigue al sistema.
- El especialista puede pedir permiso **por voz**: con las manos ocupadas, la
  solicitud se pregunta en voz alta y tu respuesta la resuelve.
- El especialista recuerda en que iban entre arranques, y un encargo cuyo
  canal se cae se termina por la via lenta en vez de perderse.
- La espera del encargo es una tarjeta con paso vivo, reloj y resumen; al
  cerrar deja una linea con lo que se delego.

### Fixed
- **La voz ya no inventa el final.** Narraba encargos que no podia leer: se le
  pedia contar un resultado que nunca se le pasaba, y rellenaba con lo mas
  plausible — que habia salido bien. Ahora recibe lo que reporto el
  especialista, con instruccion explicita de no adornar.

### Changed
- El producto se llama **Companion** (`com.karen.companion`); el build de
  trabajo es Companion Next y nunca comparten identidad.

## [0.9.0] — 2026-08-22

### Added
- Se puede autorizar al especialista **por voz**: cuando pide permiso, la voz
  lo pregunta en su turno y tu respuesta lo resuelve. Antes la solicitud solo
  existia en la hoja de la pantalla y, con las manos ocupadas, moria en el
  auto-rechazo de los dos minutos.
- El especialista **recuerda en que iban** entre arranques de la app: el hilo
  de cada carpeta se guarda y se retoma. Si el guardado ya no le sirve, se
  olvida y empieza limpio, una sola vez.
- Un encargo cuyo canal se cae a media tarea **se termina por la via lenta**
  en vez de perderse, retomando la sesion; el hilo dice que hubo desvio.
- La espera del encargo es una **tarjeta con paso vivo y reloj**: que esta
  haciendo ahora, desde hace cuanto, y un resumen ("2 busquedas · 1 archivo").

### Changed
- Los pasos del encargo dejan de caer como lineas de status sueltas en el
  hilo: viven en la tarjeta mientras corre. El informe final no cambia.
- Documentacion honesta: NOTICE atribuye RiveRuntime (6.23.1, MIT) y lo fija
  por checksum; el ROADMAP mide de nuevo (16.828 lineas contra 15.307 del
  prototipo, 13.622 de tests contra 1.228) y deja de decir "cero
  dependencias"; ADR 002 anota que su premisa perdio una parte.
- Los tres archivos que rozaban el limite quedaron partidos por tema
  (tipografia, encargos del chat, bombas de la sesion de voz): gates sin un
  solo aviso.

## [0.8.1] — 2026-08-21

### Fixed
- La delegacion por voz funciona end-to-end (Wave 7). El cable con
  `claude -p` estaba roto de seis maneras: ruta hardcodeada equivocada,
  deteccion via `which` sin PATH de shell, flag `-m` inexistente, sin
  `--verbose` ni `--permission-prompt-tool stdio` ni rol del ejecutor, y un
  readLine que entregaba bloques del pipe como si fueran lineas NDJSON.
- La voz se entera del resultado: el cierre del encargo se anuncia como
  system item cuando la sesion vuelve a escuchar — antes seguia prometiendo
  "voy en camino" sobre un encargo muerto.
- Errores en humano: "Job failed: processLaunchFailed" jamas vuelve a
  pintarse en el hilo; presupuesto/cancelacion/launch tienen su frase.
- Los eventos del encargo por voz (pasos, pensamientos, aprobaciones) llegan
  al hilo y a la hoja de permisos por el mismo seam que los de chat; antes
  se drenaban y tiraban, y las aprobaciones morian en el auto-deny de 120 s.
- El proceso del especialista persiste entre encargos y se termina al
  cancelar; hermes recibe el prompt como argumento (-q) en vez de un stdin
  que esperaba para siempre; los adjuntos del turno viajan en el prompt.

## [0.8.0] — 2026-08-21

### Added
- La mascota del prototipo saluda al arrancar, con su animacion y sus
  reacciones al click.
- Cinco tipografias elegibles de verdad (antes el control existia pero no
  cambiaba nada).
- Los bloques de codigo salen resaltados, en tema claro y oscuro.
- El orb pasa a tener capas: blob, halo, particulas y sombra, siguiendo la
  voz y el estado de la conversacion.
- Controles propios en toda la app: menus desplegables, botones, campos y
  toggles con sus estados, en vez de los del sistema.

### Changed
- El contraste de cada par de colores se verifica contra WCAG AA en ambos
  temas: un cambio que lo rompa falla la suite.

### Added
- Inter viaja con la app (OFL). Las otras fuentes, si las tienes en esta
  Mac, se usan; si no, Inter o la del sistema.

## [0.7.0] — 2026-08-21

### Added
- Pensar ya no es silencio: un acorde suave de fondo mientras el modelo
  trabaja, con su toggle en Ajustes.
- Adjuntar una imagen durante una conversacion de voz se la muestra al
  agente al momento.
- La interfaz se adapta a como puedes interrumpir: boton visible con
  bocinas, flujo limpio con audifonos, cambiando en vivo al conectarlos.
- Ajustes de voz completos: criterio de fin de turno, velocidad (aplica en
  caliente), volumen, tono y cancelacion de eco con rearme.
- Avisos con sonido de interfaz para permisos y encargos.

### Added
- Avisos breves arriba a la derecha cuando se resuelve un permiso o termina
  un encargo, con un tono corto si los sonidos de interfaz están activos
  (se apagan en Ajustes).
- En una sesión de voz activa, adjuntar una imagen (menú o arrastre) se la
  enseña al agente y espera a que preguntes; no se reenvía si se reconecta.

## [0.6.0] — 2026-08-21

### Added
- Orb: la mascota reacciona a la conversacion — respira en reposo, sigue tu
  voz al escuchar, pulsa al pensar y acompana la del agente al hablar. En
  SwiftUI puro, sin dependencias ni binarios.
- Especialistas opcionales: si tienes Claude Code o Hermes instalados,
  aparecen para elegir; si no, no se nota nada. Si desinstalas el que tenias
  elegido, vuelve solo al nativo.

## [0.5.0-wave5a] — 2026-08-21

### Added
- Tema oscuro y color de acento elegible en toda la app.
- Ajustes: como quieres que te llame, apariencia y voz, con muestra para
  escuchar cada voz antes de elegirla. Todo sobrevive al reinicio.
- Onboarding que explica que necesita y por que, con enlace a donde se
  obtiene la clave y errores que dicen que hacer.

- Tarjetas en el hilo: mapas, galerias de imagenes y fuentes con sus enlaces;
  si el contenido viene mal formado se muestra como bloque de codigo en vez
  de romper la conversacion.
- Atajos de teclado reasignables, con la regla de que escribir gana: si estas
  en un campo de texto, la tecla escribe en vez de disparar el atajo.
- Distribucion: script de release que firma y notariza (o avisa que la build
  va sin firmar), y CI que corre las mismas comprobaciones en cada PR.
- Licencia MIT, NOTICE y guia de contribucion.

### Changed
- Las animaciones usan duraciones nombradas y respetan la preferencia de
  reducir movimiento del sistema.

## [0.4.0-wave4a] — 2026-08-21

### Added
- Delegacion a un especialista nativo que funciona solo con tu API key: el
  modelo de charla le pasa el encargo, trabaja en segundo plano con sus
  herramientas y devuelve el resultado al mismo hilo, desde texto o voz.
- Seis herramientas con nivel de riesgo declarado: leer, escribir y editar
  archivos, ejecutar comandos, y consultar la web. Escribir y ejecutar
  siempre piden permiso.
- Hoja de permisos con el comando o la ruta en claro (no JSON): permitir o
  denegar, y si no respondes se deniega solo a los dos minutos.
- Doble barrera de rutas: ninguna herramienta sale de tu carpeta de trabajo,
  ni siquiera por un enlace simbolico.
- Cola serial con presupuesto de quince minutos y cancelacion.

## [0.3.1-wave3] — 2026-08-21

### Fixed
- La caida del WebSocket ya no deja una sesion zombi: error observable,
  reconexion unica con historial sembrado, y el envio se detiene al primer
  fallo en vez de insistir en silencio.
- El microfono sobrevive a Macs donde el AEC de Apple no inicializa
  (kAUInitialize -10875 con dispositivos virtuales en la cadena): veto
  persistente, espera del HAL con engines frescos al reintentar, y watchdog
  de silencio que falla visible en vez de escuchar la nada.
- El tap interrumpe en vez de colgar; los fallos llegan a pantalla con su
  razon (incluida "sin conexion", distinguida de "el servidor no contesta"
  con NWPathMonitor); AVAudioEngine ya no aborta el proceso al arrancar.

### Added
- Pin de los buses del VPIO al par de dispositivos integrados (tecnica
  documentada por Apple) para esquivar agregados rotos.
- Con salida sin eco (audifonos/bluetooth) se envian frames mientras el
  agente habla: barge-in por voz sin AEC.
- Trazas del turno de voz (transiciones, eventos del servidor, permiso,
  formato del mic, primer buffer): esta ronda fue indiagnosticable sin ellas.
- Firma estable obligatoria en bundle.sh (los permisos TCC sobreviven) e
  identidad/log propios para convivir con el prototipo instalado.

## [0.3.0-wave3] — 2026-08-20

### Added
- Voz en tiempo real sobre OpenAI Realtime (WebSocket) con barge-in, mute que
  cierra turno como exige el servidor, y echo guard de 350 ms; si el
  WebSocket no abre en 6 s cae al pipeline clasico (mic + transcripcion del
  sistema + chat + TTS) sin perder el hilo.
- TTS con voz de OpenAI, cache en disco de frases cortas y voz del sistema
  como respaldo offline. Cero Python (ADR 001).
- Watchdog de Voice Processing: si el engine arranca y el tap nunca entrega
  audio, veta AEC y reintenta una vez — la cicatriz mas cara del prototipo.
- `scripts/bundle.sh`: empaqueta el .app con las usage descriptions que macOS
  exige para pedir microfono y reconocimiento de voz.

### Fixed
- Delegates de AVFoundation reescritos para Swift 6 (aislamiento) y con
  reanudacion idempotente: parar y terminar ya no pueden reanudar dos veces
  la misma continuacion.
- Los caminos de voz (WebSocket y TTS) ahora pasan por las policies de
  endpoint de Wave 2, que se habian saltado.
- Directorios de cache, logs y conversaciones se crean con permisos 0700.

## [0.2.0-wave2] — 2026-08-20

### Added
- Chat usable: onboarding con API key de OpenAI (Keychain, ping
  `GET /models`), hilo con streaming, historial de las ultimas 30
  conversaciones en Application Support.
- Fallback OpenAI → Groq → Ollama (Groq si hay key; Ollama si el probe
  lo ve). Un fallo a media frase no concatena proveedores.

### Fixed
- Hardening del review de cierre (tdd-guide, rojo primero): redirects
  cross-host o https→http rechazados (RedirectPolicy); http permitido solo
  hacia localhost (EndpointPolicy); logs sin errores del sistema ni rutas, y
  las fallas de prune ya no son silenciosas.

### Changed
- `swift run companion` abre ventana. Todavia sin voz.
- Harness de tests migrado a Swift Testing (`swift test`, 22 suites @Test);
  expect/expectEq quedan como shims sobre #expect con sourceLocation, y el
  bombeo de los tests del ViewModel es async (la main queue no es reentrante
  bajo swift test). Muere el runner ejecutable.

## [0.1.0-wave1] — 2026-08-20

### Added
- Nucleo puro de dominio: maquina de estados del turno, codecs Realtime/SSE
  /NDJSON, splitter de frases, endpointer, escalacion, markdown y cards
  `companion:*`, catalogo de proveedores y ejecutores (nativo siempre).
- Suite de caracterizacion portada del prototipo (mismos casos, tipos
  nuevos). 640 tests. `approval: 1` ya no concede permiso.

### Fixed
- Review post-cierre (code-reviewer + security-reviewer + tdd-guide, rojo
  primero): `request_id` vacio ya no crea solicitudes de permiso; URLs de
  `companion:locations` solo https; paths de gallery absolutos y sin `..`;
  suite de robustez ante JSON hostil (anidado 200+, multi-MB, tipos
  inesperados, UTF-8 invalido) en los cuatro codecs. 656 tests.
- Defensa anti-inyeccion de prompt: requisito estructural anadido al spec de
  Wave 4 (tools destructivas siempre via approvals).

### Changed
- `Build.version` a `0.1.0-wave1`.

## [0.1.0-wave0] — 2026-08-20

### Added
- Paquete SPM con 4 targets (Core/Services/UI/App); las dependencias entre
  targets codifican la arquitectura y las vigila el compilador.
- Swift 6.2 tools, strict concurrency; UI y App con MainActor por default.
- Suite de compliance `scripts/gates.sh`: build, estatico (secretos, prints,
  `try?` prohibido en Core/Services, topes de tamano), arquitectura (imports
  por capa) y tests.
- Harness de tests ejecutable (CLT no trae Swift Testing ni XCTest); API
  espejo de Swift Testing para migracion mecanica.
- Programa de reconstruccion por waves, ledger de cicatrices del prototipo
  de referencia, ADR 001 (desacople de Hermes).
