# Reference Brief: cola de macOS en CI (CodeQL Swift fuera de PRs y cancelar corridas reemplazadas)

Slug: ci-cola-macos | Nivel: quick | Fecha: 2026-10-01 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-01 ESCALATE

Direccion aprobada por Karen, opcion C: (A) CodeQL Swift solo en push a main y semanal, no en PRs; actions y javascript-typescript siguen en PRs. (B) cancelar corridas reemplazadas por PR. [KAREN:chat 2026-10-01 via orquestador]

ESCALAR SIEMPRE: el cambio toca `.github/workflows/` y la configuracion de code scanning del repo. Este brief solo especifica; no edita `.github/`.

## 1. Pregunta y decisiones abiertas

Cambio: bajar la cola de los jobs macOS de karenrebecag/Companion (repo publico) sin perder el analisis Swift en main ni las corridas de main que cuenta el gate de TSan.

Decisiones:

1. Si default setup puede limitar Swift a eventos que no sean PR; si no, la forma del `codeql.yml` de advanced setup (eventos, `build-mode`, runner, permisos) y el orden de la migracion.
2. El bloque `concurrency` de `ci.yml`: cancelar solo en `pull_request`, nunca en main.
3. Si quitar Swift de los PRs pierde algun check requerido.
4. Efecto esperado en minutos macOS y en la cola.
5. Pinear actions por SHA o por tag, de forma consistente en los dos archivos.

Respuesta corta:

1. No. Default setup corre en push, PR y semanal sin opcion de elegir eventos ni por lenguaje; hace falta advanced setup y desactivar default setup antes, porque si no la subida se rechaza.
2. Grupo `workflow + (numero de PR || run_id)` con `cancel-in-progress` igual a `github.event_name == 'pull_request'`. En main cada corrida tiene su propio grupo: no se cancela ni se reemplaza.
3. No. El unico check requerido en main es `gates`, y no hay rulesets.
4. En la ventana medida, Swift CodeQL ocupo el 86 % de los minutos macOS y la parte de PRs el 49 %. Sacarla de PRs libera unos 975 de 1974 min.
5. Por SHA en los dos archivos, a las versiones que se usan hoy (sin subir de major).

## 2. Estado actual

- `ci.yml` corre en push a main y en todo `pull_request`, sin bloque `concurrency` [repo:.github/workflows/ci.yml:3]
- El job `gates` corre en `macos-26` [repo:.github/workflows/ci.yml:15]
- El job `tsan` corre en `macos-26` [repo:.github/workflows/ci.yml:30]
- `tsan` es informativo con `continue-on-error: true` [repo:.github/workflows/ci.yml:32]
- `ci.yml` usa `actions/checkout@v4` por tag, en los dos jobs [repo:.github/workflows/ci.yml:17]
- El segundo `checkout@v4`, en el job `tsan` [repo:.github/workflows/ci.yml:34]
- `tsan` pasa a requerido tras 5 corridas seguidas sin avisos; al promover, `gates` y `tsan` seran checks requeridos [repo:docs/specs/tsan-gate.md:82]
- Default setup esta `configured` con actions, javascript-typescript y swift, `schedule: weekly`, `runner_type: standard` [repo:docs/research/evidence/codeql-runs-2026-10-01.txt:41]
- CodeQL existe solo como workflow dinamico de default setup; no hay `codeql.yml` en el repo [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:13]
- El job `Analyze (swift)` de default setup pide `macos-latest`, que hoy resuelve a la imagen `macos-26-arm64` [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:16]
- Default setup usa `build-mode: autobuild` para Swift, con codeql-action 4.38.2 y CodeQL 2.27.1 [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:17]
- El autobuild compila con Xcode 26.6 [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:18]
- En los jobs Swift que fallaron, el paso Autobuild no termino en success; el log ya no esta disponible [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:20]
- Branch protection de main: el unico check requerido es `gates`, con enforce_admins [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:4]
- El repo no tiene rulesets, asi que tampoco hay regla de merge protection por code scanning [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:9]
- Swift CodeQL en PR: 17 jobs, 975 min en total, 9 fallidos y 2 cancelados [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:26]
- Swift CodeQL en push a main: 12 jobs, 725 min en total, 7 fallidos [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:27]
- `gates` sumo 260 min en 31 jobs, con hasta 58 min de espera en cola [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:24]
- Total macOS en la ventana: 1974 min; Swift CodeQL es el 86 % y la parte de PRs el 49 % [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:29]
- Hubo runs CodeQL de commits ya reemplazados que corrieron hasta cancelarse, por ejemplo PR #72 [repo:docs/research/evidence/codeql-runs-2026-10-01.txt:9]
- Otro run reemplazado, en PR #70 [repo:docs/research/evidence/codeql-runs-2026-10-01.txt:11]
- La cuenta duena es de plan Pro [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:39]
- El repo tiene 12 archivos JS/TS, 11 de ellos en `Extensions/browser/`, que es lo que cubre javascript-typescript [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:41]
Contextos: CI en GitHub Actions (eventos pull_request, push a main, schedule semanal, workflow_dispatch), configuracion de code scanning del repo (default o advanced), branch protection de main.

## 3. Fuentes primarias

- Default setup escanea en cada push a la rama por defecto o protegida, en PRs contra ellas (sin forks) y en un horario semanal [doc:https://docs.github.com/en/code-security/concepts/code-scanning/setup-types@fpt-2026-10-01]
- Si las opciones de default setup no alcanzan, la guia es pasar a advanced setup, por ejemplo para cambiar el horario del analisis [doc:https://docs.github.com/en/code-security/concepts/code-scanning/setup-types@fpt-2026-10-01]
- Lo que default setup deja personalizar son los lenguajes y la query suite; no menciona eventos ni disparadores [doc:https://docs.github.com/en/code-security/code-scanning/enabling-code-scanning/configuring-default-setup-for-code-scanning@fpt-2026-10-01]
- Default setup usa `none` para C/C++, C#, Java y Rust, y `autobuild` para el resto de los lenguajes compilados, Swift incluido [doc:https://docs.github.com/en/code-security/code-scanning/enabling-code-scanning/configuring-default-setup-for-code-scanning@fpt-2026-10-01]
- Swift admite los build modes `autobuild` y `manual`; no admite `none` [doc:https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages@fpt-2026-10-01]
- El analisis de Swift corre en macOS por defecto, y tanto `xcodebuild` como `swift build` sirven como build [doc:https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages@fpt-2026-10-01]
- Con default setup activo, una subida de resultados CodeQL se rechaza con "Upload with CodeQL results rejected due to 'default setup'"; la salida es desactivar CodeQL default setup [doc:https://docs.github.com/en/code-security/code-scanning/troubleshooting-sarif-uploads/default-setup-enabled@fpt-2026-10-01]
- Para pasar de default a advanced desde la UI: "Switch to advanced" y luego "Disable CodeQL" [doc:https://docs.github.com/en/code-security/code-scanning/creating-an-advanced-setup-for-code-scanning/configuring-advanced-setup-for-code-scanning@fpt-2026-10-01]
- Por API: `PATCH /repos/{owner}/{repo}/code-scanning/default-setup` con `state` igual a `not-configured`; responde 200 o 202 [doc:https://docs.github.com/en/rest/code-scanning/code-scanning#update-a-code-scanning-default-setup-configuration@fpt-2026-10-01]
- Por defecto, un job pendiente en el mismo grupo de concurrencia se cancela y lo reemplaza el nuevo; `cancel-in-progress: true` cancela ademas el que esta corriendo [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@fpt-2026-10-01]
- `cancel-in-progress` acepta una expresion; `concurrency` solo puede usar los contextos github, inputs y vars [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@fpt-2026-10-01]
- El patron documentado de respaldo es `github.head_ref || github.run_id`: run_id es unico y siempre esta definido [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@fpt-2026-10-01]
- En el `if` a nivel de job solo estan disponibles github, needs, vars e inputs; `matrix` no [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/contexts@fpt-2026-10-01]
- `github.head_ref` solo existe en pull_request y pull_request_target [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/contexts@fpt-2026-10-01]
- Si se declara un permiso, todos los que no se declaran quedan en `none`; se puede declarar por job [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@fpt-2026-10-01]
- Los workflows programados corren sobre el ultimo commit de la rama por defecto, pueden retrasarse con carga alta y se desactivan en repos publicos tras 60 dias sin actividad [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows@fpt-2026-10-01]
- Planes Free y Pro: maximo 5 jobs macOS concurrentes en runners hospedados por GitHub [doc:https://docs.github.com/en/actions/reference/limits@fpt-2026-10-01]
- Actions es gratis en repos publicos con runners estandar: el limite real es la concurrencia, no el costo [doc:https://docs.github.com/en/billing/concepts/product-billing/github-actions@fpt-2026-10-01]
- Pinear a un SHA completo es la unica forma de usar una action como release inmutable; con tag hay que confiar en el autor [doc:https://docs.github.com/en/actions/reference/security/secure-use@fpt-2026-10-01]
- Dependabot no crea alertas para actions pineadas a SHA, solo para las que usan versionado semantico [doc:https://docs.github.com/en/actions/reference/security/secure-use@fpt-2026-10-01]

## 4. Implementaciones de referencia

- El starter workflow oficial de CodeQL de GitHub: matrix por lenguaje, `security-events: write` "required for all workflows", Swift en macOS y category `/language:` por lenguaje. Es referencia porque lo publica GitHub y es el que genera "Switch to advanced" [ref:https://github.com/actions/starter-workflows/blob/fbc8bd851e74a7296904aa1a44ac0edded32deaf/code-scanning/codeql.yml@fbc8bd851e74a7296904aa1a44ac0edded32deaf]
- En ese starter, el runner sale de la matrix (`macos-latest` si es swift); es posible porque `runs-on` si ve `matrix`, cosa que el `if` de job no hace [ref:https://github.com/actions/starter-workflows/blob/fbc8bd851e74a7296904aa1a44ac0edded32deaf/code-scanning/codeql.yml@fbc8bd851e74a7296904aa1a44ac0edded32deaf]
- El starter declara `actions: read` y `contents: read`, con la nota de que solo hacen falta en repos privados; con permisos explicitos, `contents: read` sigue haciendo falta para checkout [ref:https://github.com/actions/starter-workflows/blob/fbc8bd851e74a7296904aa1a44ac0edded32deaf/code-scanning/codeql.yml@fbc8bd851e74a7296904aa1a44ac0edded32deaf]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| Quedarse en default setup y quitar swift de sus lenguajes | Sin workflow que mantener | Se pierde Swift tambien en main y semanal; no cumple (A) | baja | No |
| Advanced: un `codeql.yml`, job matrix (actions, js-ts) en PR y main, job `analyze-swift` aparte con `if: github.event_name != 'pull_request'` | Cumple (A); se lee facil; el `if` usa solo `github` | Dos jobs casi iguales | baja | Si |
| Advanced: una sola matrix con lista de lenguajes calculada con `fromJSON` segun el evento | Un solo job | Expresion opaca y `runs-on` condicional; mas facil de romper | media | No |
| Advanced: archivo aparte `codeql-swift.yml` solo con push y schedule | En PRs ni aparece el job saltado | Dos workflows con el mismo `name` de categoria; mas superficie | baja | Aceptable |
| `ci.yml` con grupo por `github.ref` | Simple | En main, una corrida pendiente se reemplaza por la nueva aunque `cancel-in-progress` sea false; se pierden corridas de main que cuenta TSan | baja | No |
| `ci.yml` con grupo `workflow + (numero de PR o run_id)` y `cancel-in-progress` igual a ser PR | Cancela lo reemplazado en PR; en main cada corrida es su propio grupo | Ninguno relevante | baja | Si |

Propuesta para la spec. Archivo nuevo `.github/workflows/codeql.yml`:

```yaml
name: CodeQL

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    # Weekly Swift pass even without merges; default setup ran weekly too.
    - cron: '23 7 * * 1'
  workflow_dispatch:

# PR: a new commit cancels the superseded analysis. Push, schedule and manual
# runs fall back to run_id, so they never share a group and are never
# cancelled or replaced.
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

permissions:
  contents: read

jobs:
  analyze:
    name: Analyze (${{ matrix.language }})
    runs-on: ubuntu-latest
    permissions:
      security-events: write
      contents: read
      actions: read
    strategy:
      fail-fast: false
      matrix:
        include:
          - language: actions
            build-mode: none
          - language: javascript-typescript
            build-mode: none
    steps:
      - name: Checkout repository
        uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
      - name: Initialize CodeQL
        uses: github/codeql-action/init@2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2 # v4.38.2
        with:
          languages: ${{ matrix.language }}
          build-mode: ${{ matrix.build-mode }}
      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2 # v4.38.2
        with:
          category: "/language:${{ matrix.language }}"

  analyze-swift:
    # Swift needs a macOS runner and took 14-112 min per run; on PRs it held
    # most of the 5 macOS slots and starved gates. It runs on main, weekly and
    # on demand only. matrix is not readable in a job-level if, hence its own job.
    name: Analyze (swift)
    if: github.event_name != 'pull_request'
    # Same image as ci.yml: Package.swift needs Swift 6.2+.
    runs-on: macos-26
    timeout-minutes: 120
    permissions:
      security-events: write
      contents: read
      actions: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
      - name: Initialize CodeQL
        uses: github/codeql-action/init@2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2 # v4.38.2
        with:
          languages: swift
          # Same mode default setup used, so results stay comparable.
          build-mode: autobuild
      - name: Perform CodeQL Analysis
        uses: github/codeql-action/analyze@2892aa5e19bbd11bc0cff5427e3b750a04d9e3c2 # v4.38.2
        with:
          category: "/language:swift"
```

Cambio en `.github/workflows/ci.yml`: agregar entre `on:` y `jobs:`, y pinear los dos checkout.

```yaml
# PR: a new commit cancels the superseded run. Push to main falls back to
# run_id, so main runs never share a group and are never cancelled or
# replaced: tsan counts clean main runs before it becomes required
# (docs/specs/tsan-gate.md).
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

```yaml
      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
```

Orden de la migracion, que hace Karen o el orquestador con su aprobacion, no un agente de research:

1. Abrir el PR con los dos archivos.
2. Desactivar default setup: `gh api -X PATCH repos/karenrebecag/Companion/code-scanning/default-setup -f state=not-configured`, o Settings, Advanced Security, CodeQL analysis, Disable CodeQL.
3. Volver a correr los checks del PR: `Analyze (actions)` y `Analyze (javascript-typescript)` deben subir sin rechazo.
4. Tras el merge, el push a main corre `Analyze (swift)`; se puede verificar antes con workflow_dispatch desde la rama.

## 6. Evidencia en contra

- La razon mas fuerte en contra: un PR que mete una vulnerabilidad en Swift ya no recibe la alerta en el PR, sino hasta el push a main. Se acepta porque Karen eligio (A), y porque CodeQL no es check requerido, asi que tampoco bloqueaba merges [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:6]
- Ademas, 9 de los 17 analisis Swift en PR fallaron: la senal en PR ya era poco fiable [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:26]
- Segunda objecion: advanced setup es un workflow mas que mantener y que actualizar. Se acepta: el starter oficial es corto y el diff es de unas 70 lineas [ref:https://github.com/actions/starter-workflows/blob/fbc8bd851e74a7296904aa1a44ac0edded32deaf/code-scanning/codeql.yml@fbc8bd851e74a7296904aa1a44ac0edded32deaf]
- Tercera: pinear por SHA corta las alertas de Dependabot para esas actions. Se acepta porque son actions de GitHub y el repo no tiene `dependabot.yml`; si se agrega, vale la pena revisarlo [doc:https://docs.github.com/en/actions/reference/security/secure-use@fpt-2026-10-01]

## 7. Ejemplares y anti-ejemplos

- Bien: el grupo cae en `run_id` fuera de PR, que es unico y siempre esta definido; es el mismo patron de respaldo que documenta GitHub [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@fpt-2026-10-01]
- Anti-ejemplo: `group: ${{ github.ref }}` sin cancel en main. Las corridas pendientes de main se reemplazan igual, porque eso es lo que hace concurrency por defecto [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@fpt-2026-10-01]
- Anti-ejemplo: `if: matrix.language != 'swift' || github.event_name != 'pull_request'` a nivel de job. `matrix` no esta en ese contexto y el workflow no hace lo esperado [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/contexts@fpt-2026-10-01]

## 8. Trampas

- Mergear `codeql.yml` con default setup activo hace que cada subida falle con "rejected due to 'default setup'" [doc:https://docs.github.com/en/code-security/code-scanning/troubleshooting-sarif-uploads/default-setup-enabled@fpt-2026-10-01]
- Desactivar default setup antes del merge deja una ventana sin CodeQL hasta que el workflow corra en main; conviene hacerlo justo antes de re-correr el PR [doc:https://docs.github.com/en/rest/code-scanning/code-scanning#update-a-code-scanning-default-setup-configuration@fpt-2026-10-01]
- Declarar `permissions` sin `contents: read` deja el checkout sin acceso, porque lo no declarado queda en none [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax@fpt-2026-10-01]
- `macos-latest` puede moverse a otra imagen; `macos-26` fija el Swift 6.2+ que pide `Package.swift`, igual que `ci.yml` [repo:.github/workflows/ci.yml:12]
- El schedule corre sobre el ultimo commit de main y se desactiva tras 60 dias sin actividad en un repo publico [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows@fpt-2026-10-01]
- Contexto pull_request: `ci.yml` cancela la corrida anterior del mismo PR, `gates` sigue siendo el check requerido y se evalua sobre el commit nuevo [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:4]
- Contexto push a main: grupo por run_id, nunca se cancela ni se reemplaza; las corridas de `tsan` en main siguen contando para N=5 [repo:docs/specs/tsan-gate.md:82]
- Contexto schedule y workflow_dispatch: solo existen en `codeql.yml`, caen en run_id y corren Swift [doc:https://docs.github.com/en/actions/reference/workflows-and-actions/contexts@fpt-2026-10-01]
- Contexto branch protection: no cambia nada; CodeQL nunca fue requerido [repo:docs/research/evidence/ci-cola-macos-mediciones-2026-10-01.txt:4]

## 9. Incertidumbre

- ASSUMPTION: la cola baja de forma notable al liberar unos 975 de 1974 min macOS (49 %). Un PR pasa de ocupar 3 slots (gates, tsan y Swift de 14 a 82 min) a 2 slots de unos 7 a 11 min. Lo que no se puede predecir es la contencion que dejan los merges seguidos a main, cada uno con un Swift de 14 a 112 min. prueba: con 3 o mas PRs abiertos tras el merge, medir `started_at - created_at` de `gates` con gh api y comparar contra el maximo de 58 min.
- ASSUMPTION: la causa de los fallos del autobuild Swift (16 de 29) no se conoce y el cambio no la arregla; sigue fallando en main. prueba: correr `analyze-swift` por workflow_dispatch y leer el log completo del paso Autobuild mientras exista.
- ASSUMPTION: con advanced setup, los PRs pueden mostrar "1 configuration present on refs/heads/main was not found" por la categoria `/language:swift`, que existe en main y no en el PR. La fuente es una discusion de la comunidad, no docs oficiales; no bloquea porque CodeQL no es requerido. prueba: mirar el check "CodeQL" en el primer PR despues de la migracion.
- ASSUMPTION: las alertas abiertas de default setup siguen ligadas a la misma categoria `/language:swift` y no se duplican al pasar a advanced. prueba: comparar el conteo de alertas abiertas por herramienta antes y despues, con `gh api repos/karenrebecag/Companion/code-scanning/alerts`.
- ASSUMPTION: `timeout-minutes: 120` alcanza para un analisis Swift exitoso; el maximo exitoso medido fue 54 min y el maximo fallido 112. prueba: revisar la duracion de las primeras 3 corridas en main.
- [NEEDS CLARIFICATION: las 5 corridas limpias de tsan, ¿cuentan solo en main o tambien en PRs? Si cuentan en PRs, una corrida de PR cancelada no deberia romper la racha. La spec de tsan-gate dice "5 corridas seguidas" sin decir la rama.]
- [NEEDS CLARIFICATION: ¿se agrega tambien un grupo fijo para `analyze-swift` en main (1 corriendo y 1 pendiente, analizando siempre el ultimo commit)? Bajaria mas la cola cuando hay merges seguidos, pero se saltaria commits intermedios de main. Queda fuera de la opcion C aprobada.]
- [NEEDS CLARIFICATION: ¿el pin por SHA de `ci.yml` va en este mismo PR o en uno aparte? El brief recomienda que vaya en este, por consistencia.]

## 10. Checklist de estandar

- [ ] Existe `.github/workflows/codeql.yml` con push a main, pull_request a main, schedule semanal y workflow_dispatch.
- [ ] `Analyze (swift)` no corre en `pull_request`: el job aparece como skipped en el PR y corre en el push a main.
- [ ] `Analyze (actions)` y `Analyze (javascript-typescript)` corren en el PR y suben sin el error "rejected due to 'default setup'".
- [ ] `gh api repos/karenrebecag/Companion/code-scanning/default-setup` devuelve `state: not-configured` antes del merge.
- [ ] Swift usa `build-mode: autobuild` en `macos-26`, con `security-events: write` y `contents: read` declarados por job.
- [ ] `ci.yml` tiene el bloque `concurrency` propuesto. Un segundo push al mismo PR cancela la corrida anterior, mientras que dos pushes seguidos a main corren los dos completos.
- [ ] Branch protection sin cambios: `required_status_checks.contexts` sigue siendo `["gates"]`.
- [ ] Todas las `uses:` de los dos workflows estan pineadas a SHA completo con la version en comentario, sin subir de major.
- [ ] CHANGELOG [Unreleased] con la entrada en espanol y la fecha.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | About setup types for code scanning | GitHub Docs | fpt | 2026-10-01 | high |
| 2 | Configuring default setup for code scanning | GitHub Docs | fpt | 2026-10-01 | high |
| 3 | Configuring advanced setup for code scanning | GitHub Docs | fpt | 2026-10-01 | high |
| 4 | Upload was rejected because CodeQL default setup is enabled | GitHub Docs | fpt | 2026-10-01 | high |
| 5 | CodeQL build options and steps for compiled languages | GitHub Docs | fpt | 2026-10-01 | high |
| 6 | REST code scanning: default setup | GitHub Docs | fpt | 2026-10-01 | high |
| 7 | Workflow syntax (concurrency, permissions) | GitHub Docs | fpt | 2026-10-01 | high |
| 8 | Contexts reference (context availability) | GitHub Docs | fpt | 2026-10-01 | high |
| 9 | Events that trigger workflows (schedule) | GitHub Docs | fpt | 2026-10-01 | high |
| 10 | Actions limits | GitHub Docs | fpt | 2026-10-01 | high |
| 11 | GitHub Actions billing | GitHub Docs | fpt | 2026-10-01 | high |
| 12 | Secure use reference | GitHub Docs | fpt | 2026-10-01 | high |
| 13 | actions/starter-workflows code-scanning/codeql.yml | GitHub | fbc8bd8 | 2026-10-01 | high |
| 14 | Mediciones gh api del repo | este run | 2026-10-01 | 2026-10-01 | high |
| 15 | community discussion 153284, configuration not found | GitHub Community | 2026 | 2026-10-01 | low |
