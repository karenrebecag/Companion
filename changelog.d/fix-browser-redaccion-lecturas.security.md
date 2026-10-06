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
