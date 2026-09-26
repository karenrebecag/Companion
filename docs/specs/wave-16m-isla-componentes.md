# Wave 16m — Los componentes de la isla como Incredible

**Estado: BORRADOR (2026-09-25), esperando aprobación.** Karen: "que hay de los componentes de la
ui de notch? nos faltan muchos componentes, sobretodo de display de datos, estados, archivos
adjuntos, etc".

Evidencia: `docs/research/incredible-isla-componentes.md` (medidas de su CSS del overlay).
Base: 16l (tinta de la isla, chip de referencia, piezas base).

## 1. Principio

Cada componente entra **con su dato**, no como maqueta. Lo que no tenga de dónde leer se
construye solo si otra sesión de esta misma wave le da el dato; si no, se queda fuera y se
dice. (En 16l quedaron tres piezas sin conectar; esta wave las conecta o las borra.)

## 2. Sesiones

| Sesión | Qué | De dónde sale el dato |
|---|---|---|
| 16m-1 | **Respuesta rica en la isla**: popup `ovx` con títulos, párrafo, lista, tabla, callout, código (copiar, plegar), código en línea, clave-valor, chip de archivo, cita, tareas, enlace | La respuesta del turno ya existe como markdown; hoy solo llega su título a la tarjeta. Se reutiliza el parser de `MarkdownView` (sin tocar ese archivo, que es de 16j): una vista nueva pinta los mismos bloques con la tinta `ovx` |
| 16m-2 | **Estados**: transcripción viva (72 %) → fija (94 %), carrete de apps tocadas, tarjeta de ejecución con pasos (runcard) y checklist para trabajos largos, barras de agentes | `partial`, `targets`, `job(goal, steps)` y los eventos del ejecutor, que ya están en la proyección de la sesión |
| 16m-3 | **Adjuntos en la isla**: tarjetas 84 × 102 con vista previa, extensión y quitar; pila de capturas con contador; zona para soltar sobre el notch; el clip adjunta en la isla en vez de abrir la ventana | Los adjuntos del chat (`ChatViewModelAttach`) pasan a compartirse con la isla |
| 16m-4 | **Dictado y avisos**: tarjeta de resultado de dictado (copiar / ocultar); avisos del sistema con la rejilla de Incredible (permiso, actualización, límite de la clave, diagnóstico) | Dictado 12e; fallos de voz y permisos que ya produce `VoiceFailureMapping` |

Fuera por ahora, con motivo:
- **Gráficas y diagramas (Mermaid)**: necesitan una librería de dibujo o un motor web; es una
  dependencia nueva y va en su propia decisión.
- **Pregunta con opciones** (`AnswerOption` de 16l): Companion no pregunta con opciones. Entra
  cuando 16h lo decida; si no, se borra la pieza.
- **Menciones (@) y subida a la nube**: no hay contactos ni subida en Companion.
- **Comentarios (modal)**: ya existe el enlace de feedback del menú.

## 3. TDD

Cada sesión fija sus medidas en un test (valores de la investigación) y la lógica que alimenta
la vista (qué bloque sale de qué markdown, qué estado sale de qué evento) con tests de
proyección, antes de pintar. Verificación visual con snapshots comparados con capturas de
Incredible en el mismo estado.

## 4. Riesgos

- 16m-1 es la más grande: la isla crece a un popup de 580 que tapa contenido. Se abre al pedirlo
  ("Ver") o cuando la respuesta tiene bloques, nunca por una frase corta.
- 16m-3 cambia un flujo (el clip abre la ventana): decisión de producto, se confirma antes.
- `IslandView` ya tiene 554 líneas: cada pieza va en su archivo.

## 5. Decisiones para firmar

- **D1**: ¿el clip adjunta en la isla (como Incredible) o sigue abriendo la ventana?
- **D2**: ¿se abre el popup rico solo con "Ver" o también automáticamente si la respuesta trae
  una tabla, código o lista?
- **D3**: gráficas y diagramas: ¿las dejamos fuera o abrimos la decisión de dependencia?
