- **El llavero falso de los tests de voz ya no tiene una carrera de datos (2026-10-03).** Una boca
  de prueba borraba una clave desde la sintesis mientras el enrutador y el test leian el mismo
  llavero, sin lock: el mismo patron que ThreadSanitizer marco en CI en los dobles de la sintesis.
  Ahora cada campo va detras de un lock. Solo cambian tests.
