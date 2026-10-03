- **El bridge ya no entrega caracteres invisibles al agente (2026-10-02).** Lo que devuelve una tool
  es texto de pantalla que una pagina o un mensaje pueden escribir; los caracteres de etiqueta, bidi,
  ancho cero y controles se quitan antes de salir de Companion, para que el agente lea lo mismo que
  ve la persona. Los saltos de linea y tabuladores se conservan.
