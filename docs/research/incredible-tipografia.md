# Incredible — tipografía, espaciado, retícula y escala (cualitativo)

Fecha: 2026-09-25. Fuente: inspección en solo lectura de Incredible 0.2.36 (Tauri + Vite + Tailwind v4).
Este brief ya no lleva tokens, nombres de hojas de estilo ni valores tomados del binario: la tabla completa
de medidas está solo en la referencia local. Aquí quedan las observaciones en palabras.

La app tiene hojas separadas por ventana: la principal (chat y ajustes), la isla del notch, la bienvenida
de primer arranque y unos widgets (switch y select) (referencia local).

## 1. Familias

| Contexto | Sans | Mono |
|---|---|---|
| Ventana principal | **fuente del sistema** (SF Pro) | Geist Mono |
| Isla (overlay) | **Geist Sans**, cuerpo pequeño | Geist Mono |
| Bienvenida | Geist | monoespaciada del sistema (SF Mono) |

- Geist y Geist Mono se cargan como fuentes variables (todo el rango de pesos), sin itálicas.
- Montserrat no aparece en ninguna hoja.
- Consecuencia para Companion: la wave 16c puso Geist en toda la app. Incredible solo la usa en
  la isla y en la bienvenida; la ventana principal habla en SF Pro.

## 2. Pesos

Cuatro pesos con nombre: normal, medio, semibold y bold (referencia local).

## 3. Escala tipográfica (por papel)

- Diez papeles con nombre, desde micro hasta display; cada uno lleva su propio interlineado, más apretado
  cuanto más grande es el texto (referencia local para los valores).
- El cuerpo de la ventana principal y de la isla ronda el rango de trece a catorce píxeles; los títulos de
  sección, diálogo y banner suben de forma gradual y la página usa un título grande.
- Solo el display es fluido: crece con el ancho de la ventana dentro de un rango acotado.
- Hay interlineados y trackings con nombre (apretado y amplio), y varios trackings sueltos; los positivos
  se usan en etiquetas en mayúsculas.
- Color de texto en claro: cuatro niveles (primario, secundario, atenuado y tenue) en grises neutros.

## 4. Escala del usuario (scaling)

- **No hay control de tamaño de texto.** Ni en la interfaz ni en la configuración aparece un
  ajuste de tamaño. El binario lleva un comando de zoom del webview de Tauri, pero ningún fragmento
  del frontend lo llama.
- Todo va en píxeles fijos. Lo único fluido es el display.
- Consecuencia: el `TypeScale` de Companion (pasos ×1.08, de −1 a +3) no tiene equivalente.

## 5. Espaciado

- Base de 4 px (Tailwind); la ventana principal usa sobre todo múltiplos pequeños de esa base y pocos valores grandes.
- Cuatro espaciados semánticos: margen lateral de página, separación entre secciones, cierre de tarjeta y
  sangría de filas anidadas (referencia local).
- En la isla los paddings y gaps son más apretados.

## 6. Retícula y contenedores

- Escala de contenedores de ancho creciente, con una columna de contenido propia cercana a los 960 px (referencia local).
- Se repiten algunos anchos fijos para paneles y barras laterales.

## 7. Radios

- Escala de diez radios, desde esquinas casi rectas hasta paneles muy redondeados; hay nombres para
  badge, control, tarjeta, diálogo y panel (referencia local).

## 8. Medidas de controles

Switch en dos tamaños y select compacto con texto pequeño (referencia local para las medidas).

## 9. Diferencias con Companion hoy

| Eje | Companion | Incredible |
|---|---|---|
| Sans en ventana principal | Geist | SF Pro (sistema) |
| Sans en la isla | Geist | Geist Sans |
| Escalones | 11 · 13 · 16 · 22 · 29 | más escalones intermedios (referencia local) |
| Interlineado | solo `bodyLead` 0.3 y `codeLead` 0.15 | uno por escalón |
| Tracking tight | −0.02em | algo más apretado |
| Escala del usuario | ×1.08 por paso, −1…+3 | ninguna |
| Espaciado | 0, 4, 8, 12, 16, 20, 24, 32 | base 4 con más pasos intermedios y cuatro semánticos |
| Radios | 4, 8, 12, 16, 20 | más pasos y radios más grandes |
| Columna | `Container.sheet` 520 | columna de contenido bastante más ancha |
