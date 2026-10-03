# Reference Brief: reconstruir Ajustes como la hoja real de Incredible 0.2.36 (hoja centrada, rail con busqueda, mapa de paginas, aviso de guardado y sub-dialogos) en lugar del panel flotante WIN-5

Slug: ajustes-hoja-incredible | Nivel: standard | Fecha: 2026-10-03 | Estado: APROBADO
Versiones: swift-tools=6.2
Verificador: research-verifier 2026-10-03 ESCALATE

Origen: el plan S0-S4 aprobado por el orquestador (`.b6-backups/plan-ajustes-s1-s4.md`, fuera del repo) parte de un hallazgo: el panel flotante de WIN-5 copio el panel de desarrollo del primer arranque de Incredible, no su hoja de Ajustes. Este brief es el S0 del plan: fija el estandar antes de que S1-S4 toquen codigo. Directiva de Karen que lo gobierna: Incredible es el piso minimo de Companion y toda decision que Incredible ya resuelve se replica tal cual, sin escalarla.

Alcance: QUE hoja, rail, paginas, aviso y dialogos tiene la hoja de Ajustes de Incredible y COMO los adopta Companion en SwiftUI. Nada de lo que Incredible tiene se descarta: lo que Companion no puede hacer hoy queda en la lista GAPS de la seccion 1. Se replica el comportamiento, nunca el codigo.

Evidencia de Incredible de esta corrida: los valores extraidos del binario (medidas, nombres de clase, textos, tiempos) no se publican en este repo; viven en la referencia local, citada como [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]. Cada hecho de ese archivo lleva un id E1..E40; este brief los cita como "(E7)" y, donde hace falta un numero, dice "(valor en la referencia local)". Se reusan sin rehacer los briefs `isla-motion-incredible` (curvas y duraciones con tokens SwiftUI) e `isla-maquetacion-incredible`.

## 1. Pregunta y decisiones abiertas

Pregunta: como se reconstruyen los Ajustes de Companion para replicar la hoja real de Incredible 0.2.36, que sustituye al panel flotante de WIN-5, y que hace Companion con cada cosa de esa hoja que hoy no puede cumplir.

La recomendacion de las cuatro decisiones es igualar a Incredible (directiva de Karen, [KAREN:chat 2026-10-02]); el detalle y las opciones descartadas estan en la seccion 5.

- S1. Hoja y rail. Una hoja modal centrada sobre un scrim, con rail de busqueda y navegacion a la izquierda y el contenido a la derecha; reemplaza `SettingsPanelHost`, `SettingsPanelModel` y la pildora plegada.
- S2. Mapa de paginas. Seis paginas en el primer grupo y cuatro en el grupo de la cuenta, con alias para los ids viejos y un indice de busqueda por pagina y por fila.
- S3. Aviso de guardado. Un aviso corto abajo a la derecha de la hoja, sin animacion, que solo disparan los setters que Incredible envuelve; error en linea con reversion.
- S4. Sub-dialogos. Un popup compacto con titulo y sublinea para atajos, microfono, idiomas y permisos, y dialogos de alerta para borrar historial y reiniciar.

Decisiones que quedan para Karen (la referencia no las resuelve):

- KD1. Brillo de pantalla (resplandor de pantalla). Incredible guarda un ajuste de resplandor en su capa de datos, pero ninguna pagina lo pinta (E27). Recomendado: fila en Sistema > App.
- KD2. Apariencia y Tamano de texto. Incredible no tiene filas de ese tipo (E28). Recomendado: dentro de la pagina Cuenta.
- KD3. Alcance del reinicio. Incredible reinicia sesion, permisos, onboarding, ajustes y chats (E38). Resuelto por el orquestador el 2026-10-03 con la regla de Karen "si Incredible lo resuelve, se replica tal cual": el reinicio amplio de Incredible, en Sistema > Zona de peligro. Lo construye ATOM (G9), ya avisado.
- KD4. Dos guardados seguidos. Incredible no reinicia el temporizador del aviso (E30). Resuelto por el orquestador el 2026-10-03 con la misma regla: se copia tal cual, sin reiniciar el temporizador.

GAPS: nada de lo que Incredible tiene se descarta. Cada fila dice que hace Incredible, el estado de Companion y quien lo lleva. Una fila sin dueno es trabajo sin arrancar, no una decision de no hacerlo.

| # | Que hace Incredible | Estado en Companion | Dueno o trabajo en curso |
|---|---|---|---|
| G1 | Pagina de Contactos embebida (E22) | Sin pagina ni backend: el enum de paginas no la tiene (Sources/CompanionUI/Settings/SettingsInventory.swift:7) | Sin dueno |
| G2 | Miembros: solo con backend de organizaciones (E26) | Sin equivalente: Companion es local y no tiene organizaciones (SettingsInventory.swift:7) | Sin dueno |
| G3 | Facturacion y uso: solo con backend de organizaciones (E26) | Sin equivalente (SettingsInventory.swift:7) | Sin dueno |
| G4 | Potencia de pensamiento con dos niveles (E21) | Sin fila ni preferencia en el inventario (SettingsInventory.swift:46) | Sin dueno |
| G5 | Palabra de activacion con pausa de envio y frase de envio (E21) | Sin fila ni preferencia en el inventario (SettingsInventory.swift:46) | Sin dueno |
| G6 | Modo pasivo automatico: interruptor, activo de fabrica (E21) | La preferencia existe sin fila (Sources/CompanionUI/Voice/PassivePreference.swift:5) | Sesion Companion1 (b2b y P4); S2 reserva su lugar en la pagina de Companion y no pone una fila vacia |
| G7 | Uso del equipo (Compute Use) experimental (E21) | Sin fila ni preferencia en el inventario (SettingsInventory.swift:46) | Sin dueno |
| G8 | Capturas mientras se mantiene Fn (E21) | Sin fila ni preferencia en el inventario (SettingsInventory.swift:46) | Sin dueno |
| G9 | Reiniciar en este equipo: sesion, permisos, onboarding, ajustes y chats, con lista de lo que se borra y de lo que se conserva y palabra de confirmacion (E23, E38) | Sin fila; en construccion en otra rama | Sesion ATOM (ResetPermissionsRow autocontenida); S2 la coloca en Sistema > Zona de peligro; con el alcance amplio de Incredible (KD3) |
| G10 | Cambiar contrasena, cerrar sesion y borrar cuenta (E24) | Sin cuenta: la pagina Tu solo guarda nombre, foto y datos locales (Sources/CompanionUI/Settings/SettingsPages.swift:5) | Sin dueno |
| G11 | Datos y privacidad: como se manejan los datos, enviar datos de uso y diagnosticos, enviar ahora, aviso de consentimiento vencido, enlaces de confianza (E25) | Companion tiene su pagina de privacidad con contexto y llaves, sin esos controles (Sources/CompanionUI/Settings/SettingsAppPane.swift:7) | Sin dueno |
| G12 | Borrar historial de chats con confirmacion, borra chats y tareas (E23, E37) | El ajuste de Sistema borra adjuntos guardados, no chats (Sources/CompanionUI/Settings/SettingsView.swift:228); borrar el hilo vive en la isla y lo archiva (Sources/CompanionUI/Island/IslandView+Portal.swift:75) | Sin dueno; S4 solo mueve la confirmacion actual al dialogo de alerta |
| G13 | Volumen de la voz con "Escuchar", silenciar y deslizador (E20) | Sin fila en Ajustes; el deslizador de la isla es otro trabajo | Rama del deslizador de la isla; S2 pone la fila en General cuando exista el ajuste |
| G14 | Microfono con selector de dispositivo, medidor y prueba (E35) | Sin fila ni preferencia en el inventario (SettingsInventory.swift:46) | Sin dueno |
| G15 | Idioma de dictado: lista de idiomas con busqueda (E20, E35) | El selector de Companion es el idioma de la interfaz (Sources/CompanionUI/Settings/SettingsLanguageRow.swift:12) | Sin dueno |
| G16 | Idioma de habla de la voz (E21) | Sin fila; la pagina de voz solo elige la voz (Sources/CompanionUI/Settings/SettingsVoiceSection.swift:11) | Sin dueno |
| G17 | Voz con control Femenina/Masculina (E21) | Companion elige entre sus voces por nombre (SettingsVoiceSection.swift:26) | Sin dueno |
| G18 | Pagina Datos y privacidad y Cuenta tienen filas de equipo interno (E24) | Excluidas a proposito: son de uso interno de Incredible | No aplica |

## 2. Estado actual

- El panel de WIN-5 declara en su cabecera que copia el panel de desarrollo del primer arranque de Incredible [repo:Sources/CompanionUI/Settings/SettingsPanel.swift:4]
- El panel es un overlay flotante sin scrim: `blocksWindow` devuelve falso a proposito [repo:Sources/CompanionUI/Settings/SettingsPanel.swift:43]
- Tiene tres estados (normal, acoplado, plegado en pildora) y un modelo puro que calcula su marco [repo:Sources/CompanionUI/Settings/SettingsPanel.swift:36]
- Se pinta oscuro sin importar la apariencia de la app [repo:Sources/CompanionUI/Settings/SettingsPanel.swift:164]
- Monta `SettingsView` en el diseno compacto, sin barra lateral [repo:Sources/CompanionUI/Settings/SettingsPanel.swift:190]
- `SettingsView` ya tiene un diseno de hoja con barra lateral, que ningun host usa hoy [repo:Sources/CompanionUI/Settings/SettingsView.swift:67]
- Ese diseno de hoja es una barra lateral, una linea fina y la pagina, en una superficie redondeada con la X arriba a la derecha [repo:Sources/CompanionUI/Settings/SettingsView.swift:87]
- Las medidas de la hoja son propias de Companion: ancho maximo, alto maximo y ancho de barra lateral [repo:Sources/CompanionUI/Settings/SettingsView.swift:9]
- La barra lateral tiene el buscador arriba, dos grupos, un espaciador y la version abajo [repo:Sources/CompanionUI/Settings/SettingsView.swift:259]
- El buscador es una capsula con un campo de texto [repo:Sources/CompanionUI/Settings/SettingsView.swift:329]
- Los resultados muestran titulo y pagina en dos lineas, con un tope propio de resultados [repo:Sources/CompanionUI/Settings/SettingsView.swift:346]
- Elegir un resultado cambia de pagina, limpia el texto y enciende la fila por un momento [repo:Sources/CompanionUI/Settings/SettingsView.swift:186]
- La luz de la fila se lee de un valor de entorno y dura un tiempo fijo [repo:Sources/CompanionUI/Settings/SettingsView.swift:17]
- El host monta el panel como overlay y su comentario cita WIN-5 [repo:Sources/CompanionUI/Window/CompanionRootView.swift:188]
- El estado de apertura y de pagina vive en el root, junto al modelo del panel [repo:Sources/CompanionUI/Window/CompanionRootView.swift:21]
- Todas las entradas (menu, atajo, isla, tarjetas) abren Ajustes por la notificacion `companionOpenSettings` [repo:Sources/CompanionUI/Window/CompanionRootView.swift:225]
- Una entrada de Ajustes del menu trae primero la ventana principal y luego manda esa notificacion [repo:Sources/CompanionApp/CompanionMainWindow.swift:205]
- El menu de la isla hace lo mismo, de modo que la hoja siempre vive en la ventana principal [repo:Sources/CompanionUI/Island/IslandView+Portal.swift:57]
- Esc se resuelve en el root en cadena: aprobacion, menu desplegable, Ajustes [repo:Sources/CompanionUI/Window/CompanionRootView.swift:142]
- El buscador guarda su texto como estado privado de `SettingsView`, fuera del alcance del root [repo:Sources/CompanionUI/Settings/SettingsView.swift:31]
- `SettingsTab` tiene siete paginas y su valor crudo es un identificador que nombran la isla y los menus [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:4]
- Los dos grupos de la barra son [General, Voz, Vocabulario, Memoria] y [Tu, Privacidad, Sistema] [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:27]
- El inventario declara las opciones y los paneles que alimentan la busqueda [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:46]
- El buscador solo compara titulo y subtitulo con todas las palabras contenidas, sin palabras clave ni prefijos [repo:Sources/CompanionCore/Settings/SettingsSearch.swift:25]
- General agrupa tecla de hablar, tecla de dictado, idioma, Sonidos, Silenciar al hablar y Brillo de pantalla [repo:Sources/CompanionUI/Settings/HoldSettings.swift:83]
- Silenciar el sonido mientras hablas esta hoy en General, no en Sistema [repo:Sources/CompanionUI/Settings/HoldSettings.swift:113]
- Los interruptores escriben su preferencia directo, sin envoltorio de guardado ni aviso [repo:Sources/CompanionUI/Settings/HoldSettings.swift:130]
- Silenciar al hablar es una preferencia de UserDefaults apagada de fabrica que avisa por notificacion al cambiar [repo:Sources/CompanionUI/Settings/UserPreferences.swift:357]
- Sonidos es un solo interruptor que escribe dos preferencias [repo:Sources/CompanionUI/Settings/HoldSettings.swift:132]
- La pagina Sistema tiene version, repetir la bienvenida y adjuntos guardados [repo:Sources/CompanionUI/Settings/SettingsAppPane.swift:190]
- El borrado de adjuntos pide confirmacion con un velo de material difuminado y el scrim del sistema de diseno [repo:Sources/CompanionUI/Settings/SettingsView.swift:211]
- El scrim del sistema de diseno cambia con el esquema de color [repo:Sources/CompanionUI/DesignSystem/TokensChoices.swift:173]
- El modal de comentarios es el patron de modal centrado de la app: velo difuminado, scrim, sombra de hoja [repo:Sources/CompanionUI/Window/CompanionRootView.swift:302]
- Ese modal vive en la ventana principal porque el panel de la isla no puede alojarlo, y marca el rasgo de modal para accesibilidad [repo:Sources/CompanionUI/Feedback/FeedbackModal.swift:33]
- El sistema de diseno ya tiene los tokens de radio de dialogo y de chip [repo:Sources/CompanionUI/DesignSystem/TokensChoices.swift:278]
- El movimiento del chrome ya respeta Reducir movimiento por una funcion central [repo:Sources/CompanionUI/DesignSystem/ChromeMotion.swift:6]
- La curva estandar de Incredible ya existe como token [repo:Sources/CompanionUI/DesignSystem/Motion.swift:38]
- Los avisos de la app son una pila arriba a la derecha de la ventana, con transicion de entrada [repo:Sources/CompanionUI/DesignSystem/Toasts.swift:53]
- Esa pila no recibe clics y se monta en el root [repo:Sources/CompanionUI/Window/CompanionRootView.swift:104]
- El tope del inventario de opciones esta en 19 y nombra las adiciones que lo subieron [repo:Tests/CompanionUITests/SettingsParityTests.swift:35]
- Los tests de WIN-5 fijan las medidas, los tres estados y el marco del panel [repo:Tests/CompanionUITests/SettingsPanelTests.swift:14]
- La autoinspeccion lee la pagina abierta de Ajustes y los tests abren paginas por su valor crudo [repo:Tests/CompanionUITests/SelfInspectionMirrorWiringTests.swift:73]
- Hay una vista previa de `SettingsView` solo en DEBUG [repo:Sources/CompanionUI/Settings/SettingsView.swift:375]
Contextos: app de release (/Applications/Companion.app, la hoja vive en la ventana principal y la abren el menu, el atajo y la isla); swift test de CompanionUITests (SettingsPanelTests, SettingsParityTests, SelfInspectionMirrorWiringTests, que renderizan vistas a bitmap o leen el inventario) y de CompanionCoreTests (SettingsSearch puro) via scripts/gates.sh serializado por el lock de gates; CI (los mismos tests, sin ventana real); vista previa de Xcode de SettingsView (solo DEBUG); autoinspeccion por el puente (ScreenReport expone si Ajustes esta abierto y en que pagina); el panel de la isla (NSPanel no activante, desde donde solo se pide abrir Ajustes).

## 3. Fuentes primarias

- HIG, Settings (macOS): la guia nativa pide un elemento Ajustes en el menu de la app, el atajo Comando-coma, una ventana propia con barra de herramientas por paneles y restaurar el ultimo panel visto [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/settings.json@HIG-2026]
- HIG, Settings: recomienda atenuar minimizar y maximizar de esa ventana y actualizar el titulo con el panel visible [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/settings.json@HIG-2026]
- HIG, Modality: presentar contenido en modal solo cuando hay un beneficio claro [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/modality.json@HIG-2026]
- HIG, Modality: dar siempre una forma obvia de cerrar; en macOS se espera un boton en la vista de contenido [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/modality.json@HIG-2026]
- HIG, Modality: mantener cortas y simples las tareas modales para no perder la tarea suspendida [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/modality.json@HIG-2026]
- SwiftUI `Settings`: la escena de Ajustes de macOS 11 en adelante que SwiftUI muestra desde el menu de la app o el atajo [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/settings.json@macOS26]
- SwiftUI `sheet(isPresented:onDismiss:content:)`: presenta una hoja modal con un binding, sin parametros para scrim ni transicion de entrada [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/sheet(ispresented:ondismiss:content:).json@macOS26]
- SwiftUI `AccessibilityTraits.isModal`: cuando un elemento modal esta visible, los elementos hermanos que no son modales se ignoran para la tecnologia asistiva; desde macOS 10.15 [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/accessibilitytraits/ismodal.json@macOS26]
- SwiftUI `accessibilityReduceMotion`: con Reducir movimiento activo la UI debe evitar animaciones grandes, en especial las que simulan la tercera dimension [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/environmentvalues/accessibilityreducemotion.json@macOS26]
- SwiftUI `onExitCommand(perform:)`: en macOS la accion corre al pulsar Escape mientras la vista tiene el foco [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/onexitcommand(perform:).json@macOS26]

## 4. Implementaciones de referencia

- Incredible 0.2.36 (Norditech; la referencia que Karen fija como minimo): la hoja de Ajustes es un dialogo modal con scrim, caja centrada que crece hasta un tope de ancho y alto, rail a la izquierda y panel de contenido a la derecha [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Incredible: el scrim y la caja entran y salen con un fundido de opacidad y una escala ligera, y la caja arranca un poco por encima de su sitio al entrar; todo bajo la preferencia de movimiento, de modo que con Reducir movimiento no hay transicion (E1, E2) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Incredible: la hoja cierra por Esc, por clic en el scrim y por una X redonda arriba a la derecha con etiqueta propia; el cierre se confirma al terminar la animacion de salida (E5, E6) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Incredible: el rail no lleva titulo, empieza con la busqueda y sigue con la navegacion por grupos; el primer grupo no tiene encabezado y el de la cuenta si (E8, E9, E11) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Incredible: al escribir en la busqueda la navegacion se oculta y aparece una lista de resultados con etiqueta y pagina; flechas, Enter y clic eligen; Esc con texto lo limpia antes de cerrar (E9, E10) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Incredible: el indice tiene una entrada por pagina y una por fila con identificador de fila, palabras clave y a veces un popup; la coincidencia es por prefijo de palabra con pesos y un tope de resultados (E17, E18) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Incredible: elegir un resultado cambia de pagina, abre el popup si la entrada lo trae, busca la fila reintentando y la lleva al centro con una banda de fondo que aparece y se apaga (E19) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Incredible: el aviso de guardado es una caja pequena abajo a la derecha del panel, sin transicion, y solo lo disparan once setters envueltos (E29, E31) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Incredible: un hook de guardado optimista revierte al valor anterior y muestra un error en linea si el setter falla (E32) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Incredible: los sub-dialogos son un popup compacto con tres anchos, titulo, sublinea y X, y dialogos de alerta con tope propio y capa superior (E33, E34, E37, E38) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Base UI Dialog (mui, unas 11 mil estrellas, push 2026-10-03; es la primitiva que usa Incredible): un dialogo modal con parte de fondo, popup, titulo, descripcion y cierre, con foco inicial y final configurables [ref:https://github.com/mui/base-ui/blob/19511bb171f3b360b006c94cf6d07e53cb446505/docs/src/app/(docs)/react/components/dialog/page.mdx@19511bb171f3b360b006c94cf6d07e53cb446505]
- sindresorhus/Settings (paquete Swift, unas 1.5 mil estrellas, push 2025-11-10): la forma nativa de macOS, una ventana de Ajustes con paneles; es la alternativa que este brief no adopta y exigiria una dependencia nueva [ref:https://github.com/sindresorhus/Settings/blob/f41475771f65379ca10852c95119a7f53f0de5a5/readme.md@f41475771f65379ca10852c95119a7f53f0de5a5]
- Donde Incredible y la guia de macOS difieren (hoja modal en la ventana contra ventana de Ajustes nativa), manda Incredible por la directiva de Karen de que es el piso minimo [KAREN:chat 2026-10-02]

## 5. Opciones

S1. Hoja y rail.

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Overlay propio en el root: scrim, hoja centrada y rail, con el patron del modal de comentarios | Cabe en la ventana donde ya viven todas las entradas; scrim, entrada y cierre se igualan a Incredible; reusa `sheetBody` | Hay que escribir foco y Esc a mano; la hoja no es la ventana de Ajustes de macOS | media | Si |
| B. `.sheet(isPresented:)` nativo | Foco y cierre los da el sistema | La firma no expone scrim ni transicion de entrada; no replica el aspecto de Incredible | baja | No |
| C. Escena `Settings` de SwiftUI en ventana aparte | Es lo que pide la guia de macOS; Comando-coma gratis | No es la hoja de Incredible; rompe las entradas por notificacion y la lectura de autoinspeccion | alta | No |
| D. Mantener el panel flotante de WIN-5 | Cero cambio | Copia el panel de desarrollo del primer arranque, no la hoja | ninguna | No |

S2. Mapa de paginas.

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Reagrupar a las paginas de Incredible, mantener los valores crudos de las existentes, agregar alias y un indice con palabras clave y filas | Igual al mapa de Incredible; la isla, los menus y los tests siguen abriendo por id | El tope de 19 opciones y el buscador de Core cambian; hay paginas con huecos (GAPS) | media | Si |
| B. Solo reordenar las siete paginas actuales | Diff chico | No iguala el mapa; Silenciar al hablar sigue fuera de Sistema > Sonido | baja | No |
| C. Agregar filas de relleno para lo que falta | La hoja se ve completa | Filas que no hacen nada; el inventario promete lo que no cumple | baja | No |

S3. Aviso de guardado.

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Aviso propio dentro del host de la hoja, con un modelo puro y un envoltorio de los mismos setters que Incredible | Igual en posicion, sin animacion y en el conjunto de disparos; probable sin ventana | Un aviso mas en la app, aparte de la pila | media | Si |
| B. Reusar la pila `NoticeCenter` | Ya existe | Arriba a la derecha de la ventana, con transicion y sonido de aviso | baja | No |
| C. Una pila de avisos de otra libreria de componentes | Resuelve avisos en general | Incredible resuelve este caso y manda; esa pila no es la de la hoja | media | No |

S4. Sub-dialogos.

| Opcion | Pros | Contras | Complejidad | Recomendacion |
|---|---|---|---|---|
| A. Un componente de popup compacto con tres anchos y un dialogo de alerta, ambos sobre la hoja | Igual a Incredible; un solo componente sirve a atajos, microfono, idiomas y permisos | Apilar modales exige un orden de Esc y de foco | media | Si |
| B. `.sheet` y `.confirmationDialog` nativos | Menos codigo | No igualan tamano ni aspecto; el anidado de sheets en macOS no es el de Incredible | baja | No |
| C. Expandir en linea dentro de la pagina | Sin capas | Atajos y microfono no caben en una fila; no es lo de Incredible | media | No |

## 6. Evidencia en contra

- Contra la hoja modal: la guia de macOS pide una ventana de Ajustes con barra de herramientas y Comando-coma; se acepta como desviacion porque Incredible es el piso minimo por directiva de Karen y las entradas actuales ya traen la ventana principal al frente [KAREN:chat 2026-10-02]
- Contra la hoja modal, ademas: la guia dice que lo modal solo vale con beneficio claro, y se acepta porque Ajustes es una tarea corta que se cierra por Esc, por el scrim y por una X visible, que es lo que la misma guia pide para cerrar [doc:https://developer.apple.com/tutorials/data/design/human-interface-guidelines/modality.json@HIG-2026]
- Contra borrar WIN-5: una auditoria previa pidio ese panel y un test fija sus medidas; se resuelve porque el hallazgo de este plan es que el panel copia la superficie equivocada de Incredible, y los tests de WIN-5 se reescriben en el mismo PR que lo borra [repo:Tests/CompanionUITests/SettingsPanelTests.swift:14]
- Contra borrar WIN-5, ademas: el panel dejaba la ventana usable detras; se acepta porque Incredible bloquea con scrim y esa propiedad era un valor de diseno del panel equivocado [repo:Sources/CompanionUI/Settings/SettingsPanel.swift:43]
- Contra replicar el aviso de Incredible sobre la pila de avisos que ya existe en la app: se acepta duplicar el mecanismo porque la pila vive en el root y la hoja necesita un aviso dentro de ella, sin animacion y sin sonido [repo:Sources/CompanionUI/DesignSystem/Toasts.swift:31]
- Contra no usar otra pila de avisos de una libreria de componentes: esa libreria sirve donde Incredible no tiene referencia, y aqui Incredible resuelve el caso [KAREN:chat 2026-10-02]
- Contra la entrada sin animacion con Reducir movimiento: la guia pide evitar animaciones grandes con esa preferencia; se resuelve porque Incredible apaga toda la transicion bajo esa preferencia y Companion ya tiene el interruptor central [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/environmentvalues/accessibilityreducemotion.json@macOS26]
- Contra el buscador por prefijo y palabras clave: el de Core compara subcadenas en titulo y subtitulo y esta probado en dos idiomas; se acepta cambiarlo porque Incredible ordena por prefijo, palabras clave y pagina, y se conservan la normalizacion de acentos y mayusculas [repo:Sources/CompanionCore/Settings/SettingsSearch.swift:25]
- Contra subir el tope de opciones del inventario: el test lo fija en 19 y cada subida nombra su adicion; se resuelve nombrando en el mismo test cada fila nueva de S2 [repo:Tests/CompanionUITests/SettingsParityTests.swift:35]
- Contra que la lista GAPS prometa trabajo grande sin dueno: se acepta porque descartar lo que Incredible tiene contradice la directiva de Karen; cada fila dice su estado real [KAREN:chat 2026-10-02]

## 7. Ejemplares y anti-ejemplos

- Bien hecho, en el repo: el modal de comentarios se monta en el root con velo, elevacion de hoja y rasgo de modal, y se cierra con la accion de cancelar [repo:Sources/CompanionUI/Feedback/FeedbackModal.swift:50]
- Bien hecho, en el repo: toda animacion de chrome pasa por una funcion que recibe Reducir movimiento [repo:Sources/CompanionUI/DesignSystem/ChromeMotion.swift:6]
- Bien hecho, en el repo: la fila encontrada por la busqueda se enciende leyendo un valor de entorno, sin tocar la pagina [repo:Sources/CompanionUI/Settings/SettingsPieces.swift:184]
- Bien hecho, en el repo: el diseno de hoja con barra lateral ya existe y solo falta un host que lo use [repo:Sources/CompanionUI/Settings/SettingsView.swift:87]
- Bien hecho, Incredible: el hook de guardado muestra el valor nuevo de inmediato, revierte si el setter falla y muestra el error en la fila (E32) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Bien hecho, Incredible: la busqueda de una fila reintenta hasta que la fila existe, porque la pagina se monta despues de elegir (E19) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Bien hecho, Base UI: foco inicial en el elemento marcado o en el popup, y foco final configurable [ref:https://github.com/mui/base-ui/blob/19511bb171f3b360b006c94cf6d07e53cb446505/docs/src/app/(docs)/react/components/dialog/page.mdx@19511bb171f3b360b006c94cf6d07e53cb446505]
- Anti-ejemplo, en el repo: un panel oscuro con colores propios que ignora la apariencia de la app [repo:Sources/CompanionUI/Settings/SettingsPanel.swift:164]
- Anti-ejemplo, en el repo: un interruptor que escribe su preferencia sin pasar por un setter envuelto, de modo que no puede avisar ni revertir [repo:Sources/CompanionUI/Settings/HoldSettings.swift:130]
- Anti-ejemplo, en el repo: una confirmacion con velo difuminado, cuando la hoja de Incredible no difumina [repo:Sources/CompanionUI/Settings/SettingsView.swift:212]

## 8. Trampas

- El valor crudo de `SettingsTab` es un identificador que usan la isla, los menus y los tests; renombrar paginas cambia titulos, nunca esos valores, y los ids viejos necesitan alias como los que Incredible mantiene (E16) [repo:Sources/CompanionUI/Settings/SettingsInventory.swift:4]
- Los tests de autoinspeccion abren paginas por su valor crudo [repo:Tests/CompanionUITests/SelfInspectionMirrorWiringTests.swift:73]
- Esc se resuelve en el root y `onExitCommand` solo corre con el foco en la vista, de modo que "Esc limpia la busqueda antes de cerrar" necesita el texto de busqueda a la vista del root o un manejo local con foco [doc:https://developer.apple.com/tutorials/data/documentation/swiftui/view/onexitcommand(perform:).json@macOS26]
- La cadena actual de Esc es aprobacion, menu desplegable, Ajustes; los popups y alertas de S4 se insertan antes de cerrar la hoja [repo:Sources/CompanionUI/Window/CompanionRootView.swift:142]
- El menu desplegable de la hoja tiene su propio portal y su propia capa de captura de clics, que hay que subir por encima de los popups [repo:Sources/CompanionUI/Settings/SettingsView.swift:69]
- El scrim del sistema de diseno cambia con el esquema de color y la hoja de Incredible tiene un valor fijo; reusarlo cambia el aspecto en oscuro [repo:Sources/CompanionUI/DesignSystem/TokensChoices.swift:173]
- Companion tiene apariencia oscura y Incredible solo tiene los tokens de la hoja en claro; en oscuro la hoja usa tokens semanticos de Companion, no un negro fijo [repo:Sources/CompanionUI/DesignSystem/TokensChoices.swift:278]
- La entrada de Incredible arranca un poco por encima de su sitio y baja; el plan dice "hacia arriba", que en coordenadas de SwiftUI es un desplazamiento vertical negativo al inicio y cero al final, y la salida solo desvanece y escala (E2) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Con Reducir movimiento Incredible no cruza fundido: no hay transicion alguna; la hoja aparece y desaparece al instante [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- El cierre de Incredible se confirma al terminar la animacion de salida; en SwiftUI el estado de apertura debe seguir verdadero hasta entonces o el contenido salta [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- El aviso de Incredible no reinicia su temporizador; dos guardados seguidos pueden apagarlo antes de tiempo, y por KD4 se copia tal cual (E30) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Solo once setters disparan el aviso; los interruptores de silenciar, el nivel de modelo, el wake word, el modo pasivo y el resplandor no (E31) [ref:incredible-ref/briefs/ajustes-hoja-incredible.md@5418ee1a0967]
- Hoy los interruptores de Companion escriben directo, de modo que el envoltorio de S3 es un cambio de cada fila y no un cambio de un solo sitio [repo:Sources/CompanionUI/Settings/HoldSettings.swift:130]
- Sonidos de Companion es un interruptor positivo que escribe dos preferencias; "Silenciar efectos" de Incredible es el inverso, y se invierte solo en la vista, nunca en el almacen (E23) [repo:Sources/CompanionUI/Settings/HoldSettings.swift:132]
- Silenciar al hablar avisa por notificacion al cambiar; moverlo de General a Sistema no debe tocar esa preferencia ni su clave [repo:Sources/CompanionUI/Settings/UserPreferences.swift:357]
- Las filas nuevas de S2 suben el inventario por encima de 19 y el test lo marca como fallo hasta nombrarlas [repo:Tests/CompanionUITests/SettingsParityTests.swift:35]
- La luz de la fila encontrada es un valor de entorno que existe; el centrado y el reintento de la busqueda se agregan sin cambiarlo [repo:Sources/CompanionUI/Settings/SettingsPieces.swift:184]
- Contexto app de release: la hoja vive en la ventana principal y no en el panel de la isla, asi que el scrim cubre la ventana y no la pantalla [repo:Sources/CompanionApp/CompanionMainWindow.swift:205]
- Contexto swift test: el modelo de la hoja (medidas, busqueda, aviso, tamanos de popup) debe ser puro como el modelo del panel actual, para probarse sin ventana [repo:Sources/CompanionUI/Settings/SettingsPanel.swift:36]
- Contexto swift test: los tests de bitmap de Ajustes renderizan vistas sueltas; una hoja que dependa del root no se renderiza sola [repo:Tests/CompanionUITests/SettingsPanelTests.swift:97]
- Contexto CI: los tests de WIN-5 se reescriben o borran en el mismo PR que borra el panel, o CI rompe por simbolos que ya no existen [repo:Tests/CompanionUITests/SettingsPanelTests.swift:14]
- Contexto vista previa: la vista previa de `SettingsView` solo existe en DEBUG y debe seguir compilando con el diseno de hoja [repo:Sources/CompanionUI/Settings/SettingsView.swift:375]
- Contexto autoinspeccion: el root expone si Ajustes esta abierto y la pagina, y esos dos datos deben seguir saliendo del nuevo host [repo:Sources/CompanionUI/Window/CompanionRootView.swift:211]
- Contexto panel de la isla: la isla no puede alojar la hoja, solo pide abrirla; es la misma razon por la que el modal de comentarios vive en la ventana [repo:Sources/CompanionUI/Feedback/FeedbackModal.swift:6]

## 9. Incertidumbre

- ASSUMPTION: la sesion Companion1 lleva el modo pasivo (b2b y P4) y la sesion ATOM lleva la fila de reinicio de permisos (ResetPermissionsRow); ambas cosas las dijo el orquestador y no las verifique en esta corrida. prueba: listar las ramas `feat/presence-passive*` y `feat/reset-permissions-relaunch*` con `git branch --list` y abrir sus PR con `gh pr list`
- ASSUMPTION: el borde pintado de la hoja de Incredible puede ser el de la caja o el del popup, porque ambos se declaran (E4). prueba: capturar la hoja abierta de Incredible, ampliar el borde y medir su color
- ASSUMPTION: en apariencia oscura la hoja de Incredible no cambia de tokens, porque solo se leyeron los claros para la hoja (E3). prueba: abrir Incredible con la Mac en oscuro y capturar la hoja
- ASSUMPTION: Esc llega al root cuando el foco no esta en la hoja, porque `onExitCommand` corre solo con foco. prueba: abrir Ajustes en la app de release, quitar el foco del buscador y pulsar Esc
- ASSUMPTION: el rasgo de modal sobre un overlay dentro de un ZStack oculta a VoiceOver el resto de la ventana, como ya hace el modal de comentarios. prueba: abrir la hoja con VoiceOver y recorrer con el cursor hasta salir de ella
- ASSUMPTION: Incredible no vuelve a abrir el ultimo popup al reabrir la hoja, porque no se leyo estado persistido. prueba: abrir un popup en Incredible, cerrar la hoja y reabrirla
- KD1 firmado por Karen: fila en Sistema > App.
- KD2 firmado por Karen: dentro de Cuenta.
- [NEEDS CLARIFICATION: Karen dijo el 2026-10-02 que ya no quiere mas documentos de texto, solo codigo y tests [KAREN:chat 2026-10-02]; este brief es la compuerta de investigacion de S1-S4, que superan las veinte lineas. Se firma o se salta a la spec?]

## 10. Checklist de estandar

S1. Hoja y rail

- [ ] `SettingsPanelHost`, `SettingsPanelModel`, `SettingsPanelState`, la pildora y sus tests ya no existen, y todas las entradas (menu, atajo, isla, tarjetas) abren la hoja por `companionOpenSettings`.
- [ ] El scrim es negro con la opacidad de la referencia local, sin difuminado, y aparece con un fundido de la duracion y la curva de la referencia local.
- [ ] La hoja esta centrada, con ancho y alto topados como en la referencia local, radio de dialogo, borde y sombra de modal de los tokens, y fondo de lienzo en el panel.
- [ ] Entrar y salir anima opacidad y escala, y la entrada arranca por encima de su sitio; con Reducir movimiento no hay transicion.
- [ ] Cierra por Esc, por clic en el scrim y por una X arriba a la derecha con etiqueta localizada; el estado de apertura sigue verdadero hasta terminar la salida.
- [ ] Esc con texto en el buscador solo lo limpia; un segundo Esc cierra la hoja; un menu desplegable abierto se cierra antes.
- [ ] El foco queda atrapado: la hoja lleva el rasgo de modal y el foco inicial va al elemento marcado o a la hoja.
- [ ] El rail no lleva titulo, tiene el buscador arriba, grupos con el primero sin encabezado, el espaciador entre grupos de la referencia local y la version abajo en pie con numeros tabulares.
- [ ] Una fila del rail mide lo de la referencia local, la pagina activa lleva fondo de resaltado y el rasgo de pagina actual, y el hover tiene su transicion.
- [ ] Los resultados muestran etiqueta y pagina; flechas con tope, Enter y clic eligen; vacio dice que no hay nada para la consulta.
- [ ] Elegir un resultado cambia de pagina, abre el popup si la entrada lo trae, reintenta hasta hallar la fila y la centra con la banda de la referencia local.
- [ ] Las medidas y tiempos de S1 salen de constantes puras con un test cada una contra la referencia local, sin tocar el repo con esos valores en prosa.
- [ ] Hay captura de la hoja antes y despues, en claro y en oscuro, junto a la de Incredible.

S2. Mapa de paginas

- [ ] El primer grupo tiene General, Companion, Vocabulario, Contactos (si existe), Memoria y Sistema; el grupo Cuenta tiene Cuenta, Miembros, Facturacion y uso y Datos y privacidad, y cada pagina sin backend esta en GAPS y no pinta filas vacias.
- [ ] Los valores crudos de `SettingsTab` existentes no cambian y hay una tabla de alias para los ids viejos.
- [ ] Atajos, Microfono e Idioma de dictado abren popup; el permiso de Permisos abre su popup sobre Datos y privacidad y no es una pagina.
- [ ] Silenciar el sonido mientras hablas esta en Sistema > Sonido con su identificador de fila, y Silenciar efectos es el inverso de Sonidos solo en la vista.
- [ ] El brillo de pantalla, la apariencia y el tamano de texto quedan donde Karen decida en KD1 y KD2.
- [ ] La fila de reinicio de permisos de ATOM esta en Sistema > Zona de peligro y la del modo pasivo conserva su lugar sin fila hueca.
- [ ] El indice de busqueda tiene una entrada por pagina y una por fila con palabras clave; hay un test que busca cada fila y la encuentra.
- [ ] `SettingsParityTests` nombra cada fila nueva y el tope sube solo por ellas.
- [ ] Las filas de equipo interno de Incredible no se replican.

S3. Aviso de guardado

- [ ] El aviso esta abajo a la derecha de la hoja, con radio de chip y sombra de popup, sin animacion y con la duracion de la referencia local.
- [ ] Un modelo puro decide la visibilidad y se prueba sin reloj de pared.
- [ ] Solo disparan el aviso los setters de nombre y perfil, microfono, abrir al iniciar, volumen, diagnostico y voz; los interruptores de silenciar, el nivel de modelo, el wake word y el modo pasivo no lo disparan, con un test para cada grupo.
- [ ] Si un setter falla, el valor vuelve al anterior y la fila muestra el error en linea localizado; el interruptor muestra estado de guardado mientras corre.
- [ ] Con dos guardados seguidos el aviso se apaga con el primer temporizador, como Incredible (KD4), y tiene un test.

S4. Sub-dialogos

- [ ] El popup compacto tiene tres anchos, titulo, sublinea, X y fondo de lienzo; el tamano por variante sale de una tabla pura con test.
- [ ] Atajos, Microfono, Idioma de dictado, Idioma de habla y Permisos usan ese popup con la variante de la referencia local.
- [ ] Borrar historial y reiniciar usan un dialogo de alerta con tope propio, capa por encima del popup y rasgo de modal.
- [ ] El reinicio confirma escribiendo la palabra exacta y deshabilita el boton hasta que coincide.
- [ ] Esc cierra primero el dialogo mas alto y luego la hoja.
- [ ] Hay captura de cada popup y de cada alerta, en claro y en oscuro.

Transversal

- [ ] Ninguna medida, clase, texto ni tiempo extraido de Incredible aparece en el repo; solo la cita a la referencia local.
- [ ] El PR lleva su fragmento de changelog y los gates pasan con `scripts/gates.sh`.

## 11. Fuentes

| n | Titulo | Editor | Version o fecha | Consultado | Confianza |
|---|---|---|---|---|---|
| 1 | Incredible.app 0.2.36, extractos de la hoja de Ajustes (solo en la referencia local, no se publican) | Norditech, binario instalado | 0.2.36 | 2026-10-03 | high (shell, rail, busqueda, toast, paginas y dialogos leidos; la geometria final de oscuro no) |
| 2 | HIG, Settings | Apple | HIG 2026 | 2026-10-03 | high |
| 3 | HIG, Modality | Apple | HIG 2026 | 2026-10-03 | high |
| 4 | Settings (escena de SwiftUI) | Apple, SwiftUI | macOS 26 | 2026-10-03 | high |
| 5 | sheet(isPresented:onDismiss:content:) | Apple, SwiftUI | macOS 26 | 2026-10-03 | high |
| 6 | AccessibilityTraits.isModal | Apple, SwiftUI | macOS 26 | 2026-10-03 | high |
| 7 | accessibilityReduceMotion | Apple, SwiftUI | macOS 26 | 2026-10-03 | high |
| 8 | onExitCommand(perform:) | Apple, SwiftUI | macOS 26 | 2026-10-03 | high |
| 9 | Base UI, pagina del componente Dialog | mui | 19511bb | 2026-10-03 | medium |
| 10 | sindresorhus/Settings, readme | sindresorhus | f414757 | 2026-10-03 | medium |
| 11 | Codigo y tests de companion-next (Settings, DesignSystem, Window, Core) | este repo | main c3a2202 | 2026-10-03 | high |

[KAREN:chat 2026-10-02] Incredible es el piso minimo de Companion y toda decision que Incredible ya resuelve se replica tal cual, sin preguntar; lo que choca con una regla firmada se lista como decision explicita. Los extractos de Incredible no se suben al repo.
