- **Un test de permisos MCP ya no falla en CI de vez en cuando (2026-10-01).** Solo tests: con
  dos permisos en cola, el test exigía que las respuestas salieran al servidor en el orden de los
  clics. Pero cada respuesta sale por su lado y el protocolo las casa por id, así que dos clics
  seguidos pueden cruzarse. Ahora el test revisa que cada permiso lleve su propia respuesta, y uno
  nuevo cruza las dos a propósito. La app no cambia. Brief `docs/research/mcp-orden-veredictos.md`.
