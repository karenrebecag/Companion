# Reference Brief: que AppsModel.load() diga que paso, para que el formulario de Apps no confirme antes de que la funcion conteste

Slug: apps-load-result | Nivel: quick | Fecha: 2026-10-03 | Estado: BORRADOR
Versiones: swift-tools=6.2
Verificador: pendiente

## 1. Pregunta y decisiones abiertas

Pregunta: como sabe el formulario de configuracion de Apps (#225) si la funcion contesto a la carga que sigue al guardado, sin leer `apps.phase` despues de que `load()` volvio.

Encargo relayado por el orquestador el 2026-10-03 (no es palabra directa de Karen): redactar la spec para que `load()` reporte su propio resultado; sin codigo hasta que Karen la firme.

Hoy el controlador del formulario llama a `load()` y despues lee `phase`; `AppsSetupFlow.Outcome.after(load:)` cuenta `.loading` como guardado, marcado con HACK, porque `load()` puede volver sin pintar y dejar la fase en `.loading`.

Hallazgo al preparar este brief: en `load()` la guarda `query == self.query` compara la propiedad consigo misma (no hay copia local), asi que nunca corta. Consecuencia: si se escribe una busqueda mientras la primera carga esta en vuelo, la carga llega despues y pisa la lista filtrada con la pagina sin filtro. `fetch` no tiene el problema porque ahi `query` es parametro.

Con #226 (en cola de merge) la guarda de `load()` suma `setupEpoch == setup`, que si corta cuando se guarda otra configuracion durante la carga; ese es hoy el unico camino real al `.loading` del HACK.

Decisiones abiertas para Karen:

- D1: forma del resultado. Opcion A (recomendada): `load()` devuelve un `LoadOutcome` con lo que la funcion contesto, aunque no lo pinte. Opcion B: `configure()` comprueba siempre, tambien la primera configuracion, y el formulario confirma con `.saved` sin depender de `load()`. Opcion C: dejar el HACK y solo arreglar la guarda.
- D2: que hace el formulario si mientras carga se guardo otra configuracion (`replaced`). Recomendado: volver a editar sin anunciar nada, igual que `.busy` en #226.
- D3: el arreglo de la guarda de busqueda va como PR propio con test en rojo antes de esta spec (no necesita spec: un archivo y su test), despues del merge de #226 porque toca la misma linea.

## 2. Estado actual

- `load()` es `async` sin valor de retorno [repo:Sources/CompanionUI/Apps/AppsModel.swift:240]
- La guarda de busqueda de `load()` compara `query` con `self.query`, la misma propiedad [repo:Sources/CompanionUI/Apps/AppsModel.swift:250]
- `query` es una propiedad del modelo, no una copia local [repo:Sources/CompanionUI/Apps/AppsModel.swift:42]
- `fetch` recibe `query` como parametro, asi que su guarda si detecta una busqueda nueva [repo:Sources/CompanionUI/Apps/AppsModel.swift:512]
- El controlador del formulario carga y luego lee la fase para decidir [repo:Sources/CompanionUI/Apps/AppsSetupController.swift:42]
- El HACK que cuenta `.loading` como guardado [repo:Sources/CompanionUI/Apps/AppsSetupFlow.swift:67]
- La pagina llama a `load()` al aparecer e ignora el resultado [repo:Sources/CompanionUI/Apps/AppsPage.swift:60]
- El boton Reintentar tambien llama a `load()` sin mirar el resultado [repo:Sources/CompanionUI/Apps/AppsPage.swift:208]
Contextos: app (pagina de Apps y formulario de configuracion), tests de CompanionUITests con `AppsModel` real y servicios falsos.

## 3. Fuentes primarias

- En Swift cada `await` es un punto de suspension donde otro codigo del mismo actor puede correr y cambiar su estado, asi que el estado leido despues de un `await` puede no ser el de antes [doc:https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/@6.2]
- SE-0306 describe la reentrada de actores: entre suspensiones se intercala otro trabajo, y lo que se compruebe antes del `await` hay que volver a comprobarlo despues [doc:https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md@6.2]

## 5. Opciones

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A: `load()` devuelve `LoadOutcome` (`answered`, `failed(AppsFailure)`, `notConfigured`, `replaced`), `@discardableResult` | La respuesta ya existe antes de la guarda; el formulario decide con ella y no con la fase; sin request extra; respeta las decisiones de #226; la pagina no cambia | Un enum mas en la API del modelo; `replaced` necesita una regla en el formulario (D2) | baja | Si |
| B: `configure()` comprueba siempre y el formulario confirma con `.saved` | El formulario no depende de `load()`; una clave mala en la primera configuracion no se guarda | Sin red no se puede hacer la primera configuracion; dos requests al configurar; revierte una decision ya registrada en #226 | media | No |
| C: dejar el HACK y solo arreglar la guarda | Cambio minimo | Tras el arreglo, una busqueda durante la carga deja `.loading` y el formulario confirma sin respuesta de la funcion | baja | No |

## 9. Incertidumbre

- ASSUMPTION: ningun otro llamador de `load()` fuera de la pagina y el controlador depende de que no devuelva nada. prueba: `git grep "\.load()"` sobre Sources al implementar; hoy solo aparecen AppsPage (dos) y AppsSetupController.
- ASSUMPTION: con la opcion A, `answered` en una carga sustituida por una busqueda significa que la funcion acepto la clave aunque la lista no se pinte. prueba: test con servicio que estaciona el catalogo, busqueda en medio y aserto de `answered` mas lista filtrada intacta.
- [NEEDS CLARIFICATION: D1, D2 y D3 de la seccion 1]

## 10. Checklist de estandar

- [ ] `load()` devuelve el resultado de la funcion aunque no pinte, y la pagina sigue igual
- [ ] Una busqueda escrita durante la carga conserva su lista filtrada (test en rojo primero)
- [ ] El formulario confirma solo con `answered` y el HACK de `AppsSetupFlow` desaparece
- [ ] `replaced` deja el formulario editable sin anuncio, con test
- [ ] Cada camino nuevo tiene su test en rojo antes del codigo

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | The Swift Programming Language: Concurrency | Swift.org | 6.2 | 2026-10-03 | high |
| 2 | SE-0306 Actors | Swift Evolution | 6.2 | 2026-10-03 | high |
