# Wave 6c — Voz configurable y presencia sonora

**Estado: BORRADOR** — pendiente de aprobacion de Karen.

## Objetivo

Devolver a la voz lo que el prototipo dejaba ajustar y lo que la hacia
sentirse viva: criterio de fin de turno, velocidad, volumen, AEC re-armable,
y el sonido de fondo que evita el silencio incomodo mientras piensa.

## Alcance

### Ajustes de voz completos (UI + cableado real)
| Ajuste | Contenido | Referencia |
|---|---|---|
| Criterio de turno | Silencio (con paciencia en ms, 200-1500) vs sentido (semantic VAD con avidez baja/auto/alta). Ya existe en `Config.VoiceSettings.turnDetection` y el codec lo serializa: SOLO falta la UI y la persistencia. | prototipo `SettingsVoice`, ledger Realtime |
| Velocidad y volumen | Sliders con preview; la velocidad SI puede cambiar entre turnos de una sesion viva (la voz no — contrato del ledger): aplicar en caliente via session.update. | ledger Realtime |
| Cancelacion de eco | Toggle que RE-ARMA el veto persistente (`AECVeto`): tocarlo limpia el veto y reintenta VPIO una vez en la proxima sesion, como hacia el prototipo con `aecVetoed`. Con texto honesto de que en algunos equipos no inicializa. | ledger Audio/AEC |
| Tono | Campo de personalidad de la voz (se inyecta en las instrucciones de sesion; el codec ya lo soporta via `tone`). | prototipo `VoiceSettings.tone` |

Todo persiste (patron `UserPreferences`) y llega a `Config` en la proxima
sesion — verificar con grep que cada ajuste alcanza el codec, no solo el
UserDefaults (el patron del repo, doce veces ya).

### Presencia sonora
| Archivo | Contenido | Referencia |
|---|---|---|
| Services `ThinkingSound.swift` (nuevo) | Tono de fondo sintetizado en memoria mientras el estado es thinking: acorde grave suave con envolvente, rampa de entrada y salida, volumen bajo tokenizado. Sin assets. NO suena si hay reduce-motion... no: es audio — toggle propio en Ajustes de voz, on por defecto. Jamas por encima de la voz del agente. | prototipo `Ambience.swift` (síntesis C4+G4+C3, rampas 0.6/0.35 s) |
| Cableado | Arranca al entrar a thinking, para al primer audio del agente o al fallar. Vive del reducer: efecto nuevo `thinkingSoundOn/Off` o observacion del snapshot — decidir en kickoff con el patron mas simple que el reducer ya permita. | prototipo `main.swift set(.thinking)` |

## Tests

Mapeo ajuste→payload de session.update (fixtures del codec, ya hay patron);
re-armado del veto (store en memoria); maquina del sonido de fondo: entra en
thinking, sale con el primer audio o error (con reloj/motor inyectado, sin
AVAudioEngine real). La sintesis en si es prueba manual.

## Definicion de done

Cambiar paciencia y criterio se refleja en la siguiente sesion (visible en
las trazas del log); la velocidad cambia en caliente; el toggle de AEC
re-intenta VPIO una vez; y el silencio de thinking tiene presencia. Veredicto
manual de Karen en su hardware — esta capa nunca la ven los tests.

## Riesgos

- Tocar el arranque de sesion de voz: releer el ledger de audio ANTES (las
  cicatrices de VPIO/HAL estan a un descuido de volver).
- El sonido de fondo comparte salida con el player del agente: no puede
  robar el engine compartido cuando AEC este activo — engine propio efimero.
