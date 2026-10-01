- **Un test de diagramas ya no falla en CI de vez en cuando (2026-10-01).** Solo tests: al
  cancelar un dibujo, el test revisaba de inmediato que el dibujo se hubiera enterado, pero el
  aviso llega en un turno posterior del main actor. Con el main actor ocupado, la revisión
  llegaba antes y fallaba. Ahora espera a que el dibujo registre la cancelación. La app no cambia.
