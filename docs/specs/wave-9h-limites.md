# Wave 9h — Los límites: alcance, ritmo y memoria

**Estado: CERRADA (2026-08-24).** Las tres piezas. 205 tests.

**Dos desviaciones decididas al implementar:**

1. **`Retry-After` no se honra**, y no se finge que si. La cabecera no llega:
   `ChatTransport` expone status y lineas, no cabeceras, asi que respetarla
   exige cambiar el puerto y todos sus adaptadores y fakes. Queda como `HACK:`
   con su gatillo, en vez de un parametro que nadie puede rellenar.
2. **Un timeout ya NO se reintenta**, solo el limite de tasa. Lo enseñaron los
   tests: `turnTimeout` son 60 s, asi que tres intentos son tres minutos
   esperando una respuesta que el siguiente proveedor podia dar al momento. Un
   429 dice "vuelve luego" y lo dice en serio; un timeout ya se gasto la
   paciencia una vez.

**Un fallo mio por el camino:** el reintento entro como un `while` dentro del
`for` de proveedores, y los `continue` pelados dejaron de saltar de proveedor —
bucle infinito, 21 tests rojos y la misma URL golpeada cientos de veces. El
bucle se reescribio con etiquetas en vez de parchearse.

**Estado original: BORRADOR (2026-08-24).** Tres cosas que Companion hace distinto de
Codex y Claude Code, encontradas comparando contra su documentación. La
primera es de seguridad y está tomada por omisión, no por diseño.

---

## 1. El alcance: el especialista tiene tu carpeta personal entera

### Lo que hacemos

```swift
// CompanionMain.swift:68
StoredConfigProvider(workdir: FileManager.default.homeDirectoryForCurrentUser.path)
```

`PathValidator` deja pasar cualquier ruta bajo el workdir. `WorkdirPreference
.isAllowed` rechaza `/` y `/Users` pero **permite `$HOME` explícitamente**
(`candidate == homePath`). No existe ningún paso de confianza en ninguna parte.

Resultado: desde el primer arranque, sin preguntar nada, el especialista lee y
escribe en todo el home.

### Lo que hacen ellos

- **Un diálogo de confianza es la puerta.** Las reglas de permiso y los
  directorios adicionales "conceden capacidad **solo después** de que aceptas
  la confianza para esa carpeta".
- **Escribir vive dentro del workdir y sus subcarpetas**; el padre exige
  permiso explícito.
- **Leer fuera del límite pide aprobación por ruta.**
- Y el caso que nos retrata: "cuando arrancas en tu carpeta personal, Claude
  Code mantiene la confianza **solo para esa sesión y no la escribe en disco**".
  Tratan `$HOME` como demasiado amplio para recordarlo.
- Codex separa los ejes: "el sandbox decide a qué archivos y red puede llegar
  un comando; las aprobaciones deciden cuándo se para a preguntar".

### La diferencia, exacta

**No es la política de lectura** — ahí somos MÁS estrictos que ellos: hoy una
lectura fuera del workdir se rechaza, no se pregunta. La diferencia es el
**default**: ellos arrancan en la carpeta del proyecto y piden confianza;
nosotros arrancamos con el home entero y no preguntamos.

No se propone abrir las lecturas para "igualar": sería aflojar la seguridad en
nombre de la paridad.

### Decisión

1. **El home deja de ser el default.** En el primer arranque se elige carpeta.
   Companion no tiene "proyecto", así que el default honesto es preguntar.
2. **Si eliges el home, la confianza es de sesión.** No se persiste — copiado
   literal del comportamiento documentado, y por la misma razón.
3. **El límite se ve.** La carpeta activa ya está en el pie (hoy muestra
   `karenrebecaog`, que es el home y por eso se lee raro). Pasa a decir qué
   alcance tiene, no solo su nombre.

---

## 2. El ritmo: un límite de tasa se presenta como "no hay proveedor"

### Lo que hacemos

`ChatSSEAttempt:103` mapea 429 a `.rateLimited`, y `ChatProviderClient` hace
`continue` al siguiente proveedor. **No hay reintento ni backoff en todo el
repositorio** — `grep` de `retry`, `backoff` y `Retry-After` no devuelve nada.

Si solo tienes OpenAI no hay siguiente peldaño, la escalera se agota y el
usuario lee "no hay proveedor disponible". La verdad era "espera diez
segundos".

Es la misma familia del bug de `noProvider` que se cerró hoy: **un fallo
temporal contado como un fallo de configuración**, que manda a arreglar lo que
no está roto.

### Decisión

1. **429 se reintenta** con backoff acotado antes de bajar de peldaño, y
   honrando `Retry-After` cuando el proveedor lo manda.
2. **Si el reintento se agota, se dice lo que es**: límite de tasa, no
   ausencia de proveedor.
3. El reintento es **visible** mientras ocurre. Una espera silenciosa se lee
   como una app colgada — la misma lección del reloj de la tarjeta.

---

## 3. La memoria: truncamos donde ellos comprimen

### Lo que hacemos

`windowedTurns()` hace `turns.suffix(window)` con `historyWindow = 20`. Lo que
cae por el borde **desaparece**.

### Lo que dice la documentación

> "La compactación destila el contenido de la ventana de contexto de forma
> fiel, permitiendo al agente continuar con **degradación mínima**."

Y sobre por qué importa: "a medida que aumentan los tokens, la capacidad del
modelo de recordar con precisión disminuye" — el contexto es un recurso finito
con rendimientos decrecientes, no un cubo que se vacía por arriba.

### La diferencia

Truncar borra el principio de la conversación sin dejar rastro. En una sesión
larga de voz eso se siente exactamente como lo que Karen describió al empezar
todo esto: que se le olvidan cosas que tú recuerdas haber dicho.

### Decisión

1. Al desbordar la ventana, los turnos más viejos **se destilan en una nota**
   en vez de caerse.
2. La destilación honesta la hace un modelo. **HACK aceptable mientras tanto:**
   una nota local que conserve la primera petición del usuario y un recuento de
   lo ocurrido, marcada como tal, con el gatillo escrito — cuando la nota local
   demuestre ser insuficiente, se paga la llamada.
3. La nota dice que es una nota. Un resumen que se hace pasar por memoria
   completa es la misma mentira que un corte silencioso.

---

## 4. Piezas

```
9h-1  el alcance     default fuera del home + confianza de sesión + límite visible
9h-2  el ritmo       reintento con backoff en 429 + copy honesta
9h-3  la memoria     compactar en vez de truncar
```

9h-1 primero: es la única de seguridad, y es la única que empeora sola con el
tiempo — cada día que pasa hay más gente con el default puesto.

## 5. TDD

1. El workdir por defecto no es el home.
2. Elegir el home no persiste la confianza; el siguiente arranque vuelve a
   preguntar.
3. Una escritura fuera del workdir sigue rechazándose (no-regresión).
4. Un 429 se reintenta antes de bajar de peldaño, y respeta `Retry-After`.
5. Agotado el reintento, el mensaje dice límite de tasa y NO "sin proveedor".
6. El reintento se ve mientras ocurre.
7. Desbordar la ventana deja una nota, no un hueco.
8. La nota conserva la primera petición del usuario.
9. La nota se identifica como resumen.

## 6. Fuera de alcance

- Un sandbox de sistema operativo. Nuestro límite es `PathValidator` más el
  gate de aprobaciones; cambiar eso es otra wave.
- Abrir las lecturas fuera del workdir con aprobación por ruta. Sería aflojar
  para parecernos, y hoy somos más estrictos.
- Reglas de permiso persistentes por comando.

## 7. Fuentes

- Claude Code — *Configure permissions*: diálogo de confianza como puerta;
  escritura confinada al workdir; lectura fuera con aprobación por ruta;
  confianza de `$HOME` solo de sesión y sin escribir a disco.
- Codex — *Agent approvals & security*: sandbox y aprobaciones como ejes
  distintos; el workspace es el límite.
- Anthropic — *Effective context engineering for AI agents*: compactación
  fiel; el contexto como recurso finito con rendimientos decrecientes.
- Código: `CompanionMain.swift:68`, `WorkdirPreference.isAllowed`,
  `ChatSSEAttempt.swift:103`, `ChatViewModel.windowedTurns()`.
