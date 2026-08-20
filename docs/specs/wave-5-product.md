# Wave 5 — Producto

**Estado: BORRADOR** — se refina en kickoff contra Waves 1-4. De
"funciona en la Mac de Karen" a distribuible open source. Trigger de
deuda: Xcode (notarytool + Swift Testing).

## Objetivo

Una persona sin contexto instala el .dmg, pega su API key y tiene valor
en <5 minutos, sin terminal. Quien clona corre `git clone && swift build
&& scripts/gates.sh` en verde.

## Archivos

### CompanionUI (expande `Tokens.swift` de Wave 2; UN color y UN timing)

| Archivo | Contenido | Contrato |
|---|---|---|
| `Tokens.swift` | Temas claro/oscuro, enfasis elegible | Ledger cards; anti-patron Palette vs Tokens |
| `Motion.swift` | UN sistema de timing | anti-patron Motion vs MotionTime |
| `CardProtocol.swift` | Protocolo comun de card nativa | original ad hoc |
| `MapCard` / `GalleryCard` / `SourcesCard` | Sobre CompanionBlocks + extractSources. JSON invalido -> CodeBlock | Phase 7 |
| `SettingsView.swift` | Perfil, voz con preview, modelos/keys, atajos | Settings* original |
| `ShortcutCodec.swift` | Persistencia y conflicto de atajos | `testShortcutCodec` |
| `VoicePreview.swift` | `/v1/audio/speech`, no Realtime | `VoiceSettings.swift:184` |
| `OnboardingView.swift` | Pulido de vacios y errores | Wave 2 |
| `OrbView.swift` | Mascota. Rive vs SwiftUI puro = ADR | `Orb.swift` |

### Distribucion

- `scripts/make-signing-cert.sh` — identidad "Companion Dev" (TCC).
- `scripts/notarize.sh` — notarytool (requiere Xcode).
- Sparkle o fallback GitHub Releases (primera dep de terceros -> ADR).
- `.github/workflows/ci.yml` — gates en cada PR.
- Migracion harness -> Swift Testing cuando haya Xcode.

### Open source

README / ARCHITECTURE / CONTRIBUTING en ingles. NOTICE.md (Orb, pow,
hermes-agent schemas, Sparkle). LICENSE MIT salvo objecion. Plantillas
de issue/PR.

## Tests

- Portar `testShortcutCodec`, `testTurnNumbering` si no quedo en Wave 1.
- Cards: JSON invalido / lat imposible / http plano -> nil; el View
  degrada.
- Tokens: un solo catalogo; no reintroducir Palette.
- **No** portar `testUpdateCheck` / `testUpdateInstaller` (launchd +
  Desktop). Sparkle los reemplaza.

## Restricciones

- UI nace en espanol; docs publicos en ingles.
- No segunda paleta ni segundo motion.
- Rive no entra sin ADR.
- Firma estable entre builds o TCC revoca mic.
- Gates verdes en maquina ajena.

## Definicion de done

.dmg en Mac limpia: onboarding -> chat o voz en <5 min, sin terminal.
Clone + build + gates verde. Docs publicos en ingles. Changelog +
roadmap. Spec CERRADO. v1.

## Riesgos

- Notarizacion + Apple Developer Program: empezar al abrir la wave.
- Sparkle = primera dep SPM -> ADR; alternativa = GitHub Releases.
- Orb/Rive infla el .dmg.
