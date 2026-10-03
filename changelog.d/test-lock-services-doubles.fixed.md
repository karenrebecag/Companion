- **Los dobles de la mano y del oido de los tests de servicios ya no tienen carreras de datos (2026-10-03).**
  El doble de las manos guardaba su configuracion y leia sus registros (inyectado, pulsado,
  elevado) sin lock mientras el ejecutor los escribia fuera del hilo principal, y el oido de
  prueba sacaba sus esperas de stop() de una lista compartida desde varias tareas a la vez: el
  mismo patron que ThreadSanitizer marco en los otros dobles. Ahora cada campo va detras de un
  lock y ninguna espera se duerme con el lock tomado. Solo cambian tests.
