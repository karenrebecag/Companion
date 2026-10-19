- **Medición de jueces sobre el corpus (2026-10-18).** Un test opcional
  (`COMPANION_LIVE_JUDGES=1`) corre la cascada de decisión sobre todas las órdenes de
  `ordenes.jsonl` con Ollama y con Jev, y reporta aciertos, latencia p50 y costo por
  juez, además de cuántas veces el head de delegación acierta en las filas de encargos y
  de "no delegar". La clave de TypeSafe se lee de Ajustes > Claves.
