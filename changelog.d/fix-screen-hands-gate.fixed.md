- **`see` ya no confunde un permiso roto con un fallo de vision (2026-10-03).**
  Las manos leian solo el interruptor de Grabacion de pantalla, que puede seguir encendido aunque
  toda captura falle. Ahora leen el estado verificado: sin permiso rechazan antes de capturar, y una
  captura vacia sin permiso verificado responde `screen_recording_required` con el panel exacto,
  en lugar del ambiguo `no_capture`.
