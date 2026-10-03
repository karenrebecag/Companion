- **Escribir en el navegador ya no pierde los saltos de línea sin avisar (2026-10-03).**
  El tecleo tecla por tecla no puede enviar saltos de línea, y el host descartaba el aviso de la
  extensión, así que un correo de tres párrafos quedaba en uno y el modelo decía "escrito". Ahora el
  texto con saltos entra completo en un `textarea` en una sola inserción, comprobada al releer el
  campo. Si el campo no los conserva, el modelo recibe que el texto quedó en una línea y que debe
  avisar a la persona.
