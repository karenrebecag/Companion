# Trazabilidad de builds: de un crash report al codigo exacto

Fecha: 2026-09-30. Auditoria de solo lectura: no se cambio codigo, script ni config.
Repo: `companion-next-ci`, detached en `origin/main` (`b494e9e`).

## 0. Resumen

La propuesta (sellar hash de commit + flag dirty en el Info.plist) va en la direccion
correcta, pero **por si sola no resuelve el problema**: el `.ips` de macOS no copia claves
propias del plist (solo `CFBundleShortVersionString`, `CFBundleVersion` y
`CFBundleIdentifier`). Lo que SI viene en todo crash report es el **UUID del binario**
(`slice_uuid` / `usedImages[].uuid`). La cadena correcta es:

```
.ips (slice_uuid)  ->  archivo local por UUID  ->  commit + dirty + patch + dSYM
```

Recomendacion en una linea: mantener `CFBundleVersion` numerico y monotono (no el conteo
de git), agregar `CompanionGitCommit` / `CompanionGitDirty` al plist, **archivar el dSYM y
el binario por UUID en cada bundle** (con el diff si hubo cambios sin commit) y loggear
version + build + commit + dirty + UUID al arrancar.

## 1. Estado actual (evidencia local)

### 1.1 Lo que hace `scripts/bundle.sh`

- `CFBundleShortVersionString` = `Build.version` leido con `grep` de
  `Sources/CompanionCore/Build.swift` (hoy `0.10.0`). Linea 15.
- `CFBundleVersion` = `git -C "$ROOT" rev-list --count HEAD || echo 0`. Linea 87.
- Copia `$BUILT` tal cual a `Contents/MacOS/Companion` (linea 48), escribe el plist por
  heredoc, firma (`Companion Dev` o ad-hoc) e instala en `/Applications`.
- No hay `strip`, no se copia ni se guarda el dSYM, no se registra el commit.
- `ProductIdentityTests.testTheBundleScriptMatchesTheSource` ya lee `bundle.sh` como texto
  para verificar identidades: es el patron natural para testear los nuevos campos.

### 1.2 Como la app lee su version

- `Build.version` (Core) es la fuente unica; `UpdateChecker` lo compara contra el tag del
  ultimo release de GitHub (ADR 002: sin framework de updates, sin Sparkle).
- `SettingsView.swift:305` lee `CFBundleShortVersionString` del `Bundle.main`.
- `ProductIdentity.of(bundleID:)` decide release/desarrollo y el nombre del log
  (`Companion.log` / `CompanionNext.log`) en `makeLaunchEnvironment()`.
- Al arrancar solo se loggea `Log.app("launched")` (`CompanionMainWindow.swift:215`),
  sin version, build, commit ni UUID.
- Nadie lee `CFBundleVersion` en runtime: cambiar su formato no rompe codigo.

### 1.3 Los tres crash reports

`~/Library/Logs/DiagnosticReports/Companion-2026-09-23-104525.ips`,
`...-105123.ips` y `...-2026-09-26-002033.ips`:

| Reporte | build_version | slice_uuid |
|---|---|---|
| 09-23 10:45 | 106 | `72285568-B17E-3167-BA66-A36511979D96` |
| 09-23 10:51 | 106 | `72285568-B17E-3167-BA66-A36511979D96` |
| 09-26 00:20 | 106 | `0A51558C-9B7D-38E8-BBE4-59BEEAC82AB2` |

**Dos binarios distintos se reportaron como el mismo build 106.** El numero no identifica
nada. `bundleInfo` en los tres trae exactamente
`{CFBundleShortVersionString, CFBundleVersion, CFBundleIdentifier}`; no hay `buildInfo`.

Busque dSYMs con esos UUID en los seis worktrees `companion-next*`: **ninguno existe**.
Cada worktree tiene un `.build/arm64-apple-macosx/release/companion.dSYM`, pero se
sobreescribe en cada build. Los UUID encontrados (13A91576, DA2F1398, 64124FB0, EAEAA024,
C9E26FB4, CE833EFF) no coinciden con los crashes. Es decir: aunque se supiera el commit,
hoy ya no se podrian obtener numeros de linea de esos tres reportes.

### 1.4 El numero de build no es monotono ni unico

- El `/Applications/Companion.app` instalado hoy dice `CFBundleVersion = 184` y salio del
  worktree `companion-next-ui-gap-q1` (se ve en sus rutas embebidas, ver 1.5).
- `git rev-list --count HEAD` en `origin/main` hoy da **239**.
- El commit numero 106 de la historia actual de main es `d517bfb` (2026-08-26, onboarding),
  sin relacion con los crashes de 09-23 / 09-26.

### 1.5 El binario no esta stripped (por eso los reportes locales traen simbolos)

- `nm` sobre el binario instalado: ~63 000 simbolos en la tabla `LC_SYMTAB`, y 413
  entradas `OSO` (debug map) apuntando a `.o` en
  `/Users/karenrebecaog/Desktop/SoftwareDevProjects/companion-next-ui-gap-q1/.build/...`.
- `dwarfdump --uuid` del instalado: `EAEAA024-3D85-3F48-9E83-F8C090CBAC1D`, identico al
  `companion.dSYM` de ese worktree: `codesign` no altera `LC_UUID`, asi que el dSYM que SPM
  genera sirve tal cual para el binario dentro del `.app`.
- Por que los `.ips` traen nombres de funcion: ReportCrash simbolica en el momento del crash
  con la tabla de simbolos que viaja dentro del binario. Por eso aparece
  `closure #1 in CompanionRootView.body.getter`, pero `sourceLine` viene vacio: los numeros de
  linea viven en el DWARF (dSYM o `.o`), no en la tabla de simbolos.
- Efecto colateral: `strings` encuentra rutas absolutas con el nombre del worktree
  (`companion-next-ui-gap-q1/.build/.../Companion_CompanionServices.bundle`), que SPM mete
  en el accessor de `Bundle.module`, mas las 413 rutas `OSO`. **El DMG distribuido ya filtra
  tu usuario, la estructura de carpetas y el nombre de la rama/worktree**, independiente de lo
  que se ponga en el plist.

## 2. Documentacion de Apple

### 2.1 `CFBundleVersion` y `CFBundleShortVersionString`

[CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion):

> "This key is a machine-readable string composed of one to three period-separated
> integers, such as 10.14.1. The string can only contain numeric characters (0-9) and
> periods."
>
> "For macOS apps, increment the build version before you distribute a build."

[CFBundleShortVersionString](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring):

> "The required format is three period-separated integers, such as 10.14.1. The string can
> only contain numeric characters (0-9) and periods."

Conclusion: un hash (hex) no cabe en ninguna de las dos. `CFBundleVersion` debe ser numerico
y creciente. Xcode lo refuerza en
[CURRENT_PROJECT_VERSION](https://developer.apple.com/documentation/xcode/build-settings-reference#Current-Project-Version):
"The value must be a integer or floating point number, such as `57` or `365.8`."

### 2.2 Claves propias en el Info.plist y el formato `.ips`

Las claves propias son validas (el plist es un diccionario libre; Apple solo reserva los
prefijos de sus propias claves, como `CF`, `NS`, `LS`, `UI`). Usar un prefijo propio evita
choques: `CompanionGitCommit`, no `GitCommit`.

Pero **no aparecen en el crash report**. [Interpreting the JSON format of a crash
report](https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report)
define el objeto `bundleInfo` con tres propiedades:

> `CFBundleIdentifier` — "The bundle identifier for the process that crashed."
> `CFBundleShortVersionString` — "The bundle version string (short) for the process that crashed"
> `CFBundleVersion` — "The bundle version for the process that crashed"

y el header: `build_version` — "The bundle version string of the process the report applies
to". Los tres `.ips` locales confirman que no se copia nada mas.

### 2.3 El UUID es el identificador canonico

Mismo documento, objeto de imagen binaria:

> `uuid` — "A build UUID that uniquely identifies the binary image you can use to locate the
> corresponding dSYM file when symbolicating the crash report."

[Building your app to include debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information):

> "The compiled binary and its companion dSYM file are tied together by a build UUID that's
> recorded by both the built binary and dSYM file. [...] A binary and a dSYM file are only
> compatible with each other when they have identical build UUIDs. Keep the dSYM files for the
> specific builds you distribute, and use them when diagnosing issues from crash reports."
>
> "You must retain the Xcode archive for each build of your app you distribute. Without this
> archive, you might not be able to diagnose an issue from crash reports."

[Locating a missing debug symbol file](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file)
da las herramientas: `mdfind "com_apple_xcode_dsym_uuids == <UUID>"` y
`dwarfdump --uuid <path-to-dSYM>`. [Adding identifiable symbol names to a crash
report](https://developer.apple.com/documentation/xcode/adding-identifiable-symbol-names-to-a-crash-report)
describe `xcrun crashlog <path-to-crashReport>` y `atos` con la ruta al DWARF dentro del dSYM.

Consecuencia: el UUID ya viene gratis en cada `.ips`. Lo que falta es **guardar, por UUID, el
dSYM y el commit** — el archivo de Xcode que Apple exige, en version SPM.

## 3. Practica en proyectos maduros

| Herramienta | Que hace con la version | Fuente |
|---|---|---|
| agvtool | `agvtool next-version -all` sube al siguiente entero y escribe `CFBundleVersion`; el build es un numero, nunca un hash | [QA1827](https://developer.apple.com/library/archive/qa/qa1827/_index.html) |
| fastlane `increment_build_number` | envuelve agvtool; ejemplos: `latest_testflight_build_number + 1` o `ENV["CI_BUILD_NUMBER"]` — el contador vive fuera de git | [docs](https://docs.fastlane.tools/actions/increment_build_number/) |
| Xcode Cloud | separa tres cosas: `CI_BUILD_NUMBER` ("The number of the current build, for example, 42"), `CI_BUILD_ID` (UUID del build) y `CI_COMMIT` ("The Git commit hash that Xcode Cloud uses for the current build") | [Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference) |
| Sparkle | "the internal version number (`CFBundleVersion` and `sparkle:version`) is intended to be machine-readable and is not generally suitable for formatted text or git changeset IDs" | [Publishing](https://sparkle-project.org/documentation/publishing/) |
| Homebrew casks | versiones compuestas `"1.2.3,456"` separadas con `csv` cuando el build importa; la version sale del producto, no de git | [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) |
| Sentry | release por defecto `bundleId@CFBundleShortVersionString+CFBundleVersion`; los commits se asocian aparte (integracion de repo); los simbolos se suben con `sentry-cli debug-files upload` y "Mach-O files use a UUID" como identificador | [releases](https://docs.sentry.io/platforms/apple/configuration/releases/), [identifiers](https://docs.sentry.io/platforms/apple/data-management/debug-files/identifiers/) |
| Crashlytics | sube dSYMs con `upload-symbols`; para encontrar faltantes: `mdfind -name .dSYM \| while read -r line; do dwarfdump -u "$line"; done` | [Firebase](https://firebase.google.com/docs/crashlytics/get-deobfuscated-reports?platform=ios) |
| SPM build plugins | [PackageBuildInfo](https://github.com/bolsinga/PackageBuildInfo) genera un struct con `isDirty`, `count`, `branch`, `digest` (sha1); [GitCommitInfoPlugin](https://github.com/PGSSoft/GitCommitInfoPlugin) expone el ultimo commit en Swift | enlaces |

Patron comun: **tres identificadores separados** — build number (entero, monotono, fuera de
git), commit (metadata, nunca en `CFBundleVersion`) y UUID/dSYM (el vinculo con el crash).

No verifique que el propio `swift-package-manager` embeba un SHA en su binario; no lo cito
como precedente. Los plugins de arriba si lo hacen.

## 4. Simbolos: archivar dSYM y binario por UUID

Si. Evidencia: SPM ya produce `companion.dSYM` en release con el mismo UUID que el binario
instalado (1.5), pero lo pisa en cada build y por eso los tres crashes son irrecuperables (1.3).

Lo que deberia hacer `bundle.sh` (cambio de script, **requiere aprobacion de Karen**):

1. Leer el UUID: `dwarfdump --uuid "$BIN/Companion"` (una linea por arquitectura; hoy solo arm64).
2. Copiar a `~/Library/Developer/Companion/Builds/<UUID>/`:
   - `companion.dSYM` (de `--show-bin-path`), verificando que su UUID sea el mismo;
   - el binario sin firmar tal como salio de SPM (tabla de simbolos completa, para `atos`);
   - `build.json`: version, build, commit completo, dirty, config, fecha UTC, `swift --version`,
     rama y ruta del worktree (aqui si: es local, nunca viaja);
   - si dirty: `git diff HEAD --binary > dirty.patch` y la lista de archivos sin trackear
     relevantes. Esto es lo unico que hace trazable un build hecho desde un arbol sucio: el
     hash solo dice "partio de aqui", el patch dice "y con esto encima".
3. Que el directorio quede indexado por Spotlight, para que `mdfind com_apple_xcode_dsym_uuids`
   y `xcrun crashlog` encuentren el dSYM solos. Verificar el estado de indexado: en esta Mac
   `mdutil -s ~` devolvio "unknown indexing state", asi que el plan de prueba debe comprobarlo
   y, si falla, documentar `atos -o <UUID>/companion.dSYM/Contents/Resources/DWARF/companion`.
4. Retencion: el dSYM pesa ~30 MB. Poda por antiguedad (p. ej. conservar 60 dias o los ultimos
   N), nunca borrar los de un tag de release. `HACK:` en el script con el umbral.

Stripping: hoy no se hace. Recomiendo **no stripear el build local** (Karen gana nombres de
funcion en ReportCrash sin herramientas) y **si stripear el DMG de `release.sh`** con
`strip -S` (quita el debug map `OSO` con rutas absolutas) **antes** de firmar y **despues** de
archivar. `strip` conserva `LC_UUID`, asi que el dSYM archivado sigue sirviendo. Las rutas del
accessor de `Bundle.module` no se van con `strip` (son literales de string); eso es un hallazgo
aparte para `security-reviewer`. Decision de Karen.

## 5. Monotonia del numero de build

`rev-list --count HEAD` cuenta commits alcanzables desde HEAD. Falla en todo lo que este
proyecto hace a diario:

- **Rebase/squash**: reduce o reordena el conteo; un numero ya emitido pasa a nombrar otro commit.
- **Varios worktrees/ramas**: cada uno cuenta su propia historia (instalado 184 desde
  `ui-gap-q1`, main 239); el numero puede bajar al instalar desde otra rama.
- **Arboles sucios**: N builds distintos desde el mismo HEAD comparten numero (evidencia:
  dos UUID con build 106).
- Sin git (tarball o descarga de GitHub): cae a `0`.

Alternativas:

| Opcion | Monotono | Unico | Contras |
|---|---|---|---|
| `rev-list --count` (hoy) | no | no | ver arriba |
| Timestamp UTC `date -u +%y%m%d%H%M` (p. ej. `2609301542`) | si en una Mac | por minuto | no reproducible (solo si va en el plist, no en el binario, no afecta al binario); dos builds en el mismo minuto chocan |
| Numero de corrida de CI (`GITHUB_RUN_NUMBER`) | si | si | hoy CI solo corre `gates.sh`, no empaqueta; los builds de Karen son locales |
| Archivo contador (`~/Library/.../build-counter`) | si en una Mac | si | estado fuera del repo; otra Mac empieza de cero |
| Fecha del commit `%ct` | casi (rebase la reescribe hacia adelante) | no con arbol sucio | mezcla dos cosas |

Recomendacion: **timestamp UTC de 10 digitos** en `CFBundleVersion`. Es un entero valido para
Apple (1 componente), siempre sube respecto a 106/184/239, no depende de la historia de git y
nadie en el codigo lee ese valor. Si algun dia CI empaqueta releases, pasar a su run number
(tiene que ser mayor que el ultimo timestamp emitido; conviene decidir el esquema antes del
primer release publico por CI). El build number deja de ser el identificador: lo es el UUID.

## 6. Riesgos

### 6.1 Filtrar informacion por el plist

- El repo `karenrebecag/Companion` es publico (MIT, `UpdateChecker` apunta a sus releases):
  el SHA de un commit publicado no revela nada. Un SHA de un commit no publicado solo revela
  que existe.
- **No** poner en el plist: rama, nombre del worktree, ruta, usuario, hostname, diff. Esos van
  solo en `build.json` local.
- El flag dirty si es publico y dice "este binario no corresponde a ningun commit". Aceptable
  para builds locales; para el DMG de release, ver 6.3.
- El riesgo real de fuga hoy esta en el binario (1.5), no en el plist.

### 6.2 Reproducibilidad

- Poner commit/timestamp **solo en el plist** no cambia el binario: el mismo codigo sigue dando
  el mismo `LC_UUID` (con la misma toolchain y ruta de build). Ver
  [SOURCE_DATE_EPOCH](https://reproducible-builds.org/docs/source-date-epoch/): el tiempo que se
  embebe debe salir de la fuente, no del reloj del build.
- Un archivo Swift generado con el SHA (estilo PackageBuildInfo) cambiaria el binario en cada
  commit y, si `bundle.sh` lo escribe dentro de `Sources/`, **ensucia el arbol que el propio
  flag dirty mide**. No lo recomiendo: el plist + leer `Bundle.main` basta.
- El UUID tampoco es un hash del codigo: depende de toolchain, flags y ruta absoluta del build
  (Apple: "different Xcode versions or build settings" dan UUID distinto). Por eso se registra
  `swift --version` en `build.json`.

### 6.3 Un flag dirty equivocado

Probado en este worktree, que tiene un archivo sin trackear
(`docs/research/comparativa-calidad-...md`):

- `git describe --always --dirty` -> `v0.10.0-174-gb494e9e41cd0` (sin `-dirty`).
- `git diff --quiet HEAD` -> exit 0 (limpio).

Ambos **ignoran archivos sin trackear**. Un `.swift` nuevo sin `git add` entra al build (SPM
compila todo lo que hay en `Sources/`) y el flag diria "limpio": el peor caso, un falso negativo.
`git status --porcelain` si ve sin trackear, pero marcaria dirty por un doc en `docs/`
(falso positivo). Ademas, los archivos **ignorados** tambien entran: las fuentes propietarias
de `.gitignore` (`Gadey-Regular.otf`, `TBJInterval-*`) se copian al bundle si existen, y ningun
flag de git las ve.

Regla propuesta:

```
dirty = cambios en tracked (git diff --quiet HEAD, cubre staged + unstaged)
     OR sin trackear bajo lo que entra al build:
        git status --porcelain --untracked-files=all -- \
          Package.swift Sources Extensions assets scripts
```

Y en `build.json`, una huella de lo ignorado que entra al bundle (p. ej. `fonts: proprietary`
o `fonts: inter-only`), no en el plist.

Si no hay git (`git rev-parse` falla): `CompanionGitCommit = unknown`, `dirty = true`. Nunca
`0` ni vacio silencioso.

Politica para `release.sh` (decision de Karen): o rechazar un DMG con dirty = true, o
permitirlo con aviso. Para `bundle.sh` local no conviene bloquear: Karen trabaja sobre el
producto instalado desde worktrees en curso, y ahi el patch archivado es lo que salva la traza.

## 7. Recomendacion concreta

### 7.1 Que va en cada clave

| Clave | Valor | Ejemplo | Por que |
|---|---|---|---|
| `CFBundleShortVersionString` | `Build.version` (sin cambio) | `0.10.0` | regla de Apple, la ve el usuario, la compara `UpdateChecker` |
| `CFBundleVersion` | `date -u +%y%m%d%H%M` | `2609301542` | entero monotono, llega al `.ips` como `build_version` |
| `CompanionGitCommit` (nueva) | SHA completo de 40 hex, o `unknown` | `b494e9e41cd0...` | el abreviado puede volverse ambiguo; el completo nunca |
| `CompanionGitDirty` (nueva) | `<true/>` / `<false/>` segun 6.3 | `false` | booleano de plist, no string |

No agregar rama, ruta ni fecha legible al plist.

### 7.2 Que mas hace `bundle.sh`

1. Calcular commit + dirty (regla 6.3) antes de `swift build`, para no medir artefactos propios.
2. Escribir las claves de 7.1.
3. Tras copiar el binario y antes de firmar: leer UUID y archivar segun seccion 4.
4. Imprimir al final una linea: `build 2609301542 commit b494e9e41cd0 dirty=false uuid EAEAA024-...`.

`release.sh`: `strip -S` despues de archivar y antes de `codesign`, y la politica de dirty.

### 7.3 Que loggea la app al arrancar

Una linea en `Companion.log`, junto a (o en lugar de) `Log.app("launched")`:

```
launched version=0.10.0 build=2609301542 commit=b494e9e41cd0 dirty=false uuid=EAEAA024-3D85-3F48-9E83-F8C090CBAC1D identity=release
```

- version/build/commit/dirty: de `Bundle.main.infoDictionary`; con `swift run` no hay plist,
  asi que cada campo cae a `unknown` (mismo criterio que `ProductIdentity.of(bundleID: nil)`).
- uuid: leido en runtime del ejecutable principal (`_dyld_get_image_header(0)` y recorrer los
  load commands hasta `LC_UUID`). No se puede sellar en el plist con certeza y es la clave que
  une el log con el `.ips`.
- Ubicacion por capas: el parseo del diccionario a un struct `BuildStamp` y el formato de la
  linea son puros -> Core (testeables sin bundle); la lectura de `LC_UUID` usa `MachO`/dyld ->
  Services o App, no Core. Verificar que Gate 3 no prohiba `import MachO` en la capa elegida.
- Opcional: mostrar `build` y commit corto en Settings > Sistema junto a la version (hoy solo
  `CFBundleShortVersionString`).

Con esto, ante un crash: `slice_uuid` del `.ips` -> carpeta `Builds/<UUID>/` -> `build.json`
(commit, dirty) + `dirty.patch` + dSYM -> `xcrun crashlog` con lineas. Y el log de esa sesion
confirma el mismo UUID.

## 8. Plan de pruebas

Unitarios (Swift Testing, en `swift test`, sin tocar `/Applications`):

1. `bundle.sh` ya no contiene `rev-list --count` y si contiene `CompanionGitCommit`,
   `CompanionGitDirty` y el archivado por UUID (mismo patron que
   `testTheBundleScriptMatchesTheSource`).
2. `BuildStamp.from(infoDictionary:)`: diccionario completo; sin claves (`swift run`) ->
   todo `unknown`; `CompanionGitDirty` ausente -> dirty `true` (desconocido no es limpio);
   tipos equivocados (string en vez de bool) -> `unknown`, sin crash.
3. Formato de la linea de log: campos en orden fijo, sin rutas ni rama.
4. Lector de `LC_UUID`: sobre el ejecutable del propio test runner devuelve un UUID con formato
   8-4-4-4-12 y coincide con `dwarfdump --uuid` de ese mismo archivo.

Script (bash en un clon temporal; requiere un modo sin instalar, p. ej.
`COMPANION_NO_INSTALL=1`, que tambien es cambio de script):

5. Arbol limpio -> dirty `false`.
6. Modificar un `.swift` trackeado -> `true`; solo staged -> `true`.
7. `.swift` nuevo sin trackear en `Sources/` -> `true` (el caso que `--dirty` no ve).
8. Archivo sin trackear en `docs/` -> `false`.
9. Sin `.git` -> commit `unknown`, dirty `true`, el script no aborta.
10. Dos bundles seguidos -> `CFBundleVersion` estrictamente creciente (o fallo explicito si
    caen en el mismo minuto).
11. `plutil -extract CFBundleVersion raw` pasa la regex `^[0-9]+(\.[0-9]+){0,2}$`.
12. `Builds/<UUID>/` existe, el UUID de su dSYM == `dwarfdump --uuid` del binario del `.app`
    firmado; con arbol sucio existe `dirty.patch` y aplica limpio sobre el commit registrado.
13. `release.sh`: tras `strip -S`, `nm -ap | grep -c ' OSO '` == 0 y el UUID no cambio.

End to end (manual, Karen):

14. Bundle, abrir la app, `grep launched ~/Library/Logs/Companion.log` -> UUID igual al de
    `dwarfdump --uuid /Applications/Companion.app/Contents/MacOS/Companion`.
15. Provocar un crash en un build de prueba, tomar el `.ips`, verificar que `slice_uuid` lleva
    a su carpeta y que `xcrun crashlog` (o `atos` con el dSYM archivado) da archivo:linea.

## 9. Que requiere aprobacion de Karen

| Cambio | Tipo | Aprobacion |
|---|---|---|
| `scripts/bundle.sh`: `CFBundleVersion` por timestamp, claves nuevas, regla de dirty, archivado por UUID, modo sin instalar | script de build | **si** |
| `scripts/release.sh`: `strip -S`, politica ante dirty | script de build/distribucion | **si** |
| `scripts/gates.sh`: gate que verifique las claves nuevas en `bundle.sh` (como hoy con `NS*UsageDescription`) | config de gates | **si** |
| Directorio de archivo `~/Library/Developer/Companion/Builds/` y su retencion | config local | **si** (decide ubicacion y dias) |
| `BuildStamp` en Core, lector de `LC_UUID`, linea de log al arrancar, tests | codigo multi-archivo | spec aprobado antes de codear (regla 1 de `CLAUDE.md`) |
| Rutas absolutas en el binario distribuido (`Bundle.module`, `OSO`) | hallazgo de seguridad | pasar a `security-reviewer` -> `tdd-guide` |

Nada de esto se aplico: este documento es solo investigacion.
