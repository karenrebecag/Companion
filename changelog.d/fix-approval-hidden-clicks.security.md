- **La hoja de permiso ya no recibe clics mientras es invisible (2026-10-03).** Al crecer la isla
  (unos 120 ms) el contenido aparece desde transparente, y los botones de permiso ya aceptaban
  clics sin que pudieras verlos. Ahora un clic con el contenido aun invisible se ignora, no
  responde ni gasta la espera, y la hoja no recibe clics hasta que se ve. La espera de 0,6 s y
  el ligado al identificador de la peticion se conservan.
