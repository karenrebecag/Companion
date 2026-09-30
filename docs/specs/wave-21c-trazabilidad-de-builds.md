# Wave 21c — Trazabilidad de builds: de un crash report al código exacto

**Estado: APROBADO (2026-09-30).** Karen firmó D1–D8 tal como se recomiendan y autorizó los
cambios de scripts de esta wave (`bundle.sh`, `release.sh` y, si hace falta, `gates.sh`); D9 y
D10 decididos por ella el mismo día (ver §D9, §D10). `Package.swift` sigue fuera salvo
aprobación aparte.

Base: `docs/research/trazabilidad-builds-investigacion-2026-09-30.md` (en adelante "inv.",
citada por sección). Formato: `wave-20c-endurecimiento-aprobaciones.md`.

**Escrito contra la estructura posterior a la reorganización de `Sources`.** Otra sesión está
moviendo archivos. Esta spec asume lo que queda después de esa reorganización:

- `bundle.sh` lee la versión de `Sources/CompanionCore/Platform/Build.swift`;
- la regex de `SessionMachine` en `gates.sh` apunta a `Core/Session/`;
- `Build`, `SemanticVersion` y `ProductIdentity` viven en `Sources/CompanionCore/Platform/`.

Por eso no se citan números de línea de los scripts: se nombra el bloque (el heredoc del
plist, el `cp` del binario, el `codesign`, el bucle de `NS*UsageDescription`). Si la
reorganización no ha llegado a main cuando arranque la primera sesión, esa sesión se rebasa
sobre ella; no se escribe contra las rutas viejas.

## 1. Por qué

Hubo tres crashes (`Companion-2026-09-23-104525.ips`, `...-105123.ips` y
`...-2026-09-26-002033.ips`) y hoy ninguno se puede llevar a archivo y línea (inv. §1.3):

- vienen de **dos binarios distintos** (UUID `72285568-...` y `0A51558C-...`) que se
  reportaron los dos como build `106`, así que el número de build no identifica nada;
- los dSYM de esos UUID ya no existen, porque SPM pisa
  `.build/.../release/companion.dSYM` en cada build. Esos tres crashes **se perdieron** y
  esta wave no los recupera;
- `CFBundleVersion = rev-list --count HEAD` no es ni monótono ni único: la app instalada
  dice 184 (salió de `ui-gap-q1`), main dice 239 y el commit 106 de main no tiene nada que
  ver con los crashes (inv. §1.4, §5).

Sellar el commit en el plist ayuda, pero no alcanza: el `.ips` solo copia
`CFBundleShortVersionString`, `CFBundleVersion` y `CFBundleIdentifier` a `bundleInfo`, así
que una clave propia **nunca aparece en el reporte** (inv. §2.2). Lo que sí trae siempre es el
UUID del binario (`slice_uuid`), que es el vínculo canónico de Apple entre un crash y su dSYM
(inv. §2.3). Por eso la cadena que se construye es:

```
.ips (slice_uuid) -> Builds/<UUID>/ -> build.json (commit, dirty) + dirty.patch + dSYM -> xcrun crashlog
```

## 2. Objetivo y no-objetivos

**Objetivo.** Que cualquier crash de un build hecho desde hoy se pueda llevar a
commit + diff + archivo:línea, usando solo el `.ips` y el archivo local por UUID.

**No-objetivos.**

- Recuperar los tres crashes de septiembre (inv. §1.3).
- Subir símbolos a un servicio externo (Sentry, Crashlytics). Todo queda en la Mac de Karen.
- Builds reproducibles bit a bit. Solo se evita empeorarlos (inv. §6.2).
- Empaquetar en CI. Hoy CI solo corre `gates.sh` (inv. §5).
- Mostrar el build o el commit en Settings. Es opcional en inv. §7.3 y queda fuera; si se
  quiere, va en otra wave.
- Generar un `.swift` con el SHA. Ensuciaría el mismo árbol que el flag dirty mide
  (inv. §6.2).

## 3. Qué va dónde

| Clave / dato | Valor | Dónde vive | Quién lo lee |
|---|---|---|---|
| `CFBundleShortVersionString` | `Build.version` (sin cambio) | plist | usuaria, `UpdateChecker`, `.ips` (`bundleInfo`) |
| `CFBundleVersion` | timestamp UTC de 10 dígitos `date -u +%y%m%d%H%M` (D1) | plist | `.ips` (`build_version`), log de arranque |
| `CompanionGitCommit` (nueva) | SHA de 40 hex, o `unknown` | plist | `BuildStamp`, log de arranque |
| `CompanionGitDirty` (nueva) | `<true/>` / `<false/>`, según la regla de §3.1 | plist | `BuildStamp`, log de arranque |
| UUID del binario | `LC_UUID`, leído en runtime | binario (no se sella) | `.ips` (`slice_uuid`), log de arranque, nombre de la carpeta del archivo |
| rama, ruta del worktree, `swift --version`, config, fecha, huella de fuentes | texto | solo `build.json` local | Karen al diagnosticar |
| diff sin commit | `git diff HEAD --binary` + lista de archivos sin trackear relevantes | solo `dirty.patch` local | Karen al diagnosticar |

En el plist nunca van la rama, la ruta, el usuario, el hostname ni el diff (inv. §6.1, §7.1).

### 3.1 Regla de dirty

La regla está en inv. §6.3. `git describe --dirty` y `git diff --quiet HEAD` **no ven archivos
sin trackear**, y un `.swift` nuevo sin `git add` entra al build. Por eso:

```
dirty = NOT (git diff --quiet HEAD)                         # staged + unstaged
     OR hay salida de: git status --porcelain --untracked-files=all -- \
          Package.swift Sources Extensions assets scripts
     OR git rev-parse falla (sin git)                       # desconocido nunca es limpio
```

Se calcula **antes** de `swift build`, para no medir artefactos del propio build. Si hay
archivos sin trackear en `docs/`, dirty no se enciende.

## 4. Archivo por UUID

Ubicación: `~/Library/Developer/Companion/Builds/<UUID>/` (D2). Cada carpeta lleva:

```
<UUID>/
  companion.dSYM/        # copiado de --show-bin-path; su UUID se verifica igual al binario
  Companion              # binario sin firmar ni stripear, tal como salió de SPM (D3)
  build.json             # version, build, commit, dirty, config, fecha UTC, swift --version,
                         # rama, ruta del worktree, huella de fuentes (proprietary | inter-only)
  dirty.patch            # solo si dirty: git diff HEAD --binary + sin trackear relevantes
```

- El UUID sale de `dwarfdump --uuid` sobre el binario copiado, justo **después** del `cp` al
  `.app` y **antes** del `codesign`. `codesign` no altera `LC_UUID` (inv. §1.5).
- Si el UUID del dSYM no coincide con el del binario, el script **falla**. Un archivo con el
  dSYM equivocado es peor que no tener archivo.
- Hoy el binario es de una sola arquitectura (arm64). Si algún día hay varias, se usa una
  carpeta por UUID y `build.json` lista las demás.
- Retención (D2): se podan las carpetas de más de N días, salvo las marcadas `release` en
  `build.json` con un tag de versión, que nunca se podan. El umbral va en un `HACK:` del script
  que dice cuándo revisarlo: "si el directorio pasa de X GB".
- Spotlight: si `mdfind "com_apple_xcode_dsym_uuids == <UUID>"` encuentra el dSYM, entonces
  `xcrun crashlog` funciona solo. En esta Mac `mdutil -s ~` dio "unknown indexing state"
  (inv. §4), así que el camino documentado es
  `atos -o Builds/<UUID>/companion.dSYM/Contents/Resources/DWARF/companion`.

## 5. Línea de arranque

`Log.app("launched")` se reemplaza por:

```
launched version=0.10.0 build=2609301542 commit=b494e9e41cd0... dirty=false uuid=EAEAA024-3D85-3F48-9E83-F8C090CBAC1D identity=release
```

- Los campos van en un orden fijo, separados por un espacio, con formato `clave=valor`.
- El commit va completo, con 40 hex (inv. §7.1).
- Con `swift run` no hay plist: version, build y commit caen a `unknown`, dirty cae a `true` y
  identity queda en `development`, con el mismo criterio que `ProductIdentity.of(bundleID: nil)`.
- El UUID se lee en runtime del ejecutable principal: `_dyld_get_image_header(0)`, y se
  recorren los load commands hasta `LC_UUID`. Si no se encuentra, sale `uuid=unknown` y la app
  no aborta.
- El parseo del diccionario y el formato de la línea son puros y van en Core (`BuildStamp`).
  La lectura de `LC_UUID` usa `MachO`, así que va en Services. Gate 3 solo le prohíbe
  `SwiftUI` a Services (inv. §7.3).

## 6. Rutas privadas en el binario (hallazgo aparte)

Es un hallazgo de seguridad, así que va en su propia sesión: S5, con **security-reviewer**
primero y **tdd-guide** después, nunca como fix directo.

Hoy el binario instalado embebe rutas absolutas con el usuario y el nombre del worktree. Se
confirmaron 2 strings con `~/Desktop/SoftwareDevProjects/companion-next-ui-gap-q1`, que vienen
del accessor que SPM genera para `Bundle.module`, y además 413 entradas `OSO` del debug map
(inv. §1.5). El DMG distribuido filtra esas rutas diga lo que diga el plist.

Son dos fuentes, y cada una tiene su remedio:

| Fuente | Qué la quita | Qué no la quita |
|---|---|---|
| `OSO` (debug map) | `strip -S` en `release.sh` (D4); o `-debug-prefix-map "$ROOT=."` | — |
| Literales del accessor de `Bundle.module` (5 usos: `Typography`, `Localized`, `ApprovalSheet`, `WebKitDiagramRenderer`, `SkillStore`) | resolver los recursos desde `Bundle.main.resourceURL` con un accessor propio; o compilar desde una ruta canónica neutra | `strip` (son literales de string, no símbolos) |
| `#filePath` o `#file`, si aparece en `Sources` | `-file-prefix-map "$ROOT=."` | — |

D5 decide entre pasar los flags por `bundle.sh` (`swift build -Xswiftc -debug-prefix-map
-Xswiftc "$ROOT=."`), lo que deja `Package.swift` intacto, o usar `unsafeFlags` en
`Package.swift`. Falta verificar en Swift 6.3 que `-file-prefix-map` exista y afecte lo que se
espera; hasta verificarlo, "I don't know". La prueba de éxito no depende del mecanismo:
`strings` sobre el binario del `.app` y sobre el del DMG da 0 coincidencias de `$HOME` y del
nombre del worktree.

## 7. Archivos

Toda fila marcada **aprobación** necesita la aprobación explícita de Karen para ese cambio,
además de la firma de esta spec (regla global: scripts y configs raíz están bloqueados).

| Archivo | Cambio | Sesión | Aprobación |
|---|---|---|---|
| `Sources/CompanionCore/Platform/BuildStamp.swift` (nuevo) | struct puro + formato de la línea | S1 | spec |
| `Sources/CompanionServices/Platform/ExecutableUUID.swift` (nuevo, junto a Log, UpdateChecker y los stores de Keychain) | lector de `LC_UUID` | S1 | spec |
| `Tests/CompanionTests/BuildStampTests.swift` (nuevo) | casos 1–4 de §10 | S1 | spec |
| el sitio de `Log.app("launched")` en `CompanionApp` | usar `BuildStamp` + UUID | S1 | spec |
| `scripts/bundle.sh` | timestamp, claves nuevas, dirty, `COMPANION_NO_INSTALL`, archivo, poda | S2, S3 | **necesita aprobación explícita de Karen** |
| `scripts/tests/bundle-stamp.sh` (nuevo) | harness en clon temporal, casos 5–12 | S2, S3 | **necesita aprobación explícita de Karen** |
| `Tests/CompanionTests/BuildScriptTests.swift` (nuevo) | lectura de `bundle.sh` como texto, mismo patrón que `testTheBundleScriptMatchesTheSource` | S2 | spec |
| `scripts/release.sh` | `strip -S` entre el archivo y la firma; política ante dirty (D7) | S4 | **necesita aprobación explícita de Karen** |
| `scripts/gates.sh` | gate nuevo junto al bucle de `NS*UsageDescription`: `bundle.sh` declara `CompanionGitCommit` y `CompanionGitDirty` y no contiene `rev-list --count` | S4 | **necesita aprobación explícita de Karen** |
| `Package.swift` | solo si D5 elige `unsafeFlags` | S5 | **necesita aprobación explícita de Karen** |
| accessor de recursos propio (UI/Services) | solo si D5 lo elige | S5 | spec + security-reviewer |

## 8. API (`package`, no `public`)

```swift
// Sources/CompanionCore/Platform/BuildStamp.swift
package struct BuildStamp: Sendable, Equatable {
    package static let unknown = "unknown"
    package enum Key {
        package static let commit = "CompanionGitCommit"
        package static let dirty  = "CompanionGitDirty"
    }
    package let version: String   // x.y.z o "unknown"
    package let build: String     // ^[0-9]+(\.[0-9]+){0,2}$ o "unknown"
    package let commit: String    // ^[0-9a-f]{40}$ o "unknown"
    package let dirty: Bool       // ausente, o de un tipo que no es Bool -> true

    package init(version: String, build: String, commit: String, dirty: Bool)
    package static func from(infoDictionary: [String: Any]?) -> BuildStamp
    package func launchLine(uuid: UUID?, identity: ProductIdentity) -> String
}

// CompanionServices
package enum ExecutableUUID {
    /// LC_UUID of the main executable; nil when the load command is missing.
    package static func ofMainExecutable() -> UUID?
}
```

`from` valida cada campo contra su formato. Un valor que no pasa la validación cae a
`unknown`: nada venido del plist llega crudo al log. Si el diccionario es `nil` o está vacío,
sale `unknown` en todo y dirty en `true`.

## 9. Invariantes

- **I1** En el plist no hay ninguna ruta, usuario, hostname, rama ni diff. Solo las cuatro
  claves de §3 más las que ya existen.
- **I2** El flag dirty **nunca es falsamente limpio**. Un cambio sin commit (tracked o sin
  trackear) bajo `Package.swift`, `Sources`, `Extensions`, `assets` o `scripts` da `true`, y
  la ausencia de git da `true`. Se tolera un falso positivo; un falso negativo no.
- **I3** `CFBundleVersion` cumple `^[0-9]+(\.[0-9]+){0,2}$` (inv. §2.1) y crece estrictamente
  entre dos bundles en la misma Mac. Si dos bundles caen en el mismo minuto, el script falla
  explícitamente; no repite el número en silencio.
- **I4** Cada `.app` producido por `bundle.sh` tiene su carpeta `Builds/<UUID>/` con un dSYM
  cuyo UUID es igual al del binario firmado. El archivo se escribe antes de firmar y antes de
  `strip`.
- **I5** `strip` conserva `LC_UUID`. Un binario del DMG y su carpeta archivada comparten UUID.
- **I6** La línea de arranque solo contiene campos validados. Ningún campo lleva espacios,
  saltos de línea ni rutas.
- **I7** `COMPANION_NO_INSTALL=1` no toca `/Applications`, y el resto del flujo es idéntico.
- **I8** Ninguna carpeta con tag de release se poda.

## 10. Plan de pruebas (15 casos, inv. §8)

Unitarios (Swift Testing, `swift test`, sin tocar `/Applications`):

1. `BuildScriptTests`: `bundle.sh` ya no contiene `rev-list --count`, y sí contiene
   `CompanionGitCommit`, `CompanionGitDirty`, `COMPANION_NO_INSTALL` y el archivado en
   `Builds/`.
2. `BuildStamp.from`: con el diccionario completo; con `nil`, todo es `unknown` y dirty es
   `true`; si falta `CompanionGitDirty`, dirty es `true`; si viene un string en vez de un bool,
   dirty es `true`; un commit de 7 hex o con espacios da `unknown`; un build `"12a"` da
   `unknown`.
3. `launchLine`: los campos van en orden fijo, sin `/` fuera de lo esperado, sin espacios
   dentro de un valor y sin saltos de línea.
4. `ExecutableUUID.ofMainExecutable()` sobre el runner de tests devuelve un UUID igual al de
   `dwarfdump --uuid` de ese mismo ejecutable.

Script (`scripts/tests/bundle-stamp.sh` en un clon temporal con `COMPANION_NO_INSTALL=1`):

5. Con el árbol limpio, dirty es `false`.
6. Un `.swift` trackeado modificado da `true`; un cambio solo en staged también da `true`.
7. Un `.swift` nuevo sin trackear en `Sources/` da `true`: es el caso que `--dirty` no ve.
8. Un archivo sin trackear en `docs/` da `false`.
9. Sin `.git`, el commit es `unknown`, dirty es `true` y el script no aborta.
10. Dos bundles seguidos dan un `CFBundleVersion` estrictamente creciente, o un fallo explícito
    si caen en el mismo minuto.
11. `plutil -extract CFBundleVersion raw` pasa la regex de I3.
12. `Builds/<UUID>/` existe y el UUID de su dSYM es igual al `dwarfdump --uuid` del binario
    firmado. Con el árbol sucio existe `dirty.patch`, y aplica limpio sobre el commit
    registrado (`git apply --check`).
13. `release.sh` (o su parte de `strip`, aislada): después de `strip -S`,
    `nm -ap | grep -c ' OSO '` da 0 y el UUID no cambió.

End to end (manual, Karen): 14 y 15 son el chequeo en vivo de §14.

## 11. Decisiones (firma Karen)

- **D1 — Número de build.** Las opciones son: timestamp UTC de 10 dígitos, un archivo
  contador en la Mac, o el número de corrida de CI.
  **Recomendación: timestamp** (`date -u +%y%m%d%H%M`). Es un entero válido para Apple, supera
  a 106/184/239, no depende de la historia de git y nadie lo lee en el código. El contador
  vive fuera del repo y empieza de cero en otra Mac. El número de CI no sirve hoy, porque CI no
  empaqueta. Cuando CI empaquete releases, su esquema tendrá que arrancar por encima del último
  timestamp emitido (inv. §5).
- **D2 — Dónde y cuánto se archiva.** **Recomendación:**
  `~/Library/Developer/Companion/Builds/` (fuera de los worktrees, así que sobrevive a borrar
  uno), con 60 días de retención y las carpetas de release para siempre. Cada carpeta pesa
  unos 30 MB de dSYM más el binario (inv. §4). La alternativa de "los últimos N" castiga los
  días de muchos bundles.
- **D3 — Archivar el binario sin stripear.** **Recomendación: sí.** Duplica el peso, pero
  permite correr `atos` contra el binario exacto y deja rehacer un DMG stripeado sin
  recompilar. Si el espacio aprieta, se guarda solo el dSYM.
- **D4 — Stripear.** **Recomendación:** no stripear el build local de `bundle.sh` (ReportCrash
  sigue dando nombres de función sin herramientas) y sí correr `strip -S` en `release.sh`,
  **después** de archivar y **antes** de `codesign` (inv. §4). `strip` no toca las rutas de
  `Bundle.module`; eso lo resuelve D5.
- **D5 — Rutas privadas en el binario.** Hay dos opciones para los flags: (a)
  `-debug-prefix-map`/`-file-prefix-map` pasados desde `bundle.sh` con `-Xswiftc`, o (b) esos
  mismos flags con `unsafeFlags` en `Package.swift`. Y hay dos para `Bundle.module`: (c) un
  accessor propio sobre `Bundle.main.resourceURL`, o (d) compilar el release desde una ruta
  canónica.
  **Recomendación: (a) + (c)**, decidido después del informe de security-reviewer en S5.
  (a) no toca la config raíz. (c) elimina el literal de raíz, en vez de disfrazarlo.
  Por qué se reemplaza `Bundle.module`: el accessor que genera SPM guarda la ruta absoluta de
  compilación como literal de string, y `-file-prefix-map` no lo reescribe; el binario deja
  de ser reproducible y lleva el usuario y el worktree.
  **Hallazgo que cambia (c), verificado 2026-09-30** (informe
  `~/Desktop/research-loop-spec/piloto/recursos-empaquetados-bundle-module.md`, 40 citas
  re-leídas; el accessor lo comprobé en `.build/.../CompanionUI.build/DerivedSources/resource_bundle_accessor.swift`):
  el `Bundle.module` que genera `swift build` (backend nativo, 6.3.3) busca el bundle en la
  RAÍZ de la `.app` y después en la ruta absoluta del `.build` de este checkout, y si no,
  `fatalError`. `bundle.sh` copia los bundles a `Contents/Resources`, que el accessor nunca
  mira: la app instalada funciona solo porque el `.build` del worktree desde el que se
  compiló existe. Un DMG en otra Mac, o esta Mac tras borrar ese `.build`, hace trap al
  arrancar en `Fonts.register()` (derivado del código, no ejecutado; S5 lo prueba primero).
  Además la app instalada lee sus recursos del `.build`, no de lo que se firmó.
  **Por eso (c) es la opción C del informe** (patrón de CodexBar tras su incidente 0.48.0):
  un resolver por módulo con recursos (`CompanionUI`, `CompanionServices`) que prueba en
  orden `Contents/Resources` de `Bundle.main` si es una `.app`, junto al ejecutable, y
  `Bundle.module` solo si el bundle de `.build` existe (así `swift test` y `swift run` siguen
  funcionando, porque ahí `Bundle.main` es el runner o el ejecutable), y si no, `nil`. Los
  recursos pasan a opcionales: sin bundle se registra y la función degrada (sin fuentes
  propias, sin skills de sistema, sin diagramas, claves crudas), nunca trap. Las fuentes
  quedan en un solo lugar (hoy `bundle.sh` las duplica). Un modo de probe por variable de
  entorno fuerza todas las cargas (fuentes, `.lproj` en y es, mascota, skills, mermaid) y
  sale con un marcador; `bundle.sh` lo corre sobre la app empaquetada con el checkout
  inaccesible y falla el empaquetado si no llega el marcador. S5 lleva tests del resolver
  con bundles falsos para los tres casos (app, ejecutable, nada) y registra la cicatriz en
  `docs/REFERENCE.md`. Construir con `--build-system swiftbuild` (opción D del informe) se
  evalúa después, no en esta wave.
  **Esto sube de prioridad dentro de 21c:** es un crash de arranque latente, no solo
  privacidad. Pasa a ser la primera sesión con código de la wave.
- **D6 — Modo sin instalar.** **Recomendación:** `COMPANION_NO_INSTALL=1` como variable de
  entorno. Construye, firma y archiva igual, pero no toca `/Applications`. Sin este modo, los
  casos 5–12 no se pueden automatizar sin pisar la app de Karen (inv. §8).
- **D7 — Un DMG con dirty.** **Recomendación:** `release.sh` **rechaza** dirty = true, con la
  válvula `COMPANION_ALLOW_DIRTY=1`, que lo deja pasar con un aviso impreso. `bundle.sh` local
  nunca bloquea, porque ahí el patch archivado es lo que salva la traza (inv. §6.3).
- **D9 — ¿El resolver cubre también `BrowserExtension`?** Esa carpeta no es recurso de
  SwiftPM: la copia `bundle.sh` y se lee con `Bundle.main.resourceURL`, así que no sufre el
  fallo del accessor. **Recomendación:** dejarla fuera del resolver, pero dentro del probe de
  empaquetado, para que su ausencia también rompa el empaquetado.
  **Respuesta de Karen (2026-09-30, vía 8f):** "browserextension está actualizada en Comet".
  Eso confirma que la extensión que carga Comet está al día; no decide si el probe exige que
  la copia dentro de `Companion.app/Contents/Resources/BrowserExtension` exista.
  **Decidido (Karen, 2026-09-30, vía 8f):** "El browser extension es indispensable." El probe
  de empaquetado FALLA si falta `BrowserExtension` dentro de `Companion.app`. Sigue fuera del
  resolver.
- **D10 — Cómo se aísla el checkout en el smoke de empaquetado.** (a) `sandbox-exec`
  negando la lectura bajo el checkout (Apple lo marca obsoleto, pero sigue disponible y es lo
  que usa CodexBar); (b) copiar la app a otra cuenta de usuario o a la VM. **Recomendación:
  (a)**, con un test del propio gate que confirme que el sandbox niega de verdad (si
  `sandbox-exec` desaparece, el gate falla y se reabre la decisión, no pasa en silencio).
  **Decidido (Karen, 2026-09-30, vía 8f):** (a), `sandbox-exec` aceptado para el gate.
- **D8 — Cómo provocar el crash de la prueba en vivo.** Hoy **no existe** ningún disparador de
  crash solo para debug en el código. Se buscaron `crash`, `fatalError` y `abort` en
  `Sources`; el único `fatalError` es el `init(coder:)` de `ParticlesView`, que no se puede
  alcanzar. Las opciones son: (a) `kill -SEGV <pid>` desde Terminal, que no toca código; o (b)
  un disparador nuevo detrás de `#if DEBUG`, que no llega al build `release` que Karen instala.
  **Recomendación: (a).** Hay que verificar en vivo que ReportCrash escribe un `.ips` para una
  señal enviada desde fuera; si no lo escribe, se reabre la decisión.

## 12. Sesiones (para `/ship`, máximo 5 archivos, test en rojo primero)

| Sesión | Cubre | Archivos | Depende de | Aprobación de script |
|---|---|---|---|---|
| S1 | `BuildStamp` + `ExecutableUUID` + línea de arranque | `BuildStamp.swift`, `ExecutableUUID.swift`, `BuildStampTests.swift`, sitio de `launched` (4) | reorganización en main | no |
| S2 | plist: timestamp, commit, dirty, `COMPANION_NO_INSTALL` | `bundle.sh`, `scripts/tests/bundle-stamp.sh`, `BuildScriptTests.swift` (3) | S1, D1, D6 | **sí** |
| S3 | archivo por UUID + `build.json` + `dirty.patch` + poda | `bundle.sh`, `scripts/tests/bundle-stamp.sh`, `BuildScriptTests.swift` (3) | S2, D2, D3 | **sí** |
| S4 | `strip -S` + política dirty + gate de claves | `release.sh`, `gates.sh`, `scripts/tests/bundle-stamp.sh` (3) | S3, D4, D7 | **sí** |
| S5 | rutas privadas (security-reviewer, luego tdd-guide) | según D5: `bundle.sh` y/o `Package.swift`, accessor propio, sus tests (3–5) | S4, D5 | **sí** |

- S1 se puede mergear sola. Hasta que llegue S2, el log dirá `commit=unknown dirty=true`, y
  eso es correcto: sin claves, no se sabe.
- En S2–S4, el test en rojo primero es el caso del harness que corresponde (por ejemplo, el 7
  antes de escribir la regla de dirty).
- En S5, el test en rojo primero es: `strings` del binario del `.app` contiene `$HOME`.

## 13. Criterios de aceptación

1. `plutil -p` del `.app` muestra `CFBundleVersion` de 10 dígitos, `CompanionGitCommit` de 40
   hex y `CompanionGitDirty` booleano. No aparece ninguna otra clave nueva.
2. `bundle.sh` no contiene `rev-list --count`, y el gate de `gates.sh` lo verifica.
3. Un `.swift` sin trackear en `Sources/` produce `CompanionGitDirty = true`.
4. Un archivo sin trackear solo en `docs/` produce `false`.
5. Sin `.git`, el plist dice `unknown` / `true` y el bundle termina.
6. Dos bundles seguidos dan números estrictamente crecientes, o el segundo falla con un mensaje.
7. Después de cada bundle existe `Builds/<UUID>/` con el dSYM de mismo UUID, `build.json`, el
   binario sin stripear (si D3 = sí) y `dirty.patch` si dirty.
8. `dirty.patch` aplica con `git apply --check` sobre el commit de `build.json`.
9. La poda borra carpetas más viejas que el umbral y conserva las de release.
10. `COMPANION_NO_INSTALL=1` deja `/Applications` sin cambios (mismo mtime).
11. El binario del DMG tiene 0 entradas `OSO` y el mismo UUID que su carpeta archivada.
12. `release.sh` rechaza un árbol sucio sin `COMPANION_ALLOW_DIRTY=1`.
13. La primera línea `launched` de la sesión trae los seis campos, y su `uuid` es igual al de
    `dwarfdump --uuid` del ejecutable instalado.
14. `BuildStamp.from(nil)` da `unknown` en todo y dirty `true`, sin crash.
15. (S5) `strings` del binario del `.app` y del DMG da 0 coincidencias de `$HOME` y del nombre
    del worktree.
16. `scripts/gates.sh` queda en verde.

## 14. Chequeo en vivo de Karen

1. Cerrar la app: `osascript -e 'quit app "Companion"'`. Después, `./scripts/bundle.sh release`.
2. Abrir la app. `grep launched ~/Library/Logs/Companion.log | tail -1` tiene que dar el mismo
   UUID que `dwarfdump --uuid /Applications/Companion.app/Contents/MacOS/Companion`.
3. `ls ~/Library/Developer/Companion/Builds/<UUID>/` muestra `companion.dSYM`, `Companion`,
   `build.json` y, si el árbol estaba sucio, `dirty.patch`.
4. Crash deliberado: **no hay disparador solo para debug en el código** (D8). Se usa
   `kill -SEGV $(pgrep -x Companion)`. Si no aparece ningún `.ips` nuevo en
   `~/Library/Logs/DiagnosticReports/`, el paso queda bloqueado y D8 se reabre.
5. En el `.ips` nuevo, `slice_uuid` debe ser igual a la carpeta del paso 3.
6. Simbolicar desde el archivo: `xcrun crashlog <ips>`. Si Spotlight no indexa la carpeta, usar
   `atos -o ~/Library/Developer/Companion/Builds/<UUID>/companion.dSYM/Contents/Resources/DWARF/companion -l <load address> <addresses>`.
   Tiene que dar archivo:línea en al menos un frame de `Companion`.
7. Con `build.json`, hacer `git show <commit>` y aplicar `dirty.patch`. El resultado es el
   código exacto de ese binario.

## 15. Riesgos

- **R1** El timestamp tiene 10 dígitos y supera `Int32.max` (2147483647). Hoy nadie lo parsea
  como entero, pero una herramienta futura que lo haga fallaría. Mitigación: sigue siendo
  válido para Apple (inv. §2.1), y si aparece un consumidor así se revisa D1.
- **R2** Un dirty con falso positivo (un script tocado sin afectar al binario) es ruido
  aceptado a cambio de I2.
- **R3** El archivo crece unos 60 MB por bundle. Con varios bundles al día y 60 días, puede
  llegar a varios GB. Lo cubren la poda y el `HACK:` con su umbral.
- **R4** Spotlight puede no indexar `~/Library/Developer/Companion`. En ese caso `xcrun
  crashlog` no encuentra el dSYM solo, y el camino es `atos` (§4). No bloquea.
- **R5** Que `-file-prefix-map` exista en Swift 6.3 y cubra lo que se espera está sin
  verificar. S5 lo prueba antes de decidir, y D5 puede cambiar.
- **R6** Reemplazar `Bundle.module` (D5 c) puede romper la carga de fuentes, el catálogo de
  localización o las skills si una ruta cambia, o caer en silencio al valor por defecto (las
  fuentes a las del sistema) cuando el proceso no es la app. Por eso va con el localizador de
  orden explícito de D5 y tests de los dos caminos en S5, y con security-reviewer más la
  revisión de código.
- **R7** Si la reorganización de `Sources` se atrasa o cambia rutas otra vez, S1 y el `grep`
  de versión en `bundle.sh` apuntan a un sitio que no existe. Mitigación: S1 no arranca hasta
  que la reorganización esté en main, y el test de identidad existente ya detecta que el
  script se desalineó.
- **R8** `kill -SEGV` puede no producir un `.ips` equivalente a un crash real (D8). En ese caso
  el chequeo en vivo necesita un disparador, y habría que decidir dónde vive sin que llegue a
  release.
