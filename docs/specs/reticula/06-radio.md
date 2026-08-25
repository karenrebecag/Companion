# R-06 — Radio

**Estado: BORRADOR.** Capa: lenguaje. Depende de: 01-05.
Decision tomada por Karen (2026-08-24): **opcion C, hibrido por capa**.

## Objetivo

Fijar el filo del producto. Todo lo demas en este programa sale de una
transformacion con numeros; esto no salio de ahi. El radio es el rasgo mas
visible del lenguaje de OSMO y adoptarlo o no fue eleccion, no calculo.

El filo va donde vive la marca; lo redondo, donde toca la geometria del
sistema operativo.

## Referencia

OSMO `css/main.css` — el sistema de forma es **binario**:

```css
.button                       { border-radius: 0.125em; }   /* 2px @ root 16 */
.button[data-shape="round"]   { border-radius: 3em; }       /* 48px, pildora */
.tag[data-shape="round"]      { border-radius: 100em; }
```

No hay ningun radio intermedio en todo el sistema. O casi cuadrado, o
pildora. Eso es lo que hace que OSMO se lea tecnico y filoso.

Estado medido hoy — cinco escalones, cuatro intermedios, 47 call sites en 17
archivos:

| token | valor | usos |
|---|---|---|
| `Radius.sm` | 4 | 2 |
| `Radius.md` | 8 | **23** |
| `Radius.lg` | 12 | 13 |
| `Radius.xl` | 16 | 9 |
| `Radius.full` | 100 | **0** |

Por `mu_r`, el radio de OSMO seria `0.125 x 13 = 1.6 → 2`.

## La decision, y por que no fue A

Registrado para que el trade no se rehaga por accidente.

macOS no es una pagina. La esquina de una ventana de macOS es de ~10-11 pt, y
los sheets, menus y popovers del sistema son igual de redondos. Un boton de
2 pt dentro de una ventana de 11 pt no lee "filoso": lee inconsistente. OSMO
no tiene esa restriccion porque una pagina web no esta metida dentro del
chrome de nadie.

Las tres opciones sobre la mesa fueron:

- **A — filo de OSMO.** `sharp = 2` y pildora. El lenguaje sin diluir, y el
  cambio mas visible del programa. Descartada por la friccion con el chrome.
- **B — statu quo derivado.** Conservar los cinco escalones y solo limpiar.
  Diff minimo, pero no adopta nada: el producto sigue leyendose macOS
  generico. Descartada.
- **C — hibrido por capa.** Elegida.

Ganancia lateral de C que A no da: el contraste de forma entre control y
panel se vuelve **un canal mas de jerarquia**, que es exactamente lo que el
presupuesto de canales del `README` pide cuando el canal de tamano se agota.

## Archivos

- `Sources/CompanionUI/TokensChoices.swift` (enum `Radius`)
- Los 17 archivos de call sites, en cuatro tandas (abajo)
- `Tests/CompanionTests/ChatThreadTests.swift`

## Contrato

```swift
/// Tres papeles, no cinco tallas. El filo distingue al control del panel:
/// es jerarquia de forma, no decoracion.
public enum Radius {
    /// Controles: boton, campo, chip, tarjeta seleccionable.
    public static let sharp: CGFloat = 4
    /// Lo que abuta el chrome de macOS: hoja, dropdown, popover, burbuja.
    public static let panel: CGFloat = 12
    /// Pildora.
    public static let full: CGFloat = 100
}
```

Regla de asignacion, para que no se decida call site por call site:

- **Lo que el usuario pulsa** → `sharp`.
- **Lo que flota sobre el contenido** → `panel`.
- **Lo que es un interruptor o una etiqueta** → `Capsule()`, que ya se usa.

4 y no 2: filoso para macOS sin verse roto junto a una ventana de 11.

### Tandas

Maximo 5 archivos, veredicto visual entre tandas. Agrupadas por capa para
que cada una se pueda juzgar como una decision, no como un diff.

| # | Capa | Archivos | Sites |
|---|---|---|---|
| 1 | Controles → `sharp` | `Controls`, `Pressable`, `ShortcutCaptureField`, `ChatInputView`, `SettingsAppPane` | 16 |
| 2 | Paneles y chrome → `panel` | `CompanionRootView`, `SettingsView`, `HeaderView`, `Dropdown`, `Toasts` | 16 |
| 3 | Tarjetas de contenido | `AttachmentViews`, `GalleryCard`, `MapCard`, `SourcesCard`, `JobCardView` | 13 |
| 4 | Hilo | `MarkdownView`, `ThreadView` + test | 2 |

En la tanda 2, `SettingsView` y `Dropdown` reparten: el contenedor va a
`panel`, las filas y tabs de adentro a `sharp`. Es la tanda que mejor enseña
si el contraste de forma funciona.

## Portar

- El principio de OSMO: **pocos valores, cada uno con un papel**, ninguno "un
  poco mas redondo que el otro". Tres en vez de dos porque hay una capa mas
  que en la web: el chrome del sistema.

## Fuera

- `sharp = 2`. Decidido: 4.
- Tocar `Capsule()`. Ya se usa donde va pildora y esta bien.
- Radios del `Orb`, del `Halftone` y de las miniaturas de imagen: son
  textura y recorte de medio, no forma de control.
- Mezclar con R-04. El estado seleccionado ya quedo resuelto sin tocar forma.

## Reescribir

- `Radius`: cinco tokens por talla → tres por papel. `sm` / `md` / `lg` / `xl`
  desaparecen; sin alias, como en R-01.
- Los 47 call sites, por tanda, aplicando la regla de asignacion. No se
  decide uno por uno: si un sitio no cae claro en control o panel, es que la
  vista no tiene clara su capa y eso se anota como hallazgo.
- `ChatThreadTests.swift:29` espera `ChatIdle.bubbleRadius == Radius.xl`. La
  burbuja es panel: pasa a `Radius.panel`.

## Hallazgos

- `Radius.full` tiene **cero usos**: el codigo usa `Capsule()` directamente.
  El token mentia sobre el sistema. Se conserva el nombre en el contrato
  porque el papel existe, pero si al terminar sigue sin usarse, se borra.
- `Radius.md` (8) concentra 23 de 47 usos y es el valor que desaparece: es el
  "un poco redondo" que hacia que el producto no tuviera filo ni suavidad.
  Es donde se va a notar el cambio.
- `AttachmentViews` usa `lg` siete veces y `sm` una — un solo archivo con dos
  idiomas de forma. Revisar al hacer la tanda 3: probablemente son control y
  contenedor mezclados.
- La tanda 4 es de dos sitios pero toca la burbuja de chat, que es lo que mas
  se ve del producto. Va sola a proposito.

## Done

Con las dos apps abiertas: los controles de Companion tienen filo y los
paneles acompañan la esquina de la ventana. El contraste entre un boton y la
hoja que lo contiene se **ve**, y se lee como decision, no como descuido.

Ningun radio intermedio sobrevive: contar los valores distintos en pantalla y
que sean tres.

Si un boton dentro de un dropdown tiene el mismo radio que el dropdown, no
esta.
