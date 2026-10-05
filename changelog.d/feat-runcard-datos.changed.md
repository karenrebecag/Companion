- **Los pasos de un encargo ya llevan datos reales (2026-10-04).** Cada paso guarda cuándo
  empezó y cuándo terminó, y su fin se empareja con su inicio por el id de la herramienta, así
  que dos llamadas paralelas a la misma tool cierran cada una su fila. Con Claude Code, un paso
  ya no se marca terminado al aparecer: se cierra con su `tool_result` (fallido si trae
  `is_error`), y todos los `tool_use` de un mensaje cuentan, no solo el primero. Los pasos
  nativos muestran su argumento principal en vez de "Executing x". Prepara la tarjeta de
  ejecución de Incredible 0.2.36; esta entrega no cambia la interfaz.
