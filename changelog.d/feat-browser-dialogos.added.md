- **El navegador ya no se queda atascado con un dialogo de la pagina (2026-10-05).**
  Cuando Companion tiene el control de una pestana y la pagina abre `alert`, `confirm`, `prompt` o
  `beforeunload`, la extension contesta por CDP: las alertas se descartan, los `confirm` siempre
  valen "no" (y si la pregunta incluye borrar, pagar, enviar, transferir o cualquiera de sus
  equivalentes en espanol, el modelo recibe una linea avisandole), los `prompt` reciben su valor
  por defecto, y un `beforeunload` mantiene la pestana donde esta. Entre acciones, la misma politica
  se aplica en un guion en el mundo MAIN que envuelve `window.alert/confirm/prompt/print` para que
  la pagina no se bloquee aunque nadie este mirando. La siguiente accion o lectura de esa pestana
  lleva una linea mas en su `done` o en el texto leido, contando que decidio Companion y pidiendo
  que la persona lo confirme.
