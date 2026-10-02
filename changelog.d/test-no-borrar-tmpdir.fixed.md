- **Los tests ya no borran la carpeta temporal de la Mac (2026-10-01).** Solo tests: tres tests
  del ejecutor nativo usaban la carpeta temporal de todo el usuario como si fuera suya y la
  borraban al terminar, así que cada corrida local intentaba vaciarla, con archivos de otras apps
  incluidos. Esa carpeta no se puede aislar desde fuera porque macOS ignora `TMPDIR` para ella.
  Ahora cada test usa una carpeta propia, y un test nuevo revisa las fuentes para que ninguno
  vuelva a borrar la temporal entera. La app no cambia. Brief
  `docs/research/native-executor-flakes.md`.
