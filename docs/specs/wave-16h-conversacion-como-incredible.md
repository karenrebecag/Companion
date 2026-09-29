# Wave 16h — Conversación al nivel de Incredible

**Estado: APROBADO (2026-09-28).** Firmado por delegación de Karen ("firma el resto cuando
finalicemos", al cierre del QA en vivo de 16k). Karen: "la calidad de incredible es excelente". Evidencia: los
transcripts de Companion del 2026-09-25 (`~/Library/Logs/Companion-transcripts.log`) y la sesión de
Incredible de las 17:23–17:25 (`~/.incredible/conversation.json`, solo tiempos y forma de los turnos;
nada de sus prompts).

## 1. Qué hace Incredible (medido) y qué hace Companion (medido)

| | Incredible | Companion |
|---|---|---|
| Acuse | Siempre, en 1,1–2,5 s: "Let me take a look at your screen", "Creating… prueba 1" | En trabajos largos, silencio: 32 s con "búscalo en Safari" |
| Trabajo largo | Un agente en segundo plano; la voz sigue libre; el resultado llega como aviso aparte | El especialista bloquea el turno |
| Lo hablado | Una frase; el detalle en una tarjeta (resultado) o un recibo con palomita | 18 s de restaurantes leídos en voz alta |
| "Listo" | Después de comprobar ("verificado, 0 bytes") | "Escribí … correctamente" sin mirar; falso |
| Contexto del pedido | Cada frase llega marcada con la app y la ventana del momento | Contexto aparte; "esto" y "aquí" fallan |
| Isla | El modelo sabe si una tarjeta se mostró, se cerró o se fue sola; si lo interrumpes, sigue sin repetirse | No lo sabe |
| Pedido compuesto | Hace las dos partes | "Abre Notas y dime qué hay en la primera" → solo abrió |
| Fugas | Ninguna vista | JSON (`{"goal":…}`) y la instrucción interna "El especialista respondió… Acusa en una línea…" dichos en voz alta |
| Texto | — | Frases pegadas sin espacio: "afternoon.Keeping", "pantalla.No contiene" |
| Lugar | — | "Restaurantes cercanos" → Fullerton (EE. UU.); luego Cuernavaca |

## 2. Criterio de done (medible, con los transcripts de hoy como banco de pruebas)

1. **Acuse < 2 s** en todo turno que delegue o use una herramienta de más de 1 s: una frase propia
   de qué va a hacer, antes del trabajo. Medido en `voice timeline` (`commit→audio`).
2. **La voz no espera al trabajo largo.** Lo que va al especialista corre en segundo plano; puedes
   seguir hablando; el resultado llega como un aviso que la voz dice en una frase.
3. **Una frase en voz, el resto en tarjeta.** Respuesta hablada ≤ 2 frases o ≤ 25 palabras cuando
   hay más contenido; el detalle va a una tarjeta en la isla (resultado) o a un recibo (acción hecha).
4. **"Listo" solo con prueba.** Una acción que cambia algo (escribir, crear, abrir, pulsar) se
   comprueba antes de afirmarse (leer el campo, existe el archivo, la app está al frente). Sin prueba,
   la frase dice lo que se intentó, no que salió bien.
5. **Pedidos compuestos completos.** "Haz A y dime B" termina con B; test sobre los 3 casos de hoy.
6. **Cero fugas.** Nada con forma de JSON, de instrucción al modelo o de marca interna llega a la
   voz ni a la isla. Un filtro único en el camino a la voz (no uno por caller), con los textos de hoy
   como casos.
7. **Frases con espacio.** Al unir trozos de respuesta, nunca "palabra.Palabra".
8. **Dónde estás.** Cada pedido lleva la app y la ventana de delante; "cerca" usa tu ubicación
   (ciudad del sistema o la que digas en Ajustes › Tú), nunca la del proveedor de búsqueda.
9. **La isla habla con el modelo.** Tarjeta mostrada, cerrada o ignorada, e interrupciones, entran
   como eventos al siguiente turno.

## 3. TDD (banco de transcripts)

Un archivo `Tests/Fixtures/transcripts-2026-09-25.txt` con los turnos reales de hoy (solo los de
Karen, sin claves). Tests:
- fuga: los 4 textos con JSON o instrucción interna nunca pasan el filtro de voz;
- espacio: "afternoon.Keeping" → "afternoon. Keeping";
- compuesto: el plan de "abre Notas y dime qué hay en la primera nota" tiene dos pasos y el segundo
  es leer;
- "listo": un `type_text` sin lectura posterior no produce una frase de éxito;
- acuse: un turno que delega emite la frase de acuse antes de la delegación (reducer);
- voz corta: una respuesta de 120 palabras con tarjeta se dice en ≤ 25 palabras;
- ubicación: el bloque de contexto lleva la ciudad; la búsqueda de "cerca" la usa.

## 4. Archivos (estimado, dos o tres sesiones)

Core: `SpeechFilter.swift` (nuevo), `EscalationCopy.swift`, `ChatPrompt.swift`, `ContextBlock.swift`,
`SessionMachine.swift` (acuse y aviso de fondo), `Plan.swift`. Services: la ruta a la voz y el
especialista en segundo plano. UI: tarjeta de recibo en la isla. Tests: `ConversationQualityTests`.

## 5. Riesgos

- Delegar en segundo plano cambia el reducer del turno: es la parte más delicada; va en su propia
  sesión con revisión de arquitectura.
- La ubicación necesita permiso de Localización o un dato en Ajustes; sin ninguno, se pregunta.

## 6. Aprobación

Firmada 2026-09-28 por delegación (ver cabecera).
