# Reticula — transformacion del sistema de OSMO

**Estado: BORRADOR.** Programa hermano de `../ds/`, no continuacion.

`ds/` porta el prototipo componente a componente. Este programa corrige los
**fundamentos** — escala tipografica, tier de seccion, retitcula de columna —
derivandolos del sistema de OSMO por transformacion, no por copia.

Mismo despacho que `ds/`: Karen aprueba UN spec y se construye ese. Sin las
tres listas (Portar / Fuera / Reescribir) un spec sigue BORRADOR.

## Por que existe

Auditoria 2026-08-24. Tres hechos medidos:

1. `TypeScale.apply` = `max(12, size - 3)`. Con `delta = 0`, los tokens `xs`
   (10.24) y `sm` (12.8) caen ambos al piso: **siete estilos de texto
   renderizan identicos a 12 pt**. En el modulo de Ajustes, 35 de 39 textos
   salen al mismo tamano. La escala documentada solo se cumple con
   `delta = +3`.
2. `gates.sh` prohibe `.padding(4)` pero no `.frame(width:)` ni la aritmetica
   sobre tokens. `Space.x1` se volvio un multiplicador: `Space.x1 * 52` = 208.
   La rampa efectiva en pantalla tiene 27 valores distintos.
3. No hay tier de seccion. El salto mayor disponible (32) es 2.7x el gap
   interno (12). En OSMO esa razon es 12.5x. Por eso un eyebrow no se lee
   como encabezado.

## La transformacion

OSMO y Companion tienen la misma figura de container:

```
OSMO       clamp(992px,  100vw, 1920px)  ideal 1440   0.689 · 1 · 1.333
Companion  clamp(440pt, ancho,  680pt)   design 560   0.786 · 1 · 1.214
```

Pero **son dos mapas, no una homotecia**:

```
mu_c = 560/1440 = 0.389    container   reparte el plano
mu_r =  13/  16 = 0.8125   root        dimensiona el texto
mu_r / mu_c = 2.09
```

En OSMO los dos mapas coinciden — `--size-font: container/90` hace que el
root sea funcion del container, y por eso puede escribirlo todo en `em`. Al
clavar el root a `NSFont.systemFontSize` (13, constante de plataforma) los
mapas se separan y cada magnitud declara a cual pertenece:

| sigue mu_r (0.8125) | sigue mu_c (0.389) |
|---|---|
| tamanos de texto | padding de container |
| gaps entre elementos | quiebres de seccion |
| alturas de boton / input / fila | dimensiones de panel |
| radios | posicion en el plano |

Lo dimensionado por su contenido escala con el root. Lo que reparte el
lienzo escala con el container.

Ancho del container en ems: OSMO `1440/16 = 90`; Companion `560/13 = 43`
(0.478x). Companion no es "OSMO mas chico": cabe la mitad de veces la
unidad, asi que la densidad sube por construccion.

## Resultado de cada capa

**Tipografia.** Se descarta la banda display de OSMO (62..150 px) y se
conserva la banda UI (11..30). El rango disponible en Companion es 11..29 —
practicamente el mismo, porque el piso es el mismo ojo humano. Pero el body
se mueve de 16 a 13, y eso cambia la estructura:

```
                debajo del body    encima del body
OSMO  body 16     16/11 = 1.45x      30/16 = 1.88x
Comp. body 13     13/11 = 1.18x      29/13 = 2.23x
```

**En una reticula chica no se diferencia hacia abajo, se diferencia hacia
arriba.** El eyebrow de OSMO puede ser pequeno porque su body es grande.
Companion copio "eyebrow = pequeno" con body 13 y los siete estilos que
bajan se estrellan contra el piso. Ese es el mecanismo exacto del bug.

Ajustando la forma de OSMO (1.25 → 1.5 → 1.333) al rango 2.23x de arriba:
exponente log(2.23)/log(2.5) = **0.875**.

```
11 --1.18--> 13 --1.22--> 16 --1.42--> 22 --1.29--> 29
```

Cae sobre sizes nativos de macOS (11 subheadline, 13 system, 22 title1): la
derivacion desde OSMO y la convencion de plataforma coinciden.

**Gaps.** Los `--gap-*` de OSMO estan en `em`, van por mu_r (x13):
0.5 → 6.5, 0.75 → 9.75, 1 → 13, 1.25 → 16.25, 1.5 → 19.5, 1.875 → 24.4,
2.5 → 32.5. Redondeados a la reticula de 4: **8/12/16/20/24/32**.
Eso ya es `Space.x2..x8`. **La escala de espaciado esta bien de nacimiento y
no se toca.**

**Seccion.** Los `--padding-*` reparten el lienzo, van por mu_c (x0.389):
60 → 24, 80 → 32, 120 → 48, 160 → 64, 200 → 80. Tier nuevo, tres escalones
usables en una ventana de 840: **24 / 32 / 48**.

**Columnas.** Las fracciones de OSMO son adimensionales, transfieren 1:1:
`1.0 / 0.825 / 0.65 / 0.5`.

**Alturas de control**, por mu_r: `--btn-height` 2.5em → **32**,
`--input-height` 3em → **40**, `--nav-bar-height` 4.625em → **60**.

## El presupuesto de canales

El canal "tamano" pierde la mayor parte de su rango:

```
OSMO       150/11 = 13.6x   ln = 2.61
Companion   29/11 =  2.64x  ln = 0.97   → queda el 37%
```

El 63% restante hay que recuperarlo de otros canales. Companion usa hoy 2.5
de 7:

| canal | OSMO | Companion hoy |
|---|---|---|
| peso | apenas (wght 460) | **sin usar**, todo regular |
| familia | 3 roles (XH / VF / Mono) | mono solo en eyebrow, mismo tamano → no registra |
| caja | uppercase en eyebrow | igual |
| tracking | -0.06 → 0 por escalon | 3 de 7 tokens usados |
| espacio arriba | tier de seccion completo | **inexistente** |
| filete | `border-top` en h3 | solo en header de Ajustes |
| color | binario | binario |

Cuando el unico canal activo es el color, dos grises es toda la jerarquia
que existe. Por eso Ajustes se ve plano.

## Lo que NO transfiere

- **La ley fluida.** OSMO escala el root con el viewport. En una app nativa
  el texto no encoge cuando el usuario achica la ventana: misma pantalla,
  misma distancia. El root queda fijo y reflota el layout.
- **La banda display.** 62..150 px no cabe en 560 pt.
- **El radio binario.** OSMO es 0.125em (≈ cuadrado) o pildora completa, sin
  nada en medio. Eso no se pudo adoptar tal cual: la esquina de una ventana
  de macOS es de ~11 pt y un boton de 2 dentro de ella lee inconsistente, no
  filoso. R-06 lo resuelve con tres papeles —`sharp` 4, `panel` 12, `full`—
  y convierte el contraste de forma entre control y panel en un canal mas de
  jerarquia. Fue decision, no derivacion.

## Secuencia

| # | Spec | Capa | Que cambia en la foto |
|---|---|---|---|
| 01 | [Escala tipografica](01-escala-tipografica.md) | fundamento | Toda la jerarquia de texto |
| 02 | [Tier de seccion](02-tier-seccion.md) | fundamento | Respiro entre grupos, shell |
| 03 | [Reticula de Ajustes](03-reticula-ajustes.md) | organismo | Columna alineada, filas iguales |
| 04 | [Estado seleccionado](04-estado-seleccionado.md) | atomo | Un solo idioma de seleccion |
| 05 | [Contrato de reticula](05-gate-reticula.md) | proceso | **CONSTRUIDO** — ratchet sobre 86 infracciones |
| 06 | [Radio](06-radio.md) | lenguaje | Filo del producto — 4 / 12 / pildora |
| 07 | [Widgets de chat](07-widgets-chat.md) | organismo | Las 3 tarjetas del modelo, al sistema |

01 es la de mayor impacto y la mas aislada —dos archivos de tokens y sus
tests, ninguna vista cambia—: se despacha primero.

06 tiene la decision de lenguaje ya tomada (hibrido por capa, 2026-08-24) y
va al final porque toca 17 archivos en cuatro tandas.
