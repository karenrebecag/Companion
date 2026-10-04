- **Companion ya elige opciones en las listas desplegables del navegador (2026-10-03).** Antes, una
  lista `<select>` (país, mes, cantidad) no se podía usar: escribir en ella fallaba y el modelo solo
  podía pedir a la persona que eligiera. Ahora `browser_select` elige la opción por la etiqueta que
  muestra la página, como en Incredible, y si no existe responde con las etiquetas que sí hay. Elegir
  una opción que borra o envía, o en una lista de otro sitio, pregunta antes; una lista sensible
  (vencimiento de tarjeta) se rechaza. Solo por etiqueta: el modelo nunca ve los valores internos, y
  un valor dejaría elegir una opción cuya etiqueta nadie revisó.
