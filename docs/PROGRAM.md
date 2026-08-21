# Programa de reconstruccion — waves

Reconstruccion desde cero de Companion con el repo original
(`../companion`) como referencia viva: contratos, tests y cicatrices se
portan; la estructura no. Ver `docs/REFERENCE.md` antes de portar cualquier
comportamiento.

## Metodo por wave

1. **Spec** — planner + architect redactan `docs/specs/wave-N-*.md`
   (objetivo, archivos, API, restricciones, riesgos).
2. **Aprobacion** — Karen aprueba el spec. Sin aprobacion no se escribe codigo.
3. **TDD** — tests primero (tdd-guide); los tests del original son el
   contrato de caracterizacion cuando aplica.
4. **Review** — code-reviewer + security-reviewer sobre lo escrito.
5. **Gates** — `scripts/gates.sh` verde. La app queda usable al cierre de
   cada wave (desde la 2).
6. **Cierre** — resumen de lo hecho, spec marcado como cerrado.

## Waves

- **Wave 0 — Scaffold** (cerrada): paquete SPM 4 targets, Swift Testing,
  gates, este programa.
- **Wave 1 — Core de dominio**: maquina de estados del turno (reducer),
  codecs de protocolo (Realtime, SSE, NDJSON de claude), splitter de frases,
  endpointer, escalation, markdown, modelo de Config. Puro y 100% testeado.
  Spec: `docs/specs/wave-1-core.md`.
- **Wave 2 — Chat vertical**: adapter ChatProvider (OpenAI -> Groq -> Ollama),
  Keychain + onboarding de primera ejecucion (pegar API key), ventana de hilo
  minima. **Hito: app usable solo con una API key.**
- **Wave 3 — Voz**: adapters de audio (mic, player, TTS), transporte Realtime
  WebSocket, barge-in; WebRTC despues. Portar las cicatrices de AEC del
  ledger. Fallbacks 100% nativos: AVSpeechSynthesizer (TTS offline) y
  SFSpeechRecognizer (STT) — cero Python (ADR 001). **Hito: conversacion
  por voz.**
- **Wave 4 — Delegacion**: puerto Executor + **NativeExecutor** integrado
  (loop de agente Swift sobre cualquier endpoint OpenAI-compatible, tools
  nativas minimas, approvals propios) — el especialista funciona sin
  instalar nada (ADR 001). Claude Code y Hermes como adapters opcionales
  detectados en runtime.
- **Wave 5 — Producto**: tokens de diseno y cards, settings, firma +
  notarizacion, updates (Sparkle), docs publicos en ingles, guia de
  contribucion. **Hito: distribuible open source.**

- **Wave 6 — Paridad y craft** (specs 6a/6b/6c): cierra la brecha medida
  contra el prototipo. 6a: menu de aplicacion, adjuntos, avisos y
  actualizaciones (ADR 002). 6b: design systems engineering — la UI es
  central; la simplificacion solo vale donde no haya perdida visual. 6c: voz
  configurable (criterio de turno, velocidad, AEC re-armable) y presencia
  sonora. **Hito: el rebuild iguala o supera al prototipo en uso diario.**

## Reglas transversales

- Todo opcional degrada: sin Claude Code la app esta completa; sin red, la
  UI lo dice con claridad.
- Nada lee el entorno fuera de `Config`.
- Se puede copiar un algoritmo del original solo tras pasar por el ledger y
  reescribirlo al patron de este repo (async/await, sin callbacks guardados).
