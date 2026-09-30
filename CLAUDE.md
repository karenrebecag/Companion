# Companion (rebuild)

App nativa macOS de voz. Reconstruccion spec-driven del prototipo de
referencia `../companion` (solo lectura: se consulta, jamas se edita).

## Mapa de documentos

| Doc | Que es | Cuando leerlo |
|---|---|---|
| `docs/ROADMAP.md` | Estado de las waves y foco actual | Al abrir sesion, SIEMPRE primero |
| `docs/PROGRAM.md` | El plan: que entrega cada wave | Al abrir una wave |
| `docs/specs/wave-N-*.md` | Contrato de cada wave (BORRADOR/APROBADO/EN CURSO/CERRADO) | Antes de codear la wave |
| Specs cerrados | Se borran del arbol al cerrar sin pendientes; `git log --diff-filter=D --name-only -- docs/specs` los encuentra | Cuando un comentario cita una spec que ya no esta |
| `docs/ORCHESTRATION.md` | Flujo por wave: fases, agentes, paralelismo, cierre | Antes de despachar agentes |
| `docs/ARCHITECTURE.md` | Patron: capas, puertos, reducer, concurrencia | Antes de disenar cualquier API |
| `docs/REFERENCE.md` | Ledger de cicatrices del original (archivo:linea) | Antes de portar CUALQUIER comportamiento |
| `docs/DECISIONS.md` | ADRs (001: desacople de Hermes) | Antes de agregar dependencias o tools |
| `CHANGELOG.md` | Una entrada por wave cerrada | Al cerrar una wave |

## Reglas de oro

1. **Sin spec APROBADO por Karen no se escribe codigo.** Los BORRADOR se
   refinan en kickoff (planner + architect en paralelo) y se re-aprueban.
2. **Ledger antes de portar**: todo comportamiento del original pasa por
   `docs/REFERENCE.md` y se reescribe al patron de este repo (async/await,
   actors, AsyncStream) — nunca copia literal.
3. **Tests primero** (tdd-guide). Hallazgo de review -> test en rojo que lo
   reproduce, luego el fix. Nunca fix directo.
4. **Gates verdes antes de cerrar cualquier tarea**: `scripts/gates.sh`
   (build, estatico — secretos/prints/try?/tamanos —, arquitectura por
   imports, tests via `swift test`).
5. **Cierre de wave** = changelog + roadmap + spec CERRADO + resumen + stop.
   La siguiente wave no arranca sin OK de Karen.

## Patron (resumen; detalle en ARCHITECTURE.md)

- 4 targets SPM = 4 capas: Core (puro) <- Services (adapters) <- UI
  (MainActor) <- App (composition root). Los imports prohibidos no compilan.
- Puertos y adapters; capacidades opcionales (Claude Code, Hermes, Ollama)
  se DETECTAN en runtime, jamas se asumen. El producto completo funciona con
  solo una API key de OpenAI (ADR 001).
- Reducer para el turno; actors para sesiones; cancelacion estructurada;
  `@Observable` por dominio (nunca un ViewModel-dios).
- Toda lectura del entorno pasa por `Config`; keys en Keychain; cero paths
  a `~/.hermes` ni dotfiles.

## La app instalada

Karen trabaja sobre **el producto**, no sobre un build de desarrollo aparte:
en `/Applications/Companion.app` vive `com.karen.companion` y no hay segunda
copia. Para que vea un cambio:

```bash
./scripts/bundle.sh release     # compila, empaqueta e instala en /Applications
```

Hay que cerrar la app antes (`osascript -e 'quit app "Companion"'`) o el
bundle se reemplaza debajo de la instancia viva. Los tests y los gates
siguen corriendo en debug: son otro directorio de build, no se pisan.

La identidad de desarrollo (`Companion Next`) sigue existiendo en
`ProductIdentity` y en `bundle.sh` — es lo que usaria un contribuyente para
no pisar su propia copia instalada — pero en esta Mac no hay ninguna.

## Entorno de esta Mac

Swift 6.3 con Xcode instalado (xcode-select apunta a Xcode.app): Swift
Testing y notarytool disponibles. Los tests corren con `swift test`.

## Idiomas

Docs publicos (README, ARCHITECTURE) en ingles; docs de trabajo en espanol.
Codigo y comentarios en ingles; comentarios = WHY. Sin emojis.
