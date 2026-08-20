# Decisiones de arquitectura

## ADR 001 — Desacoplar Hermes: absorber capacidades, no el ecosistema

**Fecha:** 2026-08-20 · **Estado:** aceptada (pendiente ratificar en spec Wave 4)

### Contexto

El prototipo original depende de hermes-agent (Python + Node, instalado en
`~/.hermes/hermes-agent`) para cuatro cosas de peso muy distinto:

| Capacidad | Uso real en el original | Peso de la dependencia |
|---|---|---|
| API keys | dotenv `~/.hermes/.env` (`TalkClient.swift:48`, `SettingsStore.swift:146`) | Accidental: solo es un archivo de texto |
| STT fallback | subprocess Python faster-whisper (`Hermes.swift:264`) | Baja: el camino caliente ya es SFSpeechRecognizer del sistema (`Transcribe.swift:6-8`) |
| TTS fallback | subprocess Python `tools.tts_tool` (`Speech.swift:261`) | Baja: el primario ya es OpenAI TTS |
| Ejecutor especialista | `hermes chat -Q` como uno de dos brains (`Hermes.swift:3`, `JobRunner.swift:185-187`) | Alta: la mitad de la delegacion |

hermes-agent es un ecosistema completo (40+ tools, skills auto-mejorables,
gateways Telegram/Discord/etc., multiples backends de terminal). Exigirlo
como requisito mata la adopcion: un usuario nuevo no va a instalar un agente
Python para probar una app de voz.

### Decision

**Ninguna capacidad del producto requiere Hermes.** Se absorbe lo minimo de
su *diseno* (no su codigo: es Python, nosotros Swift) y todo lo demas se
resuelve nativo:

1. **Keys** -> Keychain via `Config` (ya decidido, Wave 2). Muere `~/.hermes/.env`.
2. **STT** -> SFSpeechRecognizer on-device como unico camino local; la
   transcripcion de la sesion Realtime (gpt-4o-mini-transcribe) cubre voz en
   vivo. Evaluar el API SpeechAnalyzer de macOS 26 como upgrade. Cero Python.
3. **TTS** -> OpenAI TTS primario + AVSpeechSynthesizer (nativo, offline,
   gratis) como fallback. Cero Python.
4. **Ejecutor** -> `NativeExecutor` integrado en CompanionServices: loop de
   agente en Swift (chat/completions con tool calling contra CUALQUIER
   endpoint OpenAI-compatible: OpenAI, OpenRouter, Groq, Ollama) con un set
   curado y deliberadamente chico de tools nativas — leer/escribir/editar
   archivo, shell, fetch web, busqueda — todas pasando por el sistema de
   approvals propio. Funciona con la misma API key del chat: valor inmediato
   sin instalar nada.

Claude Code y Hermes quedan como **adapters opcionales del puerto `Executor`,
detectados en runtime** (binario en PATH -> aparece la opcion). La escalera:
`NativeExecutor` (siempre) < Claude Code (si esta) < Hermes (si esta).

### Que se toma de hermes-agent (MIT, con atribucion en NOTICE.md)

- Referencia de schemas/nombres de tools y semantica del loop.
- La cadena de modelos abiertos como *configuracion posible* del
  NativeExecutor (OpenRouter/Ollama), que es el valor real que Hermes
  aportaba a Karen.

### Que NO se toma (explicitamente fuera)

Skills auto-mejorables, gateways de mensajeria, backends de terminal remotos,
plugins, los 40+ tools. Si el NativeExecutor empieza a crecer hacia eso, es
smell de scope: para poder infinito ya existen los adapters opcionales.

### Consecuencias

- Wave 4 se reescribe: su entregable central es el NativeExecutor + puerto
  Executor + approvals; los adapters CLI son la cola de la wave, no el centro.
- El sandbox/approvals es responsabilidad NUESTRA (ya no se hereda de
  `~/.hermes/config.yaml`): politica en Config, confirmacion humana en UI/voz,
  auto-deny con timeout (ver ledger).
- `Brain` deja de ser {fast, hermes, claude} hardcodeado: es una lista de
  ejecutores descubiertos + el nativo.
