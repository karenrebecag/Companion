- **Los números de elemento del navegador ya no caducan con cada lectura (2026-10-05).** Companion guarda
  las últimas 20 lecturas de cada pestaña, así que un número visto en una lectura reciente sigue sirviendo
  mientras el elemento siga en la página y sin cambios; una lectura lenta que termina tarde ya no invalida
  los números de la más nueva, un marco oculto (como un video embebido) ya no llena la lectura con código
  de la página, y cada `stale_id` queda en el registro con el motivo exacto del rechazo.
