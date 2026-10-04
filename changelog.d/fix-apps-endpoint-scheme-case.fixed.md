- **La direccion de Apps acepta el esquema en mayusculas (2026-10-03).**
  "HTTPS://..." (pegado o con autocapitalizacion) se rechazaba como direccion invalida aunque es https.
  Ahora el esquema se compara sin distinguir mayusculas y se guarda en minusculas; "HTTP://" sigue
  rechazado porque la clave nunca viaja sin cifrar.
