- **El reposo de 0,6 s de la hoja de permiso ahora cuenta desde que termina de aparecer (2026-10-03).**
  Antes arrancaba al llegar la peticion, y como la isla crece primero (unos 120 ms), el contenido
  aparece despues y la hoja se revela encima (hasta 0,3 s), parte del reposo se gastaba con la hoja
  invisible o a medio mostrar: veias los botones menos de 0,6 s antes de que aceptaran clics. Ahora
  el reloj arranca cuando el contenido es visible con una peticion pendiente y ha acabado la
  revelacion; si se oculta y reaparece, o llega otra peticion, empieza de nuevo. Ademas, la guarda
  solo responde a la peticion para la que se armo. Un clic con la hoja invisible sigue ignorandose.
