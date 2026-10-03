- **Los tests de reconexion de voz ya no caen cuando la Mac esta cargada (2026-10-03).** En una
  corrida completa fallaba un test distinto cada vez: el arnes de pruebas daba solo 1 s al
  saludo del servicio, y con la maquina saturada la sesion se rendia y caia a la voz clasica
  antes de quedar escuchando. Ahora el arnes espera sin ese tope, igual que los de FanOut y
  rollover de conversacion que tenian el mismo 1 s, y un test nuevo lo cubre reteniendo el
  saludo mas alla de ese tiempo. Solo cambian tests; la app no cambia.
