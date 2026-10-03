- **El puente rechaza por nombre un argumento mal escrito o fuera de medida (2026-10-03).**
  Companion declara en el hello los limites de cada argumento (texto de 1 a 16000 bytes UTF-8 en
  `type_text` y `browser_type`, direcciones validas de `scroll`) y los vuelve a comprobar al recibir
  la llamada. Un cliente que no pase por el shim recibe `invalid_args` con el argumento exacto, sin
  gastar presupuesto ni abrir la hoja de aprobacion.
