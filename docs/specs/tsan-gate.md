# Gate de ThreadSanitizer en CI

Estado: APROBADO (Karen, 2026-09-30, "vamos con tu recomendacion", via orquestador; brief `docs/research/tsan-gate-ci.md` APROBADO).

## Objetivo

Correr la suite completa con `swift test --sanitize=thread` en CI, en un PR
propio. TSan fue el unico oraculo de la carrera del bridge (3 de 500 callbacks
perdidos, sin reproduccion por tiempo), y hoy ninguna corrida de CI lo ejecuta.

## Alcance

Entra:

- Un job `tsan` nuevo en `.github/workflows/ci.yml`, en su propio runner `macos-26`.
- (Si se elige A') `scripts/tsan.sh`, la misma orden que corre el job, para correrla en local.
- Arreglo de la carrera del helper de test `sigpipeCount`
  (`Tests/CompanionTests/BrowserListenerTests.swift:16`).
- Entrada en `CHANGELOG.md` bajo `[Unreleased]` / `### Changed`.

No entra:

- `scripts/gates.sh` y el job `gates`: no cambian (brief 5a, opcion B descartada).
- La carrera de produccion `ClassicRuntime.submit` (:285) contra `speak` (+Mouth:138):
  arreglada aparte en #68.
- `ResourceBundleLocator` y `--scratch-path`: arreglo aparte.
- Supresiones, `--skip`, `.disabled` o `withKnownIssue` para callar avisos.

## Diseno

Job (forma de la seccion 7 del brief):

```yaml
  tsan:
    runs-on: macos-26
    timeout-minutes: 45          # techo hasta medir la primera corrida; luego 2x lo medido
    continue-on-error: true      # solo con la opcion (a); se quita al promover
    steps:
      - uses: actions/checkout@<mismo pin que gates>
      - run: swift --version
      - run: ./scripts/tsan.sh   # o inline, segun decision 4
```

- `.build` por defecto, sin `--scratch-path`: el localizador de recursos solo
  encuentra los textos ahi (555 fallos con scratch path).
- `--no-parallel`: el runner tiene 3 vCPU, igual que `gates`.
- Suite completa, sin filtro: la carrera de `ClassicRuntime` salio de un test
  que ningun filtro de "sospechosos" incluia.
- El gate lee el codigo de salida de `swift test`. Un aviso de TSan mata al
  helper con senal 6 aunque cada test imprima "passed".
- Sin filtro por rutas: un job saltado cuenta como aprobado en un check requerido.
- `scripts/tsan.sh` (A') advierte que no se corre a la vez que `gates.sh` en el
  mismo checkout: con y sin TSan compilan en la misma carpeta de debug.

`sigpipeCount` (si Karen aprueba la decision 5):

```swift
import Synchronization
let sigpipeCount = Atomic<Int>(0)
// handler: add(1, ordering: .relaxed); reset: store(0); lectura: load
```

`Atomic` es lock-free por SE-0410, que es lo que C admite en un handler de
senal. `LockedBox`/`NSLock` no son async-signal-safe; `sig_atomic_t` necesita
`volatile`, que Swift no tiene. El `import Synchronization` queda solo en tests.

## Estado de partida (medido 2026-09-30)

- TSan, `.build` por defecto, en serie: 1529/1529 tests en verde en unos 95 s
  locales, con 3 avisos y salida distinta de 0.
- 1 aviso de produccion (`ClassicRuntime`) y 2 del helper `sigpipeCount`.
- Ninguno de los 5 sospechosos de suite-estable dio aviso.
- Aviso intermitente visto una vez en `AnalyzerTranscriberTests.swift:152`.
  Si reaparece, va a suite-estable, no a supresiones.

El arreglo de `ClassicRuntime` (#68) ya esta en main. Si este PR no deja otros avisos,
el job queda verde desde la primera corrida, pero sigue informativo hasta cumplir N=5.

## Decisiones de Karen (2026-09-30)

1. **(a)**: entra informativo (`continue-on-error: true`). Pasa a requerido cuando
   el arreglo de `ClassicRuntime` (#68, ya mergeado) tenga 5 corridas seguidas sin avisos.
2. N=5. Al promover, `gates` y `tsan` pasan a checks requeridos. `gates` ya lo es desde el
   2026-09-30, con enforce_admins.
3. Cero supresiones para carreras de produccion.
4. **A'**: `scripts/tsan.sh`, invocado por el job.
5. `sigpipeCount` como `Atomic<Int>` en un `let` global; `import Synchronization` solo en tests.
6. `timeout-minutes: 45`, medido en la primera corrida.

## Criterios de aceptacion

- [ ] Test en rojo primero: con TSan y filtro `SigpipeSensitive`, 2 avisos sobre
      `sigpipeCount` antes del cambio y 0 despues.
- [ ] `scripts/gates.sh` en verde y sin cambios en su diff.
- [ ] Primera corrida del job `tsan` en el PR: tiempo por paso y RSS maximo
      (`/usr/bin/time -l`) anotados en el PR. `timeout-minutes` se ajusta a 2x lo medido.
- [ ] Con (a): un aviso de TSan deja el check `tsan` en rojo, pero el workflow sigue verde
      (`continue-on-error`).
- [ ] Sin supresiones ni exclusiones en el diff.
- [ ] CHANGELOG `[Unreleased]` / `### Changed`, en espanol y con fecha.
- [ ] code, security y QA reviewers en APPROVE sobre el diff final. Los veredictos
      van en el cuerpo del PR.
- [ ] El merge espera a Karen, porque cambia los gates de CI.

## Orden

1. Hecho: Karen decidio; el brief esta APROBADO.
2. Hecho: tests-por-modulo PR 1 mergeado (#60).
3. tdd-guide: rojo de `sigpipeCount`, luego el arreglo.
4. Job (y script), CHANGELOG, reviews, PR.
