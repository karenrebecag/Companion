- **Un test de procesos ya no bloquea el main actor de los demás (2026-10-01).** Al limpiar las
  shells esperaba en el main actor el margen del SIGTERM (unos 255 ms medidos), y los tests
  `@MainActor` que corren en paralelo se quedaban sin turno, un disparador plausible del flake de
  earReview. Ahora la limpieza corre fuera del main actor. La app no cambia.
