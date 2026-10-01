- **Cuando los tests se caen a mitad de camino, el gate dice cuál y por qué (2026-10-01).** Solo
  gates: si el proceso de tests moría sin resumen, Gate 4 y la corrida de TSan solo mostraban el
  final de la salida, sin el test que estaba corriendo ni la señal, porque `swift test` sale con 1
  igual y la señal se imprime miles de líneas más arriba. Ahora el reporte imprime el código de
  salida, la señal si la hay y los tests que arrancaron sin terminar. La app no cambia.
