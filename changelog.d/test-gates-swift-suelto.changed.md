- **El gate de capas rechaza un test suelto en `Tests/` (2026-10-01).** Un `.swift` directo en
  `Tests/`, fuera de toda carpeta de target, no lo compila ningún target y sus tests nunca
  corren; ahora el gate falla y lo nombra.
