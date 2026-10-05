- **Los tests de main vuelven a compilar (2026-10-04).** Dos PR mergeados el mismo dia declaraban un reloj de
  prueba con el mismo nombre en el mismo modulo; se renombra el de versiones de archivo.
- **Las pruebas de pausa de la tarjeta de dictado ya no fallan al azar (2026-10-05).** Esperaba el reloj equivocado cuando la maquina iba cargada, asi que a veces se agotaba sin que la app tuviera ningun error. Ahora espera exactamente el tramo que debe quedar del techo.
