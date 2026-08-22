# Wave 9 — Que la use alguien que no seas tú

**Estado: BORRADOR.** Karen aprueba pieza por pieza; sin APROBADO no se
codea. Las dos decisiones que bifurcaban el trabajo ya están tomadas
(2026-08-22) y sus consecuencias están integradas abajo.

## Por qué esta wave

El hito de Wave 5 dice "distribuible open source" y está marcado CERRADO,
pero nadie que no sea Karen ha abierto la app. Medido hoy:

| Hecho | Estado real |
|---|---|
| README, ARCHITECTURE, CONTRIBUTING | en inglés |
| La app | solo español, ~60 literales de UI |
| Los prompts (charla, especialista, tools) | fijan el idioma de las RESPUESTAS: hoy siempre español |
| El producto en el Finder | "Companion Next", `com.karen.companion.next` |
| Releases publicados | ninguno; `UpdateChecker` apunta a un repo sin releases |
| `Build.version` | 0.8.1, con el CHANGELOG ya en 0.9.0 |
| Instalar sin compilar | el README no lo explica: no hay ruta para quien solo descarga |

Ninguna de esas es una falla de craft. Son las costuras que solo se ven
cuando la app sale de la Mac donde nació.

## Decisiones tomadas (2026-08-22)

1. **Idioma fuente: inglés.** El español pasa a ser traducción. Consecuencia
   que no se puede maquillar: **las ~60 cadenas de UI se reescriben en
   inglés** — no se "traducen desde" el español, el inglés se convierte en
   el original y el español en el archivo que lo sigue. El riesgo real es de
   voz, no de mecánica: el copy español de este repo tiene tono propio
   ("Lista cuando tú lo estés", "Encargo listo") y una traducción inversa
   descuidada lo aplana. Cada cadena se escribe en inglés con la misma
   intención, y el español existente se conserva tal cual como su
   traducción — no se regenera.
2. **Sin cuenta de Apple Developer.** No hay notarización ni Developer ID:
   el release sale **ad-hoc**, y eso deja de ser el escenario B para ser
   EL escenario. Consecuencias reales, no cosméticas:
   - Gatekeeper bloquea la app la primera vez. En macOS 14 el clic derecho →
     Abrir todavía sirve; **en macOS 15+ ya no**: hay que ir a Ajustes del
     Sistema → Privacidad y seguridad → "Abrir de todos modos". El README
     tiene que decir las dos, o la mitad de quien descargue se queda fuera.
   - `docs/DISTRIBUTION.md` describe hoy tres niveles de confianza como si
     el camino fuera subir de nivel. Se reescribe diciendo dónde está el
     proyecto y por qué, sin prometer una notarización que no existe.
   - Cuando exista la cuenta, `scripts/release.sh` ya la usa solo: no hay
     que rehacer nada, solo guardar credenciales.

## Piezas

```
9-1 idioma ──┐
9-2 primer arranque ──┼─→ 9-3 identidad ─→ 9-4 release
9-5 (docs, paralelo) ─┘
```

---

## 9-1 La app habla el idioma de quien la usa

Hoy la UI es española y, peor, **los prompts también**: `ChatPrompt.system`,
`Escalation.voicePreamble` ("Responde en maximo 2 frases, en espanol"),
`executorRole` y las descripciones de `ToolSpec` hacen que un usuario en
inglés reciba respuestas en español de un asistente que además le habla de
"encargos". El idioma no es una capa de barniz sobre la UI: atraviesa hasta
lo que el modelo contesta.

### Dos superficies, dos mecanismos

| Superficie | Dónde vive | Mecanismo |
|---|---|---|
| Copy de UI (~60 literales) | `ChatCopy`, `VoiceCopy`, `JobCardCopy`, `ChatIdle`, paneles de Ajustes | String Catalog (`Localizable.xcstrings`) en recursos de CompanionUI, vía `Bundle.module`. Nativo, cero dependencias. **Cadena fuente en inglés**; el español actual entra como su traducción, palabra por palabra, sin regenerar |
| Prompts al modelo | Core: `ChatPrompt`, `Escalation`, `ToolSpec` | **No** catálogo: Core es puro y no tiene bundle. `Config.language` entra como parámetro y el constructor del prompt elige variante. Puro y testeable |
| Logs (52 literales) | `Log.app(...)` | Se pasan a inglés y ya: son para quien depura, y el código de este repo es inglés (CLAUDE.md) |

### Restricciones

- El idioma sale del sistema (`Locale`) y se puede forzar en Ajustes; **toda
  lectura del entorno pasa por `Config`**, como el resto del repo.
- La voz: la instrucción de idioma viaja en el `session.update`, y cambiar
  de idioma a mitad de sesión NO reabre la sesión (el contrato de Realtime
  no lo pide). Aplica en la siguiente.
- Nada de traducir el ledger, los ADR ni los specs: docs de trabajo siguen
  en español por política declarada.

### TDD

1. `AppLanguage.resolved(from:)`: locale es-MX → es; en-US → en; fr-FR → en
   (fallback), y la preferencia explícita gana sobre el sistema.
2. `ChatPrompt.system(language: .en)` no contiene una sola palabra española;
   idem `Escalation.executorRole` y `voicePreamble`.
3. Cada clave del catálogo tiene las dos traducciones (test que lee el
   catálogo y falla si falta una). Una cadena inglesa sin español es un
   fallo, no un aviso: media app en cada idioma es peor que una monolingüe.
4. `ToolSpec.delegate.description` cambia con el idioma y sigue siendo JSON
   válido en `encodeRealtime`.

### Gate nuevo

Un literal de UI fuera de la capa de copy es un error del gate estático —
la misma disciplina que ya existe con los literales de spacing. Sin el gate,
la segunda pantalla nueva vuelve a nacer monolingüe.

---

## 9-2 El primer arranque de un desconocido

Un usuario nuevo no tiene clave, ni CLIs, ni permisos concedidos, ni
`~/.hermes`, ni la carpeta de trabajo que tú tienes. La app se diseñó para
degradar (ADR 001), pero **nunca se ha ejecutado ese camino completo**.

### Recorrido a probar, en orden

1. Cuenta de macOS limpia (o usuario nuevo): abrir el DMG, arrastrar, abrir.
2. Onboarding sin clave → con clave inválida → con clave buena. El error de
   clave inválida ya se valida contra la API; verificar que se lee.
3. Voz: prompt de micrófono y de reconocimiento de voz **bajo la firma del
   release** (no la de desarrollo).
4. Delegación sin ningún CLI instalado: el catálogo queda en el nativo y el
   selector no promete lo que no existe.
5. La carpeta de trabajo por defecto (hoy, el home) y su diálogo de permisos.
6. Cerrar y reabrir: conversaciones, adjuntos, sesión del especialista.

Lo que se rompa se arregla con test en rojo primero. El recorrido se escribe
en `docs/FIRST-RUN.md` (inglés, público): qué pide la app, por qué, y qué
pasa si dices que no a cada permiso.

### Riesgo conocido, del ledger

Las claves importadas desde la terminal piden contraseña en cada arranque;
cuando la usuaria la pega en el onboarding no ocurre porque la app es dueña
del item. Con **firma de release** (identidad distinta a "Companion Dev")
eso hay que volver a comprobarlo: es exactamente el tipo de cicatriz que
solo aparece en la máquina de otro.

---

## 9-3 Cómo se llama el producto

`Companion Next` y `com.karen.companion.next` son andamio: nacieron para
que LaunchServices no abriera el prototipo al pedir el rebuild (ledger).
Para alguien que descarga, el producto es **Companion**.

- **Portar**: el aislamiento. Dos apps con el mismo bundle id en una Mac es
  el bug que el ledger ya documentó.
- **Fuera**: renombrar a secas y rezar. Si el release toma
  `com.karen.companion`, en la Mac de Karen colisiona con el prototipo
  instalado como item de login.
- **Reescribir**: el id de release y el de desarrollo son distintos por
  configuración de `bundle.sh` (release → `com.karen.companion`, dev →
  `.next`), y el prototipo se desinstala de su Mac (`uninstall.sh` existe)
  como paso documentado del release, no como sorpresa.

Incluye el nombre visible, el icono, el nombre del archivo de log y la ruta
de Application Support (migrar lo que ya existe, no perderlo).

---

## 9-4 El primer release de verdad

Hoy `scripts/release.sh` construye, firma si hay identidad y notariza si hay
credenciales; el repo no tiene ni un release publicado.

1. **Versión**: `Build.version` es la fuente única (`bundle.sh` la lee) pero
   quedó en 0.8.1 con el CHANGELOG en 0.9.0. Subirla es parte del ritual de
   cierre, no un paso suelto: si vuelve a driftar, el updater compara mal.
2. **Publicar**: tag + release en GitHub + DMG adjunto.
3. **Cerrar el círculo del updater**: `UpdateChecker` apunta a este repo, que
   hoy responde 404 a "latest release". Verificar que ese 404 es silencio
   absoluto (ADR 002) **y** que con un release publicado el aviso aparece.
   Es el único camino del repo que nunca pudo probarse de verdad.
4. **README con ruta de descarga**: hoy solo explica compilar. Añadir
   descargar → instalar → primer arranque, con las DOS instrucciones de
   Gatekeeper (macOS 14 y macOS 15+), porque el build es ad-hoc.
5. **`docs/DISTRIBUTION.md` honesto**: la tabla de tres niveles se reescribe
   para decir dónde está el proyecto hoy y qué costaría subir, sin vender
   una notarización que nadie compró.

---

## 9-5 El renglón que quedó de la Wave 8

`docs/DISTRIBUTION.md:55` sigue diciendo que el proyecto "ships with zero
external dependencies". La corrección de 8-4 tocó NOTICE, ROADMAP y ADR 002
y se saltó este. Cero código; cabe en el mismo commit que 9-4.

---

## Fuera de esta wave, por decisión

- **Notarizar**: descartado para esta wave por decisión (sin cuenta). El
  script ya lo soporta el día que exista; la wave entrega el DMG ad-hoc y
  las instrucciones correctas para abrirlo.
- **WebRTC**, **MCP en el NativeExecutor** y **SpeechAnalyzer**: siguen en
  post-v1 (ROADMAP).
- **Programa DS 01-12**: flujo propio de aprobación atómica.
- Más idiomas que es/en: el mecanismo queda listo, la traducción no se
  inventa sin alguien que hable el idioma.

## Definición de done

Alguien que no es Karen descarga el DMG, sortea Gatekeeper **siguiendo el
README y no adivinando**, pega su clave de OpenAI, habla, delega, y la app
le responde **en su idioma** sin haber leído una sola línea de este
repositorio. Gates verdes, y ningún doc público que el `git ls-files`
desmienta.
