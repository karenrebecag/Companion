- **Con la clave de TypeSafe, Jev decide las órdenes de voz (2026-10-18).** Si la clave está
  guardada en Ajustes > Claves, Jev elige la acción aunque "Decidir en local" esté apagado y
  aunque el cerebro sea Cerebras; sin la clave todo sigue como antes y nada viaja a
  TypeSafe. Vaciar la papelera y las demás acciones irreversibles siguen pidiendo un "sí"
  por voz con cualquier confianza. Además, en cada turno Jev estima si la orden necesita
  un agente de fondo: si está muy seguro de que no, ese turno no ofrece delegar.
