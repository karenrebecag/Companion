- **Un especialista que se cae entre encargos ya no tumba la app (2026-10-01).** Si el CLI
  delegado moria entre dos encargos, mandarle el siguiente mataba Companion entera con
  SIGPIPE en vez de fallar y reintentar con un proceso nuevo, que es lo que el ejecutor ya
  esperaba. Ahora la entrada del especialista esta protegida y esa escritura falla como un
  error normal. Brief `docs/research/bridge-sigpipe.md`, opcion F.
