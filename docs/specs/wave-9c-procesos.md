# Wave 9c — Ciclo de vida de subprocesos y controles de rendimiento

**Estado: APROBADO (2026-08-23).** Nace de una sospecha de Karen sobre procesos
`hermes serve` huerfanos. La sospecha resulto ser de OTRA app — pero al ir a
comprobarlo aparecieron defectos reales en esta, y uno de ellos rompia encargos.

**Entregado:** 9c-1, 9c-2 y 9c-3 (mecanismo).
**Pendiente:** el contador visible en Ajustes, y 9c-4 (identidad compartida,
decision de Karen).

---

## 1. La sospecha, comprobada: no era Companion

Karen encontro en las preferencias de `com.karen.companion` estas claves:

```
hermesVoiceChoice = "GPT-5.4";
hermesVoiceEchoCancellation = 1;
hermesVoiceSessions = { claude = ...; fast = ...; hermes = ... };
```

y concluyo que Companion levanta `hermes serve` como subproceso por sesion de
voz, dejando uno vivo cada vez. **No es asi, y la evidencia es del disco:**

| Comprobacion | Resultado |
|---|---|
| Claves que este repo escribe | Solo `companion.*` (`companion.voice`, `companion.language`, …). Ni una `hermes*` en `Sources/` |
| Quien escribio `hermesVoice*` | El **prototipo**: `../companion/build/companion.app/Contents/Info.plist` declara `CFBundleIdentifier = com.karen.companion` — el MISMO id que el rebuild |
| Que lanza el rebuild | `hermes chat -Q` (batch, `HermesExecutor:58`), el CLI de `claude`, y `/bin/sh -c` para `run_shell`. **Ningun servidor** |
| El "widget" del PROTOCOL.md | Tiene su propio dominio en esta Mac: `com.desktop-widgets.hermes-voice`. Es otro programa |
| La voz de Companion | OpenAI Realtime o el pipeline clasico (`SFSpeech` + `AVSpeech`). No pasa por `hermes serve` |

**Conclusion: matar los 13 `hermes serve` no pudo romper la voz de Companion.**
Su voz no depende de ellos. Los procesos vivos ahora son tres Python de
`~/.hermes/hermes-agent/venv` de hace minutos — el gateway que launchd
resucito, no fugas.

### El hallazgo que sale de regalo

El prototipo y el rebuild **comparten bundle id**. Wave 9 renombro
`com.karen.companion.next` a `com.karen.companion`, que es la identidad que el
prototipo ya ocupaba. Consecuencias medidas:

- El dominio de preferencias del rebuild contiene datos fantasma de otra app.
  Hoy no chocan porque los nombres de clave no se cruzan; es suerte, no diseno.
- **Es la misma causa del prompt de contrasena del llavero** que Karen sufre a
  diario: el item se creo bajo el id viejo y su ACL ya no reconoce a quien
  pregunta. Un solo renombre, dos sintomas.

Decidir en esta wave: reclamar `com.karen.companion` como identidad unica y
limpiar el fantasma, o volver a un id propio. No se puede dejar a medias.

---

## 2. Los defectos que si son de este repo

La intuicion era buena aunque el culpable fuera otro: **este codigo puede dejar
huerfanos, y ademas tiene un bug que rompe encargos hoy.**

### 2.1 Un encargo con salida grande SIEMPRE falla por timeout

`NativeToolRunner.runShell` lee la salida **despues** de esperar a que el
proceso termine:

```swift
while process.isRunning && Date() < deadline { usleep(10_000) }
...
let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
```

Un pipe tiene ~64 KB de buffer. Un comando que escriba mas se **bloquea
escribiendo**, nunca termina, el bucle agota el deadline y el usuario recibe
"Command execution timeout exceeded" para un comando que funcionaba. Cualquier
`git log`, `ls -R` o build lo dispara. Es el defecto mas urgente de la wave y
no tiene nada que ver con huerfanos.

### 2.2 El bucle de espera quema un hilo

Ese mismo `while` con `usleep(10_000)` ocupa un hilo del pool cooperativo
hasta `timeout` segundos. Con varios encargos en paralelo, se comen hilos que
el resto de la app necesita. Es un control de rendimiento que falta, no una
optimizacion.

### 2.3 `terminate()` es SIGTERM y nada mas

`ExecutorIntegration.swift:136` y `NativeToolRunner:187` llaman
`process.terminate()` y siguen. No hay `waitUntilExit`, no hay escalada a
SIGKILL, no hay confirmacion de muerte. **Un hijo que ignore SIGTERM vive para
siempre**, y nadie se entera.

### 2.4 Se mata al hijo, no a su descendencia

`process.terminate()` senala solo al proceso directo. `hermes chat -Q` es
Python y `/bin/sh -c` es una shell: los dos pueden tener hijos propios que
sobreviven y los adopta `launchd`. **Este es exactamente el mecanismo que
produciria lo que Karen vio** — solo que en la app que si levanta servidores.

### 2.5 La app no limpia al salir

`AppDelegate` no implementa `applicationWillTerminate`. Si Companion se cierra
con un encargo en marcha, el subproceso queda vivo. `ClaudeCodeExecutor`
mantiene un handle de sesion larga: es el candidato numero uno a quedar suelto.

### 2.6 No hay techo de subprocesos concurrentes

Nada limita cuantos encargos lanzan shells a la vez.

---

## 3. Lo que dice la documentacion

- **macOS no tiene `PR_SET_PDEATHSIG`.** El truco de Linux para que un hijo
  muera con su padre no existe aqui; hay que construirlo.
- **Grupos de proceso son el mecanismo correcto para la descendencia.** Se
  spawnnea con `POSIX_SPAWN_SETPGROUP` (o `setpgid` en el hijo) y se senala al
  grupo entero con `killpg(pgid, SIGTERM)`, que en POSIX es un `kill` con PID
  negativo. Matar al padre solo deja huerfanos que `init`/`launchd` adopta.
- **`Process` de Foundation no expone los atributos de `posix_spawn`**, asi que
  el grupo se consigue con `posix_spawn` directo o envolviendo en una shell que
  haga `setpgid`.
- **`applicationWillTerminate` cubre solo la salida ordenada.** No corre en un
  crash ni en un Forzar salida, asi que es una red, no la solucion.
- **`DispatchSourceProcess` con `PROC_EXIT`** deja que un hijo vigile a su
  padre y se suicide. Solo sirve si controlas el hijo — con `hermes` y `claude`
  no es el caso.
- La sesion como unidad de matanza (`pkill -s`) **no es portable a macOS**: el
  SID no aparece o sale en cero en BSD.

Fuentes al final.

---

## 4. Piezas

### 9c-1 y 9c-2 · CERRADAS (2026-08-23)

`ProcessGroupRunner` (Services, nuevo) sustituye al `Process` inline de
`runShell`. Lo que cambia, y por que Foundation no bastaba:

- **`posix_spawn` con `POSIX_SPAWN_SETPGROUP`.** Un proceso lanzado con
  `Foundation.Process` hereda NUESTRO grupo, asi que senalar ese grupo
  senalaria a Companion. Con `pgroup 0` el hijo es lider de un grupo nuevo y su
  pid es el group id, de modo que `killpg` alcanza a toda su descendencia.
- **Los pipes se drenan MIENTRAS el comando corre.** Ese era el bug: un pipe
  aguanta ~64 KB y leer despues de esperar bloqueaba al hijo escribiendo.
- **La espera no ocupa un hilo.** `waitpid(WNOHANG)` con `Task.sleep` en vez
  del bucle de `usleep`, que paraba un hilo del pool durante todo el timeout.
- **Muerte confirmada:** `killpg` SIGTERM → gracia de 0,25 s → `killpg` SIGKILL
  → `waitpid`. Un SIGTERM suelto es una peticion, no una garantia.
- La salida parcial de un comando que se cuelga **viaja con el fallo**: suele
  ser la pista de por que se colgo.

Siete tests del helper mas dos de regresion por donde lo sufre el usuario. Los
dos que mas importan: un hijo que hace `trap '' TERM` muere igual, y un nieto
(`sleep 30 & ...`) muere con el grupo. La suite ya no deja `sleep` huerfanos.

### 9c-1 · El bug que rompia encargos (descripcion original)

Leer stdout y stderr **mientras** el proceso corre, no despues. Sustituir el
`usleep` por espera sin bloquear hilo. Cerrar el defecto de las 64 KB.

TDD: un comando que escupe 1 MB termina bien y devuelve la salida completa;
un comando que de verdad cuelga sigue dando timeout; el hilo no se ocupa
durante la espera.

### 9c-2 · Muerte que de verdad mata

- Spawn en grupo de proceso propio.
- `terminate()` pasa a ser: `killpg` SIGTERM → gracia acotada → `killpg`
  SIGKILL → confirmar con `waitUntilExit`.
- Un solo helper en Services; ni `NativeToolRunner` ni `ExecutorIntegration`
  reimplementan la escalera.

TDD: un hijo que ignora SIGTERM muere igual; un nieto muere con su abuelo;
`terminate()` no vuelve hasta que el grupo esta muerto.

### 9c-3 · Mecanismo CERRADO (2026-08-23)

- **`ProcessRegistry`**: techo de 8 grupos concurrentes con RESERVA previa al
  spawn — un pid no existe hasta que el spawn vuelve, asi que comprobar el
  techo contra los vivos dejaria pasar a dos que compiten. Un techo que no se
  aplica es documentacion.
- **Los ejecutores CLI migrados al grupo.** `RealProcessLauncher` usa
  `spawnSession`, asi que `claude` y `hermes chat -Q` ya mueren con su
  descendencia. Los tests reales que ya existian (`ProcessRoundtripTests`,
  `/bin/cat`) siguieron verdes durante el refactor: eran la red.
- **`GroupProcess.isRunning` cosecha al preguntar.** Un hijo que salio queda
  zombi hasta que alguien lo recoge, y un zombi todavia responde a
  `kill(pid, 0)`: preguntar solo eso reportaria vivo a un muerto para siempre.
- **`applicationWillTerminate` barre lo que quede**, dicho en el codigo como lo
  que es: una red para la salida ordenada. Un crash o un Forzar salida no la
  ejecutan, y macOS no ofrece pedirle al kernel que se lleve a nuestros hijos.

**Hallazgo colateral, y no era mio.** Al medir aparecio que la suite ya era
INTERMITENTE antes de esta wave: sin ninguno de los tests nuevos, 2 de cada 3
corridas fallaban en `noticeTests` y `voicePreviewTests`. Causa: `pumpUntil`
esperaba 2 s ocupando el main actor, y como todos los tests son `@MainActor`,
bajo carga se quedaban sin turno unos a otros. Con el plazo a 10 s (sale en
cuanto se cumple la condicion, asi que no cuesta nada cuando todo va bien),
cinco corridas seguidas en verde. **La regla "gates verdes antes de cerrar"
pasaba por suerte, no por diseno.**

### 9c-3 · Lo que queda: el contador visible

### 9c-3 · Descripcion original

- `applicationWillTerminate` mata los grupos vivos, **dicho como lo que es**:
  una red para la salida ordenada, no una garantia.
- Registro de subprocesos vivos con techo de concurrencia.
- Un contador visible en Ajustes para que "algo se quedo colgado" sea
  observable en vez de folclore.

### 9c-4 · La identidad compartida (decision de Karen)

Reclamar `com.karen.companion` limpiando el fantasma del prototipo, o volver a
un id propio. Cierra tambien el prompt de contrasena del llavero.

---

## 5. Fuera de alcance

- Vigilar procesos que Companion no lanzo. Si otra app deja `hermes serve`
  sueltos, no es asunto de este producto — y meterse seria justo el acoplamiento
  que el ADR 004 prohibe.
- Un supervisor tipo launchd propio.
- Matar procesos tras un crash o un Forzar salida. Sin cooperacion del hijo no
  se puede, y no controlamos a `hermes` ni a `claude`. Se documenta el limite.

---

## 6. Fuentes

- Killing a Process and All Its Descendants — grupos de proceso, PID negativo,
  y por que el SID no sirve en BSD/macOS.
- `DispatchSourceProcess` / `makeProcessSource` (Apple Developer) — vigilar la
  muerte de un proceso.
- Hilos de cocoa-dev y de los foros de Apple sobre `NSTask` que sobrevive a la
  app y sobre `applicationWillTerminate` como cobertura parcial.
- Swift Forums: atributos recomendados de `posix_spawnattr_t` para `NSTask`.
