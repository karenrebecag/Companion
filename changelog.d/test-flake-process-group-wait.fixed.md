- **El test de esperas de procesos ya no depende del reloj (2026-10-01).** Solo tests y CI:
  exigía que dos esperas terminaran en menos de 0.75 s y fallaba cuando la Mac o el runner se
  congelaban un momento. Ahora las dos shells se esperan entre sí, y CI repite ese test con el
  pool cooperativo en modo estricto (un hilo), donde una espera que bloquee su hilo sí falla.
  La app no cambia.
