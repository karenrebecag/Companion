- **Escribir en un campo ya no deja caer el texto en otro si la página le quita el foco (2026-10-03).**
  La extensión comprobaba que el campo no fuera sensible (contraseña, tarjeta) antes de enfocarlo,
  pero no que el foco se quedara ahí: un manejador de foco de la página podía moverlo a otro
  campo, incluso a uno sensible, y el texto se escribía en ese. Ahora, justo antes de escribir, se
  verifica el elemento activo (también dentro de shadow roots; un contenteditable acepta que el
  cursor esté en un hijo) y, si el foco se movió, no se escribe nada: `secure_field` si fue a un
  campo sensible, `stale_id` si no. Vale para el texto de una línea, el multilínea y las teclas
  de confianza. Queda una ventana de milisegundos entre la preparación y la primera tecla
  (anotada como HACK en el código).
