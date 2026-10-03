- **Las manos y la vista dicen que permiso o estado les falta al actuar (2026-10-02).** Con la Mac
  bloqueada, manos, vista y aperturas (`open_app`, `open_url`, `open_file`) se niegan antes de actuar
  (`screen_locked`); si se bloquea a mitad de una accion, dicen que el resultado es desconocido, y una
  captura de `see` que choca con el bloqueo se descarta. `see` sin Grabacion de pantalla responde
  `screen_recording_required` con la ruta en Ajustes del Sistema, y una ventana que no se quedo
  delante responde `foreground_unavailable`.
