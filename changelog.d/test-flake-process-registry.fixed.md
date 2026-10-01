- **El test del techo de procesos ya no depende del reloj (2026-10-01).** Esperaba 80 ms fijos a
  que dos shells de 0.3 s ocuparan el techo; si el proceso de tests se congelaba más que eso, las
  shells terminaban y el tercer encargo entraba. Ahora las shells viven hasta que el test las
  suelta y el tercero espera a que las dos ocupen su lugar. Un congelamiento de 1 s lo hacía
  fallar 5 de 5 veces; con el cambio pasa 10 de 10. La app no cambia.
