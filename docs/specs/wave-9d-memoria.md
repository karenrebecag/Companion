# Wave 9d — Lo que se ve y lo que se recuerda

**Estado: CERRADA (2026-08-24).** Entregada completa: `ConversationMemory`
(Core, pura), `Recall` en `ChatMessage`, el intercambio de tool en `runJob`, y
el guardia de huerfanos en la ventana. 188 tests, gates verdes tres corridas.

**Hallazgo durante la implementacion, no previsto en la spec:** al convertir
el resultado en una pareja llamada/respuesta aparecio un riesgo nuevo — la
ventana de historial puede cortar ENTRE las dos, y un turno `.tool` sin su
llamada no es inofensivo: el proveedor rechaza la peticion entera, asi que el
turno siguiente a una conversacion larga fallaria en seco. Cubierto con
`dropOrphanedToolTurns` y sus dos tests.

**Estado original: APROBADO (2026-08-24).** Sale de una queja de uso — "la app se
siente estupida y el prototipo resolvia" — que resulto tener una causa
concreta y medible, no una sensacion.

---

## 1. El defecto, en una linea

`messages` es a la vez el hilo que Karen lee y la memoria del modelo de
charla, y esos dos tienen requisitos opuestos.

`ChatViewModelJobs.runJob` mete el informe COMPLETO del especialista como
`role: .assistant`, y `windowedTurns()` manda `messages` tal cual al proveedor.

### Lo que eso provoca, medido

En la conversacion real del 2026-08-24: 36 mensajes con rol, 3.962 caracteres
de historial, y **un solo informe ocupa 942 — el 23%**. Con tres o cuatro
busquedas, el historial es casi todo informes viejos.

Tres consecuencias, y las tres se ven en las capturas:

1. **El modelo se cree autor del informe.** Entra como `assistant`. Su prompt
   pide "2 a 4 frases, charla, no un informe" y su propio historial le muestra
   que acaba de emitir un reporte con tabla. Gana el ejemplo. De ahi salen
   los cierres tipo "Listo, ya termine de buscar".
2. **Se come el contexto.** `historyWindow` son 20 turnos en los dos
   productos; la diferencia es que en el prototipo un encargo ocupaba 160
   caracteres y aqui ocupa el informe entero.
3. **Puede releer el resultado.** Como "lo dijo el", lo resume y lo repite —
   los mensajes casi identicos de la primera captura.

---

## 2. Como lo hace el prototipo, y por que tampoco es correcto

`RealtimeWiring.swift:145` del prototipo:

```swift
pendingEscalationResult = String(MarkdownSplitter
    .plainText(MarkdownSplitter.reportCut(reply).summary)
    .prefix(160))
```

160 caracteres del primer bloque, pegados al SIGUIENTE mensaje del usuario
como `(Tu especialista ya respondio: «…»)`, y luego borrados. La pantalla
recibe el informe completo por otro camino (`thread.completeJobTurn`).

**El principio es correcto** — mostrar todo, recordar poco — y explica por que
se siente mas agil. **La ejecucion se pasa de corta**: 160 caracteres son unos
40 tokens, y con eso el modelo no puede contestar "¿y que habia dentro?" sin
volver a delegar.

Y el rol tampoco es correcto: lo inyecta en un turno `user`.

---

## 3. Lo que dice la documentacion

| Fuente | Que dice | A quien le da la razon |
|---|---|---|
| OpenAI, function calling | El resultado de una tool vuelve con `role: "tool"` y un `tool_call_id` que corresponda a la entrada `tool_calls` del mensaje `assistant` anterior | A ninguno de los dos |
| Anthropic, context engineering | "El contexto debe tratarse como un recurso finito con rendimientos marginales decrecientes"; "a medida que aumentan los tokens, la capacidad del modelo de recordar con precision disminuye" | Al prototipo |
| Anthropic, multi-agent research | Cada subagente "devuelve solo un resumen condensado y destilado de su trabajo, a menudo 1.000-2.000 tokens" | A ninguno: el rebuild no acota, el prototipo recorta 25 veces de mas |

**Veredicto: el prototipo tiene el principio; el rebuild tiene la plumbing.**

`Turn` ya declara `toolCalls: [ToolCallRef]` y `toolCallID: String?`, con un
comentario que dice literalmente que la API rechaza un mensaje de tool sin el.
`MarkdownSplitter.reportCut` ya existe y esta probado. **Ninguno de los dos lo
llama nadie desde `Sources/`.** Es el tercer caso del mismo patron en este
repo, despues de `stepLabel` y `approvalAnnouncement`: el mecanismo se porto y
su uso se quedo atras.

---

## 4. Decision

Tres piezas, y las tres son la misma idea: **separar lo que se muestra de lo
que se recuerda.**

### 4.1 Un mensaje puede recordarse distinto de como se lee

`ChatMessage` gana un campo opcional:

```swift
public struct Recall: Sendable, Equatable {
    public var role: TurnRole
    public var content: String
    public var toolCalls: [ToolCallRef]
    public var toolCallID: String?
}
public var recall: Recall?
```

`nil` significa "recuerdame como me lees", que es el caso de todo mensaje
normal y por lo tanto no cambia nada para ellos. `windowedTurns()` usa el
`recall` cuando esta, y el texto cuando no.

### 4.2 El encargo vuelve como resultado de tool, no como monologo

Hoy la llamada a `delegate` desaparece del historial y el resultado aparece
como un `assistant` suelto. Pasa a ser el intercambio que la API espera:

- La **linea de estado** del encargo ("Encargo: …"), que hoy se excluye del
  historial, pasa a llevar el turno `assistant` con su `tool_calls`. Es el
  sitio natural: ya es el registro de QUE se delego.
- El **informe** se muestra igual que hoy, y se recuerda como turno `.tool`
  con el `toolCallID` que le corresponde.

El id lo generamos nosotros. No hace falta el del proveedor: la historia que
mandamos la construimos nosotros, y lo unico que exige la especificacion es
que ambos lados coincidan dentro de ella.

### 4.3 El resumen se acota, pero con el presupuesto de la documentacion

`ConversationMemory.recall(_:budget:)` en Core, pura:

- Si el texto cabe en el presupuesto, vuelve entero. **La mayoria de
  resultados caben**, y recortarlos costaria poder responder preguntas de
  seguimiento sin re-delegar.
- Si no cabe: el resumen de `reportCut` mas lo que quepa, cortando en
  frontera de bloque, y una nota de que el informe completo esta en pantalla.
  Nunca un corte mudo.
- Presupuesto por defecto **4.000 caracteres (~1.000 tokens)**, el extremo
  bajo del rango que documenta Anthropic. No 160.

---

## 5. Restricciones

- El hilo no cambia. Karen sigue viendo el informe completo: esta wave no
  quita nada de la pantalla.
- Un mensaje sin `recall` se comporta exactamente como hoy. La regresion
  posible esta acotada al camino de encargos.
- El presupuesto vive en un solo sitio, con su fuente citada.
- Nada de esto toca la voz. El acuse hablado es otro problema, anotado aparte.

---

## 6. TDD

1. Un mensaje normal (sin `recall`) llega al historial igual que hoy.
2. Un informe corto vuelve entero: no se recorta lo que no hace falta.
3. Un informe largo se recorta al presupuesto Y dice que se recorto.
4. El recorte empieza por el resumen de `reportCut`, no por el principio bruto.
5. Tras un encargo, el historial contiene un `assistant` con `tool_calls` y un
   `.tool` con el MISMO `toolCallID`. Nunca uno sin el otro.
6. Ningun turno `.tool` viaja sin `toolCallID` — es lo que la API rechaza.
7. El modelo ya no ve el informe como `assistant`: ese rol desaparece del
   historial para el resultado del especialista.
8. El hilo en pantalla sigue mostrando el informe completo.

---

## 6bis. Ampliacion — las tarjetas (2026-08-24)

Decision de Karen: **todos deberian poder usar los widgets.** De ahi salieron
tres arreglos que comparten causa con esta wave.

**El vocabulario de tarjetas vive ahora en un solo sitio** (`CardVocabulary`),
usado por el prompt de la charla Y por el del especialista. Antes vivia inline
en el rol del especialista, lo que tenia dos costos: la charla nunca aprendio
la sintaxis — preguntar por un lugar sin delegar no podia pintar el mapa que el
cliente ya sabia dibujar — y cualquier segunda copia se habria separado de esta
al primer cambio de forma del JSON.

**El JSON de las tarjetas ya nunca entra en la memoria del modelo.** Antes
dependia del tamano: un informe largo dejaba fuera las tarjetas (via
`reportCut`) y uno corto mandaba el payload entero. Mismo dato, dos destinos,
decision de nadie. Es la misma separacion que documenta el Apps SDK cuando
reenvia `_meta` al componente y lo deja fuera de la transcripcion. Queda un
marcador en su lugar: borrarla en silencio haria creer al modelo que no mostro
nada, y volveria a ofrecer lo que ya esta en pantalla.

**Lo que dice el asistente pasa por el mismo filtro que un informe.** El camino
ordinario no pasaba por ninguno, asi que la charla —que ahora tambien pinta
tarjetas— habria metido su propio JSON en el historial.

### Lo que NO se arreglo, y por que

El modelo **escribe** las coordenadas. El patron documentado es el contrario:
la app aporta los datos desde una ejecucion de confianza y el modelo solo elige
la presentacion ("el LLM no genera React — selecciona una capacidad de interfaz
que expone tu aplicacion"). Validamos rangos, lo que atrapa el disparate pero
no el error plausible: un pin en la calle equivocada se ve igual de seguro que
uno correcto.

Mitigacion barata aplicada: el vocabulario ahora dice explicitamente que no se
inventen coordenadas y que solo se emita la tarjeta para lugares consultados de
verdad. **El arreglo real es una herramienta de geocodificacion**, y eso exige
el ejercicio del ADR 001 — un fallo observado, y la prueba de que ninguna tool
existente lo cubre.

### Hallazgo al implementar

El presupuesto no se aplicaba cuando el PRIMER bloque ya lo excedia: una pared
de prosa sin cortes es un solo bloque, y el limite era un consejo en vez de un
tope. Lo destapo un test viejo que exigia 10.000 caracteres intactos en el
historial. Ese test se migro: el hilo y la persistencia siguen guardando los
10.000 — se comprueba — y solo la memoria los acota.

---

## 7. Fuera de alcance

- El acuse hablado que la voz escribe en el hilo (toca ADR 005).
- Compactar el historial viejo. Esta wave acota lo que ENTRA; comprimir lo que
  ya esta es otro problema y llega cuando se note.
- Cambiar `historyWindow`.

---

## 8. Fuentes

- OpenAI — Function calling y referencia de chat completions: el resultado de
  una tool vuelve como `role: "tool"` con `tool_call_id` correspondiente.
- Anthropic — *Effective context engineering for AI agents*: contexto como
  recurso finito, degradacion de recall al crecer la ventana, compactacion.
- Anthropic — *How we built our multi-agent research system*: los subagentes
  devuelven un resumen condensado de 1.000-2.000 tokens, no su trabajo entero.
- Codigo del prototipo: `RealtimeWiring.swift:145`, `main.swift:422`.
- Codigo del rebuild: `ChatViewModelJobs.runJob`, `ChatViewModel.windowedTurns`,
  `Conversation.swift` (`ToolCallRef`, `Turn.toolCallID`), `Markdown.reportCut`.
