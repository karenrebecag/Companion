# Wave 13a — Ver la pantalla de verdad

**Estado: APROBADA / EN CURSO (2026-09-06).** Karen: "vamos". Sin commit.

Cierra el hueco que 10a dejó fuera (`screen-text` / OCR / Screen Recording) y
el “Explicitly deferred” del README: **visión para percibir**, no para
clicar UI ajena. El método sale de traces de debug de Incredible en esta
Mac (2026-09-04), no de su código.

---

## 1. Cómo lo hace Incredible (medido, no copiado)

Al pulsar FN, **en el mismo milisegundo** que abre el micro:

1. `[screen-context/activation] scheduled`
2. `[mic/start]`
3. `screen-text/macos` cosecha el árbol AX de la ventana al frente
   (**378–442 ms**, ~155 caracteres)
4. Un JPEG de **86–157 KB** va a un modelo barato de visión
   (Gemini 3.5 Flash Lite). Tarda **1–9 s**, pero **en paralelo a que
   hablas**. Cuando sueltas, el resumen ya está.
5. El orquestador de voz recibe `screenshot=(none)`: **nunca el JPEG**.
   Recibe un bloque de texto: SUMMARY (≤50 palabras) + SNIPPETS (hasta 12
   fragmentos verbatim, ≤10 palabras, para buscar).

Por eso es rápido: la captura no espera al speech; el cerebro de voz no
traga una imagen de retina.

Permisos: Screen Recording **concedida** + Accessibility. Captura solo al
activar, no siempre-on.

---

## 2. El defecto nuestro

Companion lee nombre de app y títulos AX (10a), con tope de 150 ms, y
tira el canal si llega tarde. Next tiene Accesibilidad denegada → `[]`.
Cero píxeles. `RealtimeCodec.imageItem` existe (6c) y **no se usa**; y no
debería usarse para esto: meter el JPEG en realtime es lo lento.

---

## 3. Decisión

Misma forma, nuestro stack (OpenAI que ya tenemos, ScreenCaptureKit que
el Mac 14+ ya tiene).

### 3.1 Al pulsar FN (`.begin` / hold), en paralelo al micro

| Canal | Qué | Tope |
|---|---|---|
| Capture | `SCScreenshotManager` del display principal, **sin** las ventanas de Companion (island, main) | ~50–80 ms |
| Encode | JPEG calidad 0.7, lado largo ≤1280. Objetivo ~80–160 KB | — |
| AX | el `OpenDocumentsSensor` de siempre | 150 ms (ya existe) |
| Vision | `gpt-4o-mini` con imagen + nombre de app al frente | arranca ya; no bloquea el micro |

Si el tap se cancela (FN corta), se tira el JPEG y se cancela la visión.

### 3.2 Al soltar / commit

Esperar la visión **hasta 2.0 s más**. Si no llegó: el turno lleva AX y
`<screen_summary pending="true"/>`. Nunca se retrasa el speech por una
visión de 9 s.

### 3.3 Qué ve el modelo de voz

Texto en `<context>`, DATA, escapado, como 10a:

```
<screen_summary>…</screen_summary>
<screen_snippets>
  - [Safari] "…"
</screen_snippets>
```

Caps: summary 400, 12 snippets × 80. Compact del historial: `pantalla`,
nunca el JPEG ni los snippets. El JPEG no se persiste.

Prompt de visión: **nuestro**, no el de ellos. Contrato de salida:

- SUMMARY: qué hay y en qué parece el foco. Solo lo legible. Sin adivinar.
- SNIPPETS: hasta 12 fragmentos verbatim cortos, etiquetados con la app.

### 3.4 Permiso

- `NSScreenCaptureUsageDescription` en `bundle.sh` (sin esto TCC no pregunta).
- `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`.
- Fila en Ajustes › App › CONTEXTO. Toggle “Lo que se ve” (canal
  `ContextChannels.screen`, **on por defecto** cuando hay grant).
- Sin grant: canal vacío, el hold funciona igual.

### 3.5 Fuera

- Enviar el JPEG al realtime (`imageItem`).
- Grabar la pantalla en continuo.
- Clic/type por visión (sigue diferido).
- Un segundo proveedor de visión (Gemini, etc.).
- Copiar el instruction de Incredible.
- OCR local (Vision.framework) en v1: el sidecar LLM cubre; OCR es 13b si
  la visión falla o es cara.

---

## 4. Archivos (primera entrega)

| Archivo | Qué |
|---|---|
| `TurnContext.swift` / `ContextBlock.swift` | `screenSummary`, `screenSnippets`, canal `.screen`, render + compact |
| `ScreenCapture.swift` (Services, nuevo) | ScreenCaptureKit → JPEG; vacío sin permiso |
| `ScreenVision.swift` (Services, nuevo) | chat OpenAI con imagen; parsea SUMMARY/SNIPPETS; cancela |
| `VoiceSession.swift` | hold: captura+visión en paralelo; commit espera ≤2 s |
| `ContextSettings.swift` + `PermissionRow` + strings | toggle + fila Screen Recording |
| `bundle.sh` | `NSScreenCaptureUsageDescription` |
| Tests | bloque, permiso denegado, parser, compact no guarda JPEG |

`ChatViewModel` typed: misma captura al enviar (opcional v1: solo voz; el
typed puede ir en 13a.1). **v1 = voz / hold.** Typed se anota y se
re-aprueba.

---

## 5. TDD

| # | Test | Espera |
|---|---|---|
| 1 | `ContextBlock.render` con summary+snippets | tags escapados, tope de caps |
| 2 | `compact` con pantalla | dice `pantalla` / `screen`, sin el texto largo |
| 3 | parser de visión: SUMMARY + SNIPPETS bien formados | struct |
| 4 | parser: basura / vacío | `nil`, no crash |
| 5 | capture `trusted == false` | `nil` Data, no pide el permiso |
| 6 | canal `.screen` off | no llama captura ni visión |
| 7 | cancelar la Task de visión | no escribe en el turno |

---

## 6. Seguridad

- JPEG solo en memoria, se suelta al terminar el turno o al cancelar.
- Contenido de pantalla = input no confiable (mismo marco DATA que 10a).
- Nunca abrir URL/archivo que **solo** aparezca en snippets (ya está en
  `actRule`).
- Log: bytes y ms, nunca el JPEG ni los snippets.
- Screen Recording es opt-in de TCC; el toggle puede apagarse.

---

## 7. Done

Hold FN delante de Safari: el modelo puede citar un titular **visible**.
Sin Screen Recording: el hold sigue, el bloque no lleva `<screen_summary>`.
El realtime no recibe `input_image`. Comparar con Incredible en el mismo
gesto, no copiar su prompt.
