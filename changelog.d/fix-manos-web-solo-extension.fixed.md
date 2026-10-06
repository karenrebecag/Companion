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
