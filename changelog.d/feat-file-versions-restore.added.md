- **Companion puede listar y restaurar las versiones guardadas de un archivo.** `list_file_history`
  muestra, de la mas nueva a la mas vieja, cada version con su id, la hora y si se guardo antes o
  despues de un guardado, sin revelar nunca la carpeta privada. `restore_file_version` devuelve una
  version anterior sobre el archivo existente despues de que apruebes la hoja; antes guarda una copia
  de lo que hay ahora para poder deshacerlo, y si esa copia no se puede hacer no restaura nada.
