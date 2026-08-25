# Wave 9g — El ciclo de vida del encargo

**Estado: APROBADO (2026-08-24). 9g-1 CERRADA.**

**Entregado — 9g-1, el freno.** `cancelJob()` en el view model llama al
`cancel()` que llevaba desde la Wave 4 construido, probado y sin pedal. Botón
**Parar** junto al reloj de la tarjeta: lo que quieres mientras esperas es
saber cuánto lleva y cómo detenerlo. Parar **conserva lo hecho y lo dice** —
la promesa de la referencia— y no se reporta como fallo: un encargo parado ya
dijo lo suyo, y un segundo aviso se leería como que algo se rompió.

**Dos hallazgos durante la implementación:**

1. `JobSteps.summary` solo conocía los nombres de herramienta de Claude Code
   (`Bash`, `Read`, `WebSearch`…). Un encargo del ejecutor **nativo** dejaba un
   registro que no decía nada de lo que había hecho — y eso importa justo
   cuando lo paras y quieres saber hasta dónde llegó. Ahora entiende los dos
   vocabularios.
2. `ChatViewModelJobs` escribía `"Error en el encargo: …"` **cableado en
   español**, fuera del catálogo, donde el gate estático no lo ve porque no es
   un `Text(...)`. Pasa por el catálogo.

**Entregado — 9g-1b, el freno por voz.** `stop_job` como tool del Realtime,
hermana de `resolve_approval`, atada al mismo runner que el boton. Sin
parametros a proposito: parar no admite matices, y un argumento que el modelo
pueda rellenar mal es una forma de no parar. Con la misma disciplina que su
hermana: prohibido llamarla por iniciativa propia.

**Entregado — 9g-2, negar con alcance.** Negar el PRIMER paso para el encargo
entero; negar uno posterior solo acota. La asimetria es la decision: un encargo
cuyo primer paso rechazas casi nunca es uno que quieras que siga probando
alternativas — que es literalmente lo que paso, `diskutil` denegado y `df -h`
adelante. Pero si ya autorizaste algo, el encargo va donde tu lo mandaste, y
abortarlo tiraria lo que si quisiste.

**Entregado — 9g-5, la voz confirma.** Un encargo nacido de voz escribe en el
hilo QUE entendio, **literal**, antes de tocar nada. Parafrasear seria la misma
trampa en una segunda capa. Un encargo tecleado no lo hace: ya viste tus
propias palabras.

**NO entregado — 9g-4, y por que.** Iba a mover la tarjeta viva dentro de la
lista de mensajes. Al mirarlo de cerca, la tarjeta al fondo **es correcta**
mientras hay un encargo vivo: es lo que esta pasando ahora. Lo que Karen vio
como desorden (respuesta → mapa → tarjeta) era un TERCER encargo arrancando
despues de la respuesta anterior. El ruido real de esa pantalla son los acuses
duplicados, que es 9g-3 y el ADR 005, no la posicion de la tarjeta. No se toca
lo que no esta roto.

**Entregado — 9g-3, encolar (corregido en uso).**

La primera version RECHAZABA el segundo encargo. Karen lo probo y salio peor
que el bug original: pedir cines mientras buscaba parques **cancelo las dos
cosas**. Dos causas, ambas mias:

1. **Copy que llega a un modelo no es copy, es prompt.** El mensaje de rechazo
   decia "dime para si quieres que lo deje y haga esto". Escrito para la
   usuaria; el modelo lo leyo como instruccion, llamo a `stop_job` y mato el
   encargo vivo.
2. **La descripcion de `stop_job` era laxa**: "o diga que eso no es lo que
   pidio" cubre casi cualquier peticion nueva. Ahora exige una peticion
   EXPLICITA de parar, y dice que una tarea nueva se encola.

**Y la decision de rechazar era la equivocada.** La documentacion distingue
TRES gestos y ninguno cancela lo que corre:

| Gesto | Que hace |
|---|---|
| Interrumpir (Esc / Ctrl+C) | Para y conserva lo hecho |
| Steer (Codex: Enter) | Inyecta en el turno vivo; el agente se adapta sin perder progreso |
| Encolar (Codex: Tab · Claude Code: Enter) | Se guarda y corre despues, visible y retirable |

Pedir otra cosa es lo tercero. Mi objecion contra encolar —"trabajo que
arranca solo cuando ya lo olvidaste"— la resuelven con VISIBILIDAD, no
rechazando: Claude Code lista lo encolado sobre el input y deja retirarlo.

Ahora se encola: `JobQueue` ya serializaba la ejecucion, asi que bastaba con
mandarlo y **decir que espera**. Un segundo encargo anunciandose como si
hubiera arrancado era lo que hacia que dos se pelearan por una tarjeta.

**Pendiente, anotado:** lo encolado se ve en el hilo pero no se puede retirar
por voz. Claude Code lo permite. Cuando aparezca la necesidad, es una tool
hermana de `stop_job`.

**WAVE COMPLETA.** 202 tests.

**Estado original: BORRADOR (2026-08-24).** Sale de una sesion real de Karen en la que
la app **ejecuto trabajo que ella nunca pidio y no pudo detener**. El desorden
visual que la hizo mirar era el sintoma; esto es la causa.

---

## 1. Lo que paso, paso a paso

| # | Hecho | Evidencia |
|---|---|---|
| 1 | El STT destrozo el audio | El hilo guarda "Sinaırakalık forma." como lo que se dijo |
| 2 | El modelo de charla **invento** una tarea plausible de ese ruido | "Perfecto, vamos a ver el espacio disponible y como esta tu disco" |
| 3 | Delego. Arranco un encargo que toca el sistema de archivos | `Encargo: Revisar el espacio disponible…` |
| 4 | Karen se corrigio hablando | "Cines, cines cerca del Reforma" |
| 5 | **Nada cancelo el primer encargo** | No existe llamador de `cancel()` |
| 6 | Karen nego el permiso | `Permiso denegado.` |
| 7 | **El encargo siguio y entrego un informe de disco** | "Estado del disco", 926 GiB, y su propia nota: "solo pude ejecutar `df -h`; el mas detallado fue bloqueado por permisos" |

Un audio mal oido se convirtio en trabajo real sobre su Mac, y ni corregirse ni
negar el permiso lo detuvo.

## 2. Los cuatro defectos, verificados en el codigo

1. **Nada puede cancelar un encargo.** `JobRunner.cancel()` existe y esta en el
   protocolo `JobSubmitter`. **Cero llamadores en `Sources/`.** Es el cuarto
   caso en este repo de construido-probado-jamas-invocado, y este es el freno
   de emergencia.
2. **Negar es por comando, no por encargo.** El gate paro `diskutil` y el
   encargo continuo con `df -h`. No existe "esto entero, no".
3. **Dos encargos comparten un hueco.** `pendingApproval` es un unico
   `ApprovalRequest?` y `job` un unico `JobTimeline?`. Con dos encargos en
   vuelo se pisan, y una respuesta puede contestar por el encargo equivocado.
4. **La tarjeta viva no tiene lugar en el tiempo.** `JobCardView` se pinta
   FUERA de `ForEach(model.messages)`, clavada al final. Por eso el proceso
   aparece despues del resultado.

## 3. Como lo resuelven los que ya lo resolvieron

### 3.1 Interrumpir y negar son gestos DISTINTOS

Claude Code, referencia de modo interactivo:

> `Esc` — **Interrupt Claude**: "Stop the current response or tool call
> mid-turn so you can redirect. **Claude keeps the work done so far.**"
> Y en un dialogo de permiso, `Esc` **declina la accion**, igual que **No**.

Dos gestos, dos alcances: **No** rechaza *esta accion*; **Esc** para *el turno*
y conserva lo hecho. Companion no tiene ninguno de los dos.

### 3.2 Escribir mientras trabaja NO lanza un segundo encargo

> "Type a message and press Enter while Claude is working. Claude Code
> **queues** the message instead of interrupting the turn."

Por eso nunca necesitan dos huecos de aprobacion: **no hay dos turnos
compitiendo**. Karen tenia dos encargos en vuelo porque hablar durante uno
arranca otro.

### 3.3 Cada aprobacion tiene identidad propia

Codex asigna **ids de aprobacion distintos a cada comando** dentro de una
ejecucion de varios pasos, y su flujo admite **rechazo granular**. Y separa dos
cosas que aqui estan mezcladas: *el sandbox decide hasta donde alcanza un
comando; las aprobaciones deciden cuando se para a preguntar*.

Companion ya genera un `requestId` por peticion. Lo que falta es que la UI deje
de tener un solo cajon para todos.

### 3.4 Negar puede llevar un motivo

> "You can attach a note to Claude when you approve or **deny** a single
> action."

Es exactamente lo que a Karen le falto poder decir: *no es que no te deje —
es que yo no pedi esto*.

### 3.5 Una tool que no se puede usar no se le enseña al modelo

> "A bare tool name like `Bash` **removes the tool from Claude's context
> entirely, so Claude never sees it**." Una regla con patron, en cambio, deja
> la tool visible y bloquea las llamadas que encajen.

Confirmacion independiente de lo que ya hicimos con `availableTools`: hay dos
granularidades distintas —quitar la capacidad y bloquear la llamada— y
conviene no confundirlas.

### 3.6 La delegacion es una FILA del hilo, y el detalle se pide

En Claude Code la delegacion "aparece como una **fila de tool call** con el
nombre del subagente y una descripcion corta". Al terminar, **la fila
desaparece** y el detalle queda disponible bajo demanda durante un rato.
Ademas, "el agente lider ve solo el resumen final de cada subagente, nunca sus
pasos intermedios".

Tres cosas que nosotros hacemos al reves: la tarjeta no esta en el hilo, se
queda despues de terminar, y hasta la Wave 9d el informe entero entraba en la
memoria del modelo.

## 4. Decision

### 4.1 Dos gestos, no uno

- **Negar** rechaza *esa* accion y **puede llevar un motivo** que viaja al
  modelo. Es lo que hay hoy, mas la nota.
- **Parar** cancela el encargo entero llamando al `cancel()` que ya existe,
  conserva lo hecho, y lo deja dicho en el hilo.

Y una tercera cosa, que es la que Karen necesitaba y ninguno de los dos cubre:
**negar la PRIMERA accion de un encargo pregunta si se para el encargo**. Un
encargo cuyo primer paso se rechaza casi nunca es un encargo que quieras que
siga por otro camino.

### 4.2 Un turno a la vez; hablar encola

Hablar o escribir mientras un encargo corre **encola**, no lanza otro. Es lo
que hace desaparecer el problema del hueco compartido en vez de administrarlo.

`ChatViewModel` ya tiene `queued` para el chat. Se extiende al encargo.

### 4.3 Un hueco por encargo

Aprobaciones y tarjetas **indexadas por id de encargo**, no globales. Aunque
4.2 haga raro el caso, un unico cajon global es una bomba que ya exploto.

### 4.4 La tarjeta vive en el hilo

`JobCardView` entra en `ForEach(model.messages)` como un mensaje mas, en el
punto donde ocurrio. Al terminar deja su rastro de una linea —que es lo que la
Wave 9-0 ya decidio— y el detalle se abre bajo demanda.

### 4.5 Una transcripcion dudosa no lanza trabajo con efectos

La causa raiz. Ninguna de las referencias habla de voz, pero el principio de
Codex traduce: *el sandbox decide el alcance, la aprobacion decide cuando
parar a preguntar*. Para voz, el equivalente es que **una transcripcion de baja
confianza es entrada no confiable**, y la entrada no confiable no llega a un
encargo con efectos sin confirmacion.

Minimo viable: si el encargo nacio de voz y el modelo va a tocar disco, el
hilo repite en una linea QUE entendio antes de arrancar. Karen habria visto
"revisar el disco" cuando dijo "cines" y lo habria parado en el primer segundo.

## 5. Piezas

```
9g-1  parar de verdad      cancel() con llamador, en UI y por voz
9g-2  negar con alcance    motivo en la negativa + "¿paro el encargo?"
9g-3  un turno a la vez    encolar en vez de lanzar un segundo
9g-4  la tarjeta en el hilo  posicion temporal + rastro al cerrar
9g-5  la voz confirma       lo que entendio, antes de tocar disco
```

9g-1 es el freno y va primero. 9g-3 elimina la clase de bug de 9g-4/huecos
compartidos en vez de gestionarla.

## 6. TDD

1. `cancel()` tiene llamador y un encargo cancelado no entrega resultado.
2. Lo hecho antes de parar se conserva y se dice; no se tira en silencio.
3. Negar la primera accion ofrece parar el encargo; negar una posterior no.
4. La negativa con motivo llega al modelo.
5. Hablar durante un encargo **encola**: no hay dos encargos vivos a la vez.
6. Dos peticiones de aprobacion no se pisan: cada una responde a su id.
7. La tarjeta del encargo aparece entre los mensajes anteriores y el
   resultado, nunca despues.
8. Un encargo nacido de voz que va a tocar disco confirma lo entendido.

## 7. Fuera de alcance

- Un sandbox de sistema operativo al estilo de Codex. Aqui el limite lo pone
  `PathValidator` y el gate de aprobaciones; cambiar eso es otra wave.
- Reglas de permiso persistentes ("no preguntes mas por este comando"). Util,
  y otra conversacion.
- Mejorar el STT. `SpeechTranscriber` sigue siendo deuda post-v1; 9g-5 asume
  que la transcripcion puede ser mala y protege igual.

## 8. Fuentes

- Claude Code — *Interactive mode*: `Esc` interrumpe la respuesta o la tool
  call a mitad de turno y conserva lo hecho; en un dialogo de permiso declina
  la accion. Escribir mientras trabaja **encola**.
- Claude Code — *Configure permissions*: orden deny → ask → allow; una regla
  de nombre desnudo **quita la tool del contexto del modelo**; se puede
  adjuntar una nota al aprobar o negar.
- Codex — *Agent approvals & security* y referencia de configuracion: sandbox
  y aprobaciones son ejes distintos; ids de aprobacion por comando; rechazo
  granular.
- Anthropic — *How we built our multi-agent research system*: el lider ve el
  resumen del subagente, no sus pasos.
- Claude Code — subagentes: la delegacion es una fila de tool call en el hilo,
  la fila se retira al terminar y el detalle queda bajo demanda.
- Codigo: `JobRunner.cancel()` sin llamadores; `ChatViewModel.pendingApproval`
  y `.job` como huecos unicos; `ThreadView:95` con la tarjeta fuera de la lista.
