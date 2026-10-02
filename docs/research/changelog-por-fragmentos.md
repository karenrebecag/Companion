# Reference Brief: CHANGELOG por fragmentos

Slug: changelog-por-fragmentos | Nivel: standard | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

## 1. Pregunta y decisiones abiertas

Cada merge a main hace conflictar en CHANGELOG.md a todos los PR abiertos, porque todos agregan entrada bajo `[Unreleased]`; cada conflicto fuerza rebase y otra corrida de CI en macOS (unos 10 min). El 2026-10-01 pasó con #71, #72, #74, #78, #80 y #81 [KAREN:chat 2026-10-01].
Decisiones: (1) que mecanismo evita el conflicto sin dependencias nuevas, (2) como se ensambla el CHANGELOG, (3) como el gate exige exactamente un fragmento por PR.

## 2. Estado actual

- CHANGELOG.md tiene una sola sección `[Unreleased]` donde cada PR agrega bullets al tope, con fecha en español dentro del título [repo:CHANGELOG.md:6]
- El encabezado dice que hay una entrada por wave cerrada y que no hay releases versionados hasta Wave 5 [repo:CHANGELOG.md:3]
- La entrada de CHANGELOG es parte del cierre de wave en el proceso [repo:docs/ORCHESTRATION.md:59]
- CI corre el job `gates` en macos-26 con el mismo `scripts/gates.sh` que se corre local [repo:.github/workflows/ci.yml:15]
- El checkout de CI es `actions/checkout@v4` sin `fetch-depth`, es decir un clon superficial sin la base del PR [repo:.github/workflows/ci.yml:17]
- CI corre en `pull_request` y en push a main [repo:.github/workflows/ci.yml:6]
- gates.sh es Bash 3.2 con herramientas del sistema y termina con `exit` según `fails` [repo:scripts/gates.sh:2]
- El gate 2 (estático) ya hace chequeos de texto con grep sobre el repo, el lugar natural para un chequeo barato [repo:scripts/gates.sh:34]
- No hay `.gitattributes` en el repo hoy [repo:.gitignore:1]
Contextos: CI en macos-26 (job gates, evento pull_request y push a main), `scripts/gates.sh` local en el Mac de Karen, worktrees de agentes (`/ship`), merge desde la UI de GitHub o `gh`.

## 3. Fuentes primarias

- towncrier guarda un archivo por cambio con nombre `<id>.<tipo>.<sufijo>` en `newsfragments/`, y los huérfanos llevan prefijo `+` [doc:https://towncrier.readthedocs.io/en/stable/tutorial.html@stable]
- `towncrier build` compila los fragmentos en el changelog y los borra; `--draft` solo previsualiza; es una herramienta Python configurada en pyproject.toml o towncrier.toml [doc:https://towncrier.readthedocs.io/en/stable/tutorial.html@stable]
- changesets guarda `.changeset/<ID_UNICO>.md` con front matter YAML (paquete y bump semver) y el mensaje se escribe al CHANGELOG en el siguiente release [doc:https://github.com/changesets/changesets/blob/main/docs/adding-a-changeset.md@main]
- changesets se invoca con `npx @changesets/cli` o yarn/pnpm, o sea exige Node y un package.json (inferido de la doc, que no lo declara formalmente) [doc:https://github.com/changesets/changesets/blob/main/docs/adding-a-changeset.md@main]
- GitLab genera el changelog desde el asunto de commits con el trailer Git `Changelog`, no desde archivos de fragmento [doc:https://docs.gitlab.com/development/changelog/@current]
- scriv crea fragmentos con `scriv create`, los guarda en un directorio y `scriv collect` los combina por categoría en orden cronológico con encabezado de versión y fecha [doc:https://scriv.readthedocs.io/en/latest/concepts.html@latest]
- El driver `merge=union` hace un merge de 3 vías tomando líneas de ambos lados sin marcadores, y git advierte que deja las líneas agregadas en orden aleatorio [doc:https://git-scm.com/docs/gitattributes@current]
- GitHub no considera los `.gitattributes` definidos por el usuario; soporte de GitHub lo dijo en 2017 y la discusión sigue abierta sin respuesta oficial [doc:https://github.com/orgs/community/discussions/9288@2026]

## 4. Implementaciones de referencia

- towncrier se usa a sí mismo: su directorio de fragmentos tiene un archivo por cambio (`556.bugfix`), mantenido por el equipo Twisted [ref:https://github.com/twisted/towncrier/tree/b8d90be2b1dc3c982b0de95cf02db994ce595c06/src/towncrier/newsfragments@b8d90be2b1dc3c982b0de95cf02db994ce595c06]
- pip (PyPA, escala enorme, PRs concurrentes todo el día) usa `news/<id>.<tipo>.rst` por PR y ensambla en release [ref:https://github.com/pypa/pip/tree/a7002c9771a6c3f0317a4e6b9fbdcd22e643f7b6/news@a7002c9771a6c3f0317a4e6b9fbdcd22e643f7b6]
- changesets se usa a sí mismo con un directorio `.changeset` con config.json [ref:https://github.com/changesets/changesets/tree/c73949ba7b3160a4aa5729223335c190de1528f8/.changeset@c73949ba7b3160a4aa5729223335c190de1528f8]
- Proyectos reportan en issues que el mergeability de GitHub ignora el union driver y el PR sigue CONFLICTING [doc:https://github.com/commandprompt/pgcolumnar/issues/1116@2026]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Fragmentos propios (layout towncrier, ensamblado con shell) | Cero dependencias; archivo nuevo por PR nunca conflictúa; el texto en español con fecha queda tal cual | Hay que escribir un script de ~30 líneas y un chequeo | baja | Recomendada |
| B. towncrier | Maduro, plantillas, categorías | Exige Python en CI y en la máquina; plantillas pensadas para versión+issue | media | No: dependencia nueva |
| C. changesets | Estándar en monorepos JS | Exige Node/package.json y está centrado en bump semver por paquete | media | No: modelo ajeno a SwiftPM |
| D. scriv | Fragmentos Markdown, sin issue obligatorio | Python; `scriv collect` pensado para versiones | media | No: dependencia nueva |
| E. GitLab (trailers de commit) | Sin archivos | Depende de que el trailer sobreviva al squash y de una API de GitLab | media | No: GitHub squash y sin API |
| F. `merge=union` en CHANGELOG.md | Una línea de config | GitHub no lo respeta en el PR, no arregla el problema real; orden aleatorio | baja | No |

## 6. Evidencia en contra

- La razón más fuerte contra A: es un towncrier casero que hay que mantener, y los fragmentos mueven la fecha y el orden del CHANGELOG al momento del release. Se acepta: el script es corto, el formato es el de towncrier y migrar a towncrier después es renombrar archivos [doc:https://towncrier.readthedocs.io/en/stable/tutorial.html@stable]
- Un fragmento por PR no evita el conflicto si dos PR eligen el mismo nombre; se resuelve nombrando el archivo con el slug de la rama o el número de PR, único por construcción [doc:https://towncrier.readthedocs.io/en/stable/tutorial.html@stable]
- El CHANGELOG deja de mostrarse al leer main entre releases; se acepta porque `[Unreleased]` se arma al cerrar wave y los fragmentos son legibles en `changelog.d/` [repo:CHANGELOG.md:3]

## 7. Ejemplares y anti-ejemplos

- Así se ve bien hecho: un archivo por cambio con id y tipo en el nombre, p. ej. `news/12248.bugfix.rst` [ref:https://github.com/pypa/pip/tree/a7002c9771a6c3f0317a4e6b9fbdcd22e643f7b6/news@a7002c9771a6c3f0317a4e6b9fbdcd22e643f7b6]
- Layout propuesto: `changelog.d/<slug-de-rama>.<added|changed|fixed|security>.md`, con el bullet completo en español y su fecha, como hoy [repo:CHANGELOG.md:8]
- Ensamblado: `scripts/changelog-assemble.sh` agrupa por categoría los `changelog.d/*.md`, los inserta bajo `## [Unreleased]` y hace `git rm` de los fragmentos, mismo contrato que `towncrier build` [doc:https://towncrier.readthedocs.io/en/stable/tutorial.html@stable]
- Anti-ejemplo: `merge=union` sobre CHANGELOG.md, que localmente evita el conflicto pero el PR en GitHub sigue CONFLICTING [doc:https://github.com/commandprompt/pgcolumnar/issues/1116@2026]
- Gate propuesto: contar archivos nuevos del PR en `changelog.d/` con `git diff --name-only --diff-filter=A origin/$GITHUB_BASE_REF...HEAD -- changelog.d`; si el conteo != 1, FAIL; omitir si no hay `GITHUB_BASE_REF` (corrida local) [repo:scripts/gates.sh:34]

## 8. Trampas

- El checkout superficial no trae la base del PR, así que el gate necesita `fetch-depth: 0` o un `git fetch origin $GITHUB_BASE_REF` antes de comparar [repo:.github/workflows/ci.yml:17]
- Poner el chequeo dentro de gates.sh lo corre en macos-26 junto con el build; es mejor un job ligero aparte en ubuntu o correrlo primero en gates.sh para fallar rápido [repo:.github/workflows/ci.yml:15]
- Un job de CI aparte con path filter deja el check requerido colgado; no usar filtros [repo:.github/workflows/ci.yml:29]
- gates.sh es Bash 3.2: sin arrays asociativos ni `mapfile`, y `sort`/`sed` BSD [repo:scripts/gates.sh:2]
- Los PR ya abiertos con bullets en CHANGELOG.md siguen conflictuando una última vez; hay que convertirlos a fragmento al rebasar [KAREN:chat 2026-10-01]
- Un `.gitattributes` con `merge=union` no sirve aquí: el servidor de GitHub lo ignora para la mergeabilidad [doc:https://github.com/orgs/community/discussions/9288@2026]
- Excluir del conteo "exactamente uno" los PR que no cambian comportamiento visible (docs, CI) con una regla explícita o un fragmento de categoría vacía; hoy esa excepción no está decidida [repo:docs/ORCHESTRATION.md:59]

## 9. Incertidumbre

- ASSUMPTION: GitHub no aplica `merge=union` en el botón de merge del repo, solo lo vimos en reportes de terceros. prueba: PR de prueba con dos ramas que agregan líneas al final de CHANGELOG.md con la regla activa y ver si queda CONFLICTING
- ASSUMPTION: `git diff --diff-filter=A origin/$GITHUB_BASE_REF...HEAD` funciona en el evento pull_request con `fetch-depth: 0`. prueba: un PR de prueba con el gate en modo solo aviso
- [NEEDS CLARIFICATION: los PR de solo docs o CI, deben llevar fragmento o se exentan con una etiqueta]
- [NEEDS CLARIFICATION: el ensamblado corre al cerrar wave o en `scripts/release.sh`]

## 10. Checklist de estandar

- [ ] Existe `changelog.d/` con un README de una pantalla que dice nombre, categorías y que el bullet lleva fecha
- [ ] Ningún PR toca CHANGELOG.md salvo el de ensamblado
- [ ] `scripts/changelog-assemble.sh` es Bash 3.2, sin dependencias, idempotente y con modo `--dry-run`
- [ ] gates.sh falla si el PR no agrega exactamente un archivo en `changelog.d/` (omitido sin `GITHUB_BASE_REF`)
- [ ] CI trae la base del PR (`fetch-depth: 0` o fetch explícito) antes del chequeo
- [ ] El chequeo corre sin build previo, para fallar en segundos
- [ ] ORCHESTRATION.md y CLAUDE.md dicen "un fragmento" en vez de "entrada en CHANGELOG.md"

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | towncrier tutorial | Twisted/towncrier | stable | 2026-10-01 | high |
| 2 | Adding a changeset | changesets | main (nota: pagina marcada desactualizada) | 2026-10-01 | medium |
| 3 | GitLab changelog entries | GitLab | current | 2026-10-01 | high |
| 4 | scriv concepts | Ned Batchelder | latest | 2026-10-01 | high |
| 5 | gitattributes | git-scm.com | current | 2026-10-01 | high |
| 6 | Discussion 9288 | GitHub community | 2026 | 2026-10-01 | high |
| 7 | news fragments de pip y towncrier | PyPA, Twisted | sha fijados | 2026-10-01 | high |

[KAREN:chat 2026-10-01] Todos los PR llevan fragmento; se ensamblan al cerrar cada wave.

Reutilizado (2026-10-02) por chore/changelog-fragmentos-gate (PR #93, parte B): el Gate 0 que exige exactamente un fragmento por PR es la parte B de este mismo brief. Al rebasarse sobre main, el checkout fijado por SHA de ci-cola-macos (#81) se conserva y se le agrega fetch-depth: 0. No se investigo nada nuevo.
