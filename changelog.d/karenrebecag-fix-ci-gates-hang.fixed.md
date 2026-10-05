- **Un test colgado ya no retiene la CI seis horas (2026-10-04).** El job de gates tiene un
  tope de 30 minutos y la salida de `swift test` sale al log mientras corre. Si pasan varios
  minutos sin salida nueva, un vigilante imprime el ultimo test que empezo, el arbol de
  procesos y una muestra de pila, y corta la corrida con un fallo claro de "test colgado"
  en vez de dejar la cola de merge esperando.
