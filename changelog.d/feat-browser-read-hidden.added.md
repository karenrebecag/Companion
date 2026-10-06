- **La lectura del navegador puede listar también lo oculto (2026-10-04).**
  Con `hidden: true`, `browser_read` incluye los controles que no se muestran, como los items
  de un menú cerrado, y cada uno va marcado `hidden` para que el modelo no lo tome por visible.
  Actuar sobre uno se sigue rechazando mientras siga oculto, su texto no entra al texto de la
  página y su valor no viaja. Sin la opción, la lectura es exactamente la de antes.
