# Orquestacion — flujo global por wave

Como se construye cada wave: quien hace que, en que orden, y que debe estar
verde antes de avanzar. Este flujo es el mismo para todas las waves; el
contenido vive en su spec (`docs/specs/wave-N-*.md`).

## Roles

- **Karen** — product owner: aprueba specs, resuelve ambiguedades, cierra waves.
- **Sesion principal (Claude)** — orquestador: refina specs, despacha
  subagentes, integra, corre gates, reporta. No implementa modulos grandes
  directamente si un agente especializado aplica.
- **Subagentes** — trabajo especializado (abajo).

## Ciclo de vida de un spec

`BORRADOR -> APROBADO -> EN CURSO -> CERRADO`

- BORRADOR: lo escribe el orquestador con planner/architect. Nadie codea.
- APROBADO: Karen dio OK explicito. Es el contrato de la wave.
- EN CURSO: construccion. Si el alcance o la API cambian, se vuelve a
  BORRADOR de esa seccion y se re-aprueba; los ajustes menores se anotan en
  el spec bajo "Desviaciones".
- CERRADO: definicion de done cumplida, gates verdes, changelog y roadmap
  actualizados.

## Fases del ciclo (por wave)

### 1. Kickoff — refinar el spec

Al abrir una wave, el spec escrito meses antes se refina contra lo que las
waves anteriores realmente produjeron:

- **planner** — descompone en tareas ordenadas con dependencias.
- **architect** — valida API y fronteras contra `docs/ARCHITECTURE.md` y el
  ledger (`docs/REFERENCE.md`). Corren EN PARALELO.
- El orquestador integra ambos en el spec -> **aprobacion de Karen**.

### 2. Construccion — tests primero

- **tdd-guide** arranca cada modulo: tests en rojo antes del codigo. Cuando
  el original tiene tests equivalentes (`../companion/Tests/Phase*.swift`),
  se portan como caracterizacion: mismos casos, misma semantica.
- Modulos sin dependencias entre si se construyen en paralelo (subagentes
  independientes); los acoplados, en secuencia.
- **Explore** para preguntas puntuales sobre el repo de referencia; nunca
  copiar sin pasar por el ledger.
- **build-error-resolver** solo si el build se rompe y la causa no es obvia.

### 3. Verificacion

- **code-reviewer** + **security-reviewer** EN PARALELO sobre lo escrito.
- Todo hallazgo se corrige via tdd-guide: primero el test que lo reproduce
  en rojo, luego el fix. Nunca fix directo.
- `scripts/gates.sh` verde (build, estatico, arquitectura, tests).

### 4. Cierre

- Entrada en `CHANGELOG.md` (que cambio y por que importa al usuario).
- `docs/ROADMAP.md` actualizado (estado de la wave, siguiente foco).
- Spec marcado CERRADO con fecha; desviaciones documentadas.
- Resumen a Karen y stop. La wave siguiente NO arranca sola.

## Reglas de paralelismo

- Analisis independientes (exploracion, reviews, specs de modulos): siempre
  en paralelo.
- Escritura sobre los mismos archivos: nunca en paralelo.
- La sesion principal mantiene el estado; los subagentes reciben contexto
  explicito (que archivo, que contrato, que seccion del ledger aplica).

## Escalacion de dudas

Ambiguedad de producto (UX, alcance, prioridad) -> pregunta a Karen, una y
concreta. Ambiguedad tecnica con default razonable -> se decide, se anota en
el spec, se sigue.
