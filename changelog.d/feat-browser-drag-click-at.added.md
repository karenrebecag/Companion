- **El navegador ya arrastra y pulsa un punto de la página (2026-10-03).** Dos herramientas nuevas,
  como las de Incredible: `browser_drag` arrastra un elemento de la última lectura sobre otro, o
  unos píxeles, con el botón real del ratón en pasos, para reordenar listas, mover tarjetas o
  deslizadores. Sobre un elemento pide permiso si cualquiera de los dos extremos lo pediría para un
  clic, y el sí queda atado a los dos elementos y sus etiquetas; por píxeles siempre pide permiso.
  `browser_click_at` pulsa un punto x, y de la página visible, para lo que no tiene número (un
  lienzo, un mapa), y siempre pide permiso. El punto y el destino del arrastre solo valen si salen
  de una lectura de hace menos de un minuto, se comprueban otra vez justo antes de pulsar, y nunca se
  suelta ni se pulsa sobre un marco incrustado de otra página. Los arrastres HTML5 nativos
  (`draggable`) todavía no se completan.
