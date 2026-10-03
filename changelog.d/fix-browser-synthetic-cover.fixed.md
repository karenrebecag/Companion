- **Pulsar dentro de un iframe ya no atraviesa lo que lo tapa (2026-10-03).**
  Dentro de iframes, y cuando el clic real no encontraba dónde caer, la extensión pulsaba el
  elemento por código sin mirar si un diálogo, un banner o una capa lo cubría, así que se pulsaba
  algo que la persona no podía ver. Ahora ese clic comprueba primero qué hay encima del elemento, en
  su propio iframe y en la página que lo contiene, y si algo lo tapa se rechaza y el modelo vuelve a
  leer la pestaña.
