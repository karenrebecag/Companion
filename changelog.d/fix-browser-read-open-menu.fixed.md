- **Leer un menu abierto en el navegador ya no devuelve una pagina vacia (2026-10-02).** `browser_read` con
  un selector como `[role=menu]` trae las opciones del menu; si nada coincide o todo esta oculto falla con
  `selector_no_match` o `selector_hidden` y un texto que dice que hacer: abrir el menu o leer sin selector.
