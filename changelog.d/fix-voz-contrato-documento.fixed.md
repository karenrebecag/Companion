- **La voz entrega el documento por contrato, no por adivinanza (2026-10-12).** Al pedir por voz
  una tabla, cinco pasos o tres parrafos, el cerebro llama a `show_document` con la frase y el
  documento por separado: la voz dice solo esa frase, el hilo guarda frase y documento, y la isla
  muestra la tarjeta del documento al callar la voz, en hold y en manos libres. Antes el modelo
  escribia la estructura en markdown libre y cada respuesta tenia una forma distinta (tabla con y
  sin pipes, valla `companion:table`, prosa con punto y coma, una negativa), asi que la voz leia
  filas o no habia documento. Verificado en vivo con gpt-oss-120b en Cerebras: 15 de 15 peticiones
  con estructura llegaron por la tool y una pregunta corta nunca la uso. Fuera: `SpokenLead`,
  `ReplyRichness` y el desvallado de `markdown`, que eran las heuristicas que no convergian.
