- **CI deja de hacer cola por el analisis de Swift (2026-10-01).** CodeQL de Swift tardaba hasta
  95 min en macOS y ocupaba la mayoria de los 5 runners en cada PR; ahora corre solo en main, cada
  semana y a mano. Actions y JavaScript se siguen analizando en cada PR. Un commit nuevo en un PR
  cancela su corrida anterior; las de main nunca se cancelan. Las actions quedan fijadas por SHA.
