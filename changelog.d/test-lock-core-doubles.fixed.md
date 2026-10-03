- **Los dobles de test del core ya no tienen carreras de datos (2026-10-03).**
  El presentador, el transcriptor, la pantalla, el observador de cambios y el almacen de secretos
  falsos se leian desde un hilo mientras otro los escribia, sin lock. Ahora cada uno guarda su
  estado detras de un lock, con la misma API. Solo cambian tests.
