- **Una respuesta larga del puente ya no se pierde entera (2026-10-03).**
  Companion no limitaba el tamano de lo que devolvia una herramienta, y una salida de mas de 64 KB
  hacia que el shim cortara la conexion. Ahora la salida se recorta a 24000 bytes UTF-8 sin partir
  caracteres y termina con una nota que dice que el resultado es parcial y pide acotar la consulta.
