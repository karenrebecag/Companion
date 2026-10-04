- **Una clave o direccion equivocada ya no borra la configuracion de Apps que funcionaba (2026-10-03).**
  Antes, al guardar, la clave nueva iba al llavero y la direccion a las preferencias antes de que la
  funcion respondiera, asi que un error de tipeo desconectaba Apps sin vuelta atras. Ahora, si ya habia
  una configuracion (o una clave guardada para esa direccion), la funcion tiene que aceptar la nueva primero; si la rechaza, no responde o esta
  caida, se conserva la anterior y el formulario dice por que. Mientras se comprueba, Guardar queda
  bloqueado, y una respuesta tardia de la funcion anterior ya no se pinta sobre la nueva. La primera
  configuracion se guarda como antes.
