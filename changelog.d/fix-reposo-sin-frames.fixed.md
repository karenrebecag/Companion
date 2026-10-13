- **La app ya no dibuja cuando nadie la ve (2026-10-13).** El orbe de voz respira
  incluso en reposo y redibujaba a 60-120 fps aunque la ventana estuviera oculta,
  minimizada o tapada: ahora la ventana avisa cuando sale de pantalla y los orbes
  (voz, pensando) y el brillo de texto se detienen hasta que vuelve. La pila de
  avisos dejaba un reloj de dos ticks por segundo encendido sin avisos y repintaba
  aunque nada caducara; ahora duerme. La animación visible no cambia.
