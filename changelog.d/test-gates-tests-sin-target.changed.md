- **El gate de capas detecta tests que nadie compila (2026-10-01).** Solo gates: un `.swift` bajo
  `Tests/` que `exclude:`, `sources:` o un `path:` propio dejaban fuera nunca corría, y el build
  solo lo avisaba de pasada, o ni eso. Ahora el gate le pregunta a SwiftPM
  (`swift package describe`) qué compila cada target y falla si sobra un archivo. La app no cambia.
