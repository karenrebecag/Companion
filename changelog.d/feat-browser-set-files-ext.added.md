- **La extension del navegador ya sabe poner un archivo en un campo de subida (2026-10-04).** Solo la parte
  de la extension: encuentra el campo de la ultima lectura (un solo campo en todo el documento, nunca dentro
  de un frame), comprueba que sea un campo de archivo y le pasa la ruta al navegador, que lee el archivo. Si
  la pagina navego a otro documento u otro origen en el medio, no sube nada; si falta el permiso de acceso a
  archivos lo dice. Todavia no esta conectada a Companion; borrador. `browser_read` ahora reporta los campos de archivo con el rol "file".
