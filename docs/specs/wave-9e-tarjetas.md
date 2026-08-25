# Wave 9e — Las tarjetas, como las define la industria

**Estado: CERRADA (2026-08-24).** Las tres piezas entregadas. 195 tests.

**Desviacion de la spec, decidida al implementar:** no se anadio
`outputSchema`. Su funcion en MCP es que un cliente REMOTO valide un JSON que
cruza un protocolo. Nuestras tarjetas son tipos Swift compilados y en proceso:
el tipo YA es el contrato, y lo comprueba el compilador. Declarar un esquema
JSON encima habria sido ceremonia, no seguridad — y un campo que nadie valida
es justo el patron que este repo lleva tres waves corrigiendo.

**Estado original: BORRADOR (2026-08-24).** Sale de rechazar una mitigacion barata. En
9d se anadio al prompt "no te inventes las coordenadas", que trata el sintoma:
el modelo sigue siendo la FUENTE del dato. Esta spec traza el contrato real y
lo que costaria cumplirlo.

---

## 1. El principio, en una linea

> "El LLM no genera React — **selecciona una capacidad de interfaz** que expone
> tu aplicacion."

El modelo elige QUE mostrar. La aplicacion aporta CON QUE. Hoy hacemos lo
contrario: el modelo escribe el payload y nosotros lo parseamos.

## 2. El contrato, como lo define MCP Apps / Apps SDK

Tres canales, con una regla de decision explicita en la documentacion:

| Canal | Cuando va ahi |
|---|---|
| `content` | El modelo (o un cliente sin UI) lo necesita |
| `structuredContent` | La UI lo necesita **y** es seguro para el contexto del modelo |
| `_meta` | La UI lo necesita **y** el modelo NO debe razonar sobre ello |

Mas dos piezas:

- **`outputSchema`**: declara el JSON exacto que devuelve la tool. Da a los
  clientes con que validar y al componente **un contrato de render estable**.
  No es prosa: es esquema.
- **`_meta.ui.resourceUri`**: ata la tool a su plantilla de UI. La tool
  responde "que se puede llamar y que interfaz aparece"; el recurso responde
  "como se renderiza".

## 3. Que tenemos y que falta

| Contrato | Companion hoy | Estado |
|---|---|---|
| `content` | `ToolResult.output` (String) al turno `.tool` | **Existe** |
| `structuredContent` | — | **Falta** |
| `_meta` (fuera del contexto) | — | **Falta** |
| `outputSchema` | `ToolSpec` solo declara ENTRADA | **Falta** |
| Plantilla atada a la tool | `MapCard` / `GalleryCard` atadas a un lenguaje de fence | Existe, mal atado |
| Canal a la UI | `JobEvent` (`stepStarted`, `thought`, `approvalRequested`) | **Existe y sirve** |

La conclusion incomoda: **la tarjeta no tiene por donde llegar a la pantalla
salvo atravesando al modelo.** `ToolResult` es una cadena, y esa cadena vuelve
al bucle del modelo. Cualquier dato que quiera pintarse tiene que pasar por su
memoria, escribirse otra vez, y esa segunda escritura es donde nace la
alucinacion.

## 4. El diseno correcto

### 4.1 `ToolResult` gana el canal que le falta

```swift
public struct ToolResult {
    public var ok: Bool
    public var output: String        // content: lo que el modelo lee
    public var card: CardPayload?    // structuredContent + _meta: lo que la UI pinta
}
```

El modelo lee `output` — nombres, direcciones, lo suficiente para conversar.
**Nunca ve las coordenadas**, asi que no puede transcribirlas mal.

### 4.2 `ToolSpec` declara su salida

Hoy `ToolSpec` describe solo la entrada. Gana `outputSchema`, que es lo que
convierte "el componente espera esta forma" de comentario en contrato
verificable — y lo que hace que un payload malformado sea un fallo del test y
no un bloque de codigo feo en pantalla.

### 4.3 El payload viaja por el canal que ya existe

`JobEvent.card(CardPayload)`. El runner lo emite, el hilo lo pinta. No entra en
`ToolResult.output`, no entra en el historial, no lo escribe el modelo.

### 4.4 Una tool que produzca datos de verdad

Sin una fuente, el contrato no tiene que transportar. Para lugares la fuente
correcta es **nativa y sin clave**: `MKLocalSearch` / `MKGeocodingRequest`
(verificado en el SDK instalado), y el proyecto ya importa MapKit para
`MapCard`. Cero dependencias nuevas.

```
find_places(query, near?) -> nombres + direcciones (al modelo)
                          -> coordenadas reales   (a la tarjeta)
```

### 4.5 El fence no se borra: se marca

Aqui esta la parte que la documentacion NO cubre, porque los hosts de MCP no
tienen nuestro hibrido. Los especialistas CLI (Claude Code, hermes) **no corren
nuestras tools**: devuelven texto. Para ellos el fence es el unico canal, y
borrarlo les quitaria las tarjetas por completo.

Decision: la tarjeta lleva **procedencia**.

- Nacida de una tool → dato verificado, se pinta como hoy.
- Nacida de un fence → la escribio el modelo, y la tarjeta **lo dice en la
  cara**, visiblemente.

No es un adorno: es exactamente el defecto que abrio esta wave — *un pin en la
calle equivocada se ve igual de seguro que uno correcto*. Si no podemos impedir
que el modelo lo escriba, lo minimo es dejar de presentarlo con la misma
autoridad que un dato consultado.

---

## 5. Piezas

```
9e-1  el canal        ToolResult.card + JobEvent.card + outputSchema
9e-2  la fuente       find_places sobre MKLocalSearch
9e-3  la procedencia  la tarjeta dice de donde salio su dato
```

9e-1 sin 9e-2 es un canal sin carga. 9e-3 es independiente y es la que mas
valor da por linea escrita.

## 6. Lo que esto cuesta, dicho antes

- **Una tool mas.** El ADR 001 exige el ejercicio, y hay que hacerlo con
  honestidad: aqui **no hay un fallo observado**. No hemos visto un pin malo.
  Lo que hay es un defecto de arquitectura documentado — el dato lo origina el
  modelo — y eso es una razon legitima, pero no es la misma. Se escribe asi en
  el ADR o no se escribe.
- **`ToolResult` es un tipo que cruza capas.** Cambiarlo toca Core, el runner,
  el executor y la UI.
- **La procedencia es visible**, o sea que es decision de diseno tuya, no mia.

## 7. TDD

1. Una tool con `card` no mete el payload en `ToolResult.output`.
2. El historial del modelo no contiene nunca las coordenadas de una tarjeta
   nacida de tool.
3. `outputSchema` rechaza un payload con la forma equivocada, y el test falla
   ahi — no en pantalla.
4. `find_places` devuelve coordenadas de `MKLocalSearch`, no del modelo (test
   con un buscador falso: el de verdad sale a la red).
5. Una tarjeta de fence se marca como no verificada; una de tool no.
6. Sin tool disponible, un fence sigue pintando: los especialistas CLI no
   pierden nada.

## 8. Fuera de alcance

- Convertir Companion en host MCP. El contrato se toma prestado; el protocolo
  no.
- `_meta.ui.resourceUri` y plantillas remotas. Nuestras tarjetas son nativas y
  compiladas; el equivalente del "recurso" es el propio `MapCard`.
- Galeria desde tool. Sin una fuente de imagenes de confianza, seria el mismo
  error con otra cara.

## 9. Fuentes

- Vercel — *AI SDK 3.0, Generative UI*: el modelo selecciona una capacidad, no
  genera la interfaz.
- OpenAI Apps SDK — *Reference* y *Add UI to your MCP server*: `content` /
  `structuredContent` / `_meta`, y `_meta` reenviado al componente sin exponerlo
  al modelo.
- MCP Apps — `outputSchema` como contrato de render estable entre tool, host y
  componente; `_meta.ui.resourceUri` para atar tool y plantilla.
- SDK instalado: `MKLocalSearch.h`, `MKGeocodingRequest.h`, `CLGeocoder.h`.
