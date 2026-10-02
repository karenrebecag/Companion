- **Los tests del ejecutor nativo ya no fallan bajo carga (2026-10-01).** Solo tests: cuatro de
  ellos esperaban con un plazo de 5 s que ocupaba un hilo real, y con la Mac cargada el plazo
  vencía antes de que el trabajo tuviera turno. Otros leían los eventos del encargo justo después
  de cerrarlos, antes de que su lector los hubiera procesado, y a veces los veían vacíos. Ahora
  esperan directamente, y cada lectura espera a que el lector termine. La app no cambia. Brief
  `docs/research/native-executor-flakes.md`.
