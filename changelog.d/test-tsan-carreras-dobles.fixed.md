- **El reloj falso de los tests de la tecla FN ya no tiene una carrera de datos (2026-10-02).**
  La cola que arma la tecla leia ese reloj mientras el test lo movia desde el hilo principal, sin
  lock, y ThreadSanitizer lo marco en CI. Ahora el reloj va detras de un lock. Solo cambian tests.
