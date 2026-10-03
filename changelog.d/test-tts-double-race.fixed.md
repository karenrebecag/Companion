- **Los dobles de la voz en los tests de sintesis ya no tienen una carrera de datos (2026-10-03).**
  El fetch y la voz de respaldo falsos anotaban sus llamadas desde la sintesis mientras el test
  las leia, sin lock, y ThreadSanitizer lo marco en CI. Ahora cada campo va detras de un lock.
  Solo cambian tests.
