# Conformance — el contrato de la reticula, ejecutable

Las reglas de la reticula vivian como prosa en `docs/design-system.md` y como
cinco `grep` en `scripts/gates.sh`. Un agente podia ignorarlas sin que nada
fallara, y de hecho **el gate cerraba en verde con 86 infracciones**: sus
patrones no cubrian la forma que el repo escribe de verdad
(`RoundedRectangle(cornerRadius: 8)` lleva dos puntos, `Text(x ?? "...")`
interpone una expresion).

Este directorio las convierte en **datos**. Patron tomado de
`ATOMUIKIT/atom-uikit-ds/conformance` (modelo Willison: el contrato es el
archivo, no el parrafo).

```bash
swift test --filter uiConformanceTests   # solo el contrato
./scripts/gates.sh                       # todo, con el contrato dentro de Gate 4
```

## Diseno

1. **El contrato es data, el runner es tonto.** Cambiar una regla es editar
   `ui-contract.json` — visible en el diff. Un agente que necesita relajar una
   regla tiene que tocar ESTE archivo; un literal enterrado en una vista no se
   ve en el review.

2. **Ratchet, no big-bang.** `baseline` registra la deuda por archivo. Si un
   archivo empeora, falla. Si mejora, avisa para bajar el numero. Asi el gate
   se enciende HOY, sin fingir que el pasado es perfecto, y congela la entrada
   de deuda nueva. Esto corrige el plan original de R-05, que esperaba a
   limpiar antes de encender — y por tanto no encendia nunca.

3. **Cada regla lleva su `why`.** Es lo que se imprime cuando falla. Una regla
   sin motivo escrito es una regla que alguien va a borrar en seis meses.

## Valvulas

- `// token-exempt: <por que>` en la linea (o en la llamada multilinea). Sin
  el motivo escrito no cuenta como exencion.
- `exemptFiles` en el contrato, con el motivo. Para archivos generados o
  auditados en otro repo.
- `baseline`, para deuda medida y triada.

## Lo que el escaner hace y no hace

Une las lineas de una llamada partida en varias — sin eso, `.frame(` arriba y
`width: 16` abajo no matchean nada y el archivo se reporta limpio. Descarta
comentarios puros: una regla mencionada en un comentario no es una infraccion.

No entiende Swift: son expresiones regulares sobre texto. Un caso gris se
triage con `baseline` o con `token-exempt`, no bajando la regla.

**Prueba de aceptacion:** un gate que no falla con un bug conocido no es un
gate. Verificado por mutacion en las dos direcciones — meter un
`RoundedRectangle(cornerRadius: 8)` en un archivo limpio falla; quitar un
literal existente pasa con la nota de bajar el baseline.
