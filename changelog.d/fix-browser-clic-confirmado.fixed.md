- **Un clic que no se puede confirmar ya no se reporta como pulsado (2026-10-05).** Si la página
  no veía la pulsación aterrizar en el elemento (por un overlay, por un control que se movió, o
  porque el clic se perdió), la extensión decía igualmente "clicked" o seguía tecleando. Ahora el
  clic, el doble clic y el clic derecho avisan al asistente de que la pulsación no se pudo
  confirmar y le piden volver a leer la pestaña antes de actuar, sin repetir el clic a ciegas;
  `browser_type` ni siquiera teclea si la pulsación no se confirmó (sería peor mandar las teclas
  al campo equivocado) y devuelve el error `press_unconfirmed`.
