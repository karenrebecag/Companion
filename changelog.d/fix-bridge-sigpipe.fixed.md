- **Los tests del puente ya no tumban toda la corrida con SIGPIPE (2026-10-01).** CI moria
  sin resumen dentro de las suites del puente: los clientes de prueba escribian a un socket
  que el servidor ya habia cerrado, sin nada que convirtiera la senal en un EPIPE. Ahora
  cada cliente de prueba protege su socket, y la conexion del puente protege el suyo al
  construirse, no solo al aceptarse. La app ya estaba protegida en el camino real. Brief
  `docs/research/bridge-sigpipe.md`.
