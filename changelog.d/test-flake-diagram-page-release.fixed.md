- **El test de la pagina de diagrama colgada ya no apuesta contra el reloj (2026-10-01).**
  `diagramPageFailureTests` dormia 1 s y esperaba que el web view ya estuviera suelto, pero
  WebKit lo suelta cuando el recolector de JavaScript llega al script colgado, sin plazo fijo.
  Ahora espera a que se suelte, con el tope comun de 30 s. Solo tests; la app no cambia.
  Brief `docs/research/diagram-page-liberacion.md`.
