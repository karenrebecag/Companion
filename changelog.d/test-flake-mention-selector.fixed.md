- **Dos tests del selector de @ esperan al diálogo de contactos, no a una señal vecina
  (2026-10-01).** Uno daba por abierto el diálogo en cuanto aparecían las apps y los archivos, y
  Swift no ordena esas dos cosas; bajo carga podía fallar. El otro podía pasar sin llegar a probar
  un diálogo retenido. La falla no se reprodujo en local: el arreglo sigue lo que Swift garantiza.
  La app no cambia.
