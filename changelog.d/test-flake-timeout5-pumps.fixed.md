- **Los tests de reconexión toleran que la Mac se congele unos segundos (2026-10-01).** Solo
  tests: 17 esperas de `VoiceReconnectTests` tenían topes de 5 s y 2 s de reloj de pared, la misma
  causa que el arreglo de permisos (#74). Ahora usan el tope común de 30 s. La app no cambia.
