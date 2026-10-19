- **Jev de TypeSafe como juez de decisiones (2026-10-18).** Nuevo adaptador que pregunta
  a Jev (`jev-1.14.0`) las mismas preguntas tipadas que hoy responde el modelo local, con
  la clave en Ajustes > Claves. Una respuesta mal formada se descarta y un 429/529 o un
  timeout deja pasar el turno al cerebro; a TypeSafe solo viaja la frase y los nombres de
  las opciones, nunca la pantalla. Todavía no está conectado a la cascada.
