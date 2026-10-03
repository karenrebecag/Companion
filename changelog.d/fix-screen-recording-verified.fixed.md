- **Grabacion de pantalla cuenta solo cuando una captura real funciono (2026-10-03).** El preflight del
  sistema puede seguir diciendo que si despues de revocar el permiso; ahora la vista espera un sondeo
  real con ScreenCaptureKit antes de la primera captura, y una captura que falla vuelve a sondear: si
  el permiso se perdio, la vista se apaga (estado `stale`) en vez de fallar en silencio en cada turno,
  y la siguiente captura vuelve a sondear (como mucho una vez cada 30 s) hasta que funciona otra vez.
  La causa de cada captura fallida queda en el log. El sondeo nunca pide el permiso ni muestra el aviso del sistema sin concesion previa.
