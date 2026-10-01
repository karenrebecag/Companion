# changelog.d

Cada PR agrega **un** archivo aqui en vez de editar `CHANGELOG.md`. Un archivo nuevo
nunca choca con los de otros PR, que era el origen de los rebases en cadena.

## Nombre

`changelog.d/<slug-de-rama>.<added|changed|fixed|security>.md`

- `<slug-de-rama>` es el nombre de tu rama sin `/` (ej. `fix/voz-red` pasa a `fix-voz-red`).
  Es unico por construccion.
- La categoria es una de `added`, `changed`, `fixed`, `security` y corresponde a los
  encabezados `### Added`, `### Changed`, `### Fixed`, `### Security` del CHANGELOG.
- Docs y CI tambien llevan fragmento (normalmente `changed`).

## Contenido

El bullet exacto, en espanol y con su fecha, igual que las entradas de `CHANGELOG.md`:

```
- **Titulo en lenguaje llano (2026-10-01).** Que cambio y por que le importa a quien usa la app.
```

Puede ocupar varias lineas; las siguientes se indentan dos espacios.

## Quien toca CHANGELOG.md

Solo el ensamblado, al cerrar cada wave:

```
scripts/changelog-assemble.sh --dry-run   # vista previa, no escribe
scripts/changelog-assemble.sh             # inserta bajo [Unreleased] y hace git rm
```

Sin fragmentos no hace nada. Una categoria desconocida aborta sin escribir.
