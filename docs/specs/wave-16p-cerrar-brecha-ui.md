# Wave 16p — Cerrar la brecha de UI con Incredible

**Estado: APROBADO (2026-09-29).** Firmado por delegación de Karen: "podemos igualar? trabaja
sobre un worktree especifico para estos fixes... todo en loop. tu eres el orquestador, delega
subagentes en loop para cerrar toda esta brecha". Evidencia:
`docs/research/audit-ui-companion-vs-incredible.md` (conteos con archivo:línea).

## 1. Qué cierra

El audit encontró que la ingeniería de la UI ya supera a Incredible (tokens con enforcement,
máquina de estados, motion presupuestado, i18n) y que la brecha restante es de **consolidación**
y de **catálogo**. El catálogo lo cubren 16m-3..7 y 16h (firmadas). Esta wave cubre lo demás.

## 2. Programa y orden

Dos carriles en worktrees propios, integrados en la rama `feat/ui-gap`. Un solo PR
`feat/ui-gap → main` al final, que Karen lee antes del merge (regla de ritmo: nada llega a
`main` sin que lo lea).

| Carril | Orden | Sesión |
|---|---|---|
| UI (`companion-next-ui-gap`) | 1 | 16p-1 quick wins |
| | 2 | 16p-2 consolidación (antes de 16m-3: parte `IslandView` por familias) |
| | 3-7 | 16m-3 adjuntos, 16m-4 dictado y avisos, 16m-5 gráficas y Mermaid, 16m-6 pregunta con opciones y rejilla de avisos, 16m-7 menciones y comentarios |
| | 8 | 16p-3 tipografía y pins |
| Conversación (`companion-next-ui-gap-h`) | 1-3 | 16h-1 filtro de voz, espacios, "listo" con prueba, compuestos; 16h-2 acuse y delegación en segundo plano; 16h-3 dónde estás e isla→modelo |

Cada sesión: test en rojo → implementación → code-reviewer y security-reviewer en paralelo →
hallazgos aplicados test-first → `scripts/gates.sh` verde → PR a `feat/ui-gap` con bitácora.

## 3. 16p-1 — Quick wins

1. **Errores visibles.** `ChatViewModel.errorText` hoy solo lo pinta `ThreadView`, que nadie
   instancia. Se pinta en la isla (aviso con salida, patrón `IslandNoticeCard`) y en Home.
   Test: un `errorText` no nulo produce estado visible en la proyección de la isla.
2. **reduceMotion** en `CompanionRootView`, `SettingsView`, `Dropdown`, `MainSidebar`: sus
   animaciones leen `accessibilityReduceMotion` y caen a opacidad/instantáneo. Test por la
   función pura que elige la animación.
3. **i18n fuera del catálogo**: labels de `Highlight` (`TokensChoices`), `ShortcutAction`
   (`Shortcuts`), tema (`UserPreferences`), "Opening/Abriendo" (`IslandAnswerPieces`) pasan a
   `Localizable.strings` es/en. Test: cada label resuelve a una clave existente en ambos idiomas.
4. **Semántica de botón** en los 11 `onTapGesture` interactivos (patrón `AppsPage:374`:
   `accessibilityAddTraits(.isButton)` + `accessibilityAction`, o `Button` con estilo plano).

## 4. 16p-2 — Consolidación

1. **Una primitiva por papel**: un keycap (sm/lg, con `.elevation`), un estilo de chip en
   cápsula parametrizado por tinta, un botón cerrar (ventana e isla por variante), botones de
   icono reducidos a `IconButton` + variante de isla. Métricas pinneadas a los valores medidos.
2. **Retirar código muerto** (0 instancias verificadas por grep al empezar la sesión):
   `HeaderView` (salvo `ChoiceDropdown`/`HistoryOverlay`, que se mueven), `ControlBar`,
   `ThreadView` (su helper `visible` se muda), `ChatInputView`, `StatusLine`, `AttachmentStrip`,
   `Badge` si sigue sin uso, vista `PermissionRow`, `ShortcutCaptureField`, `VoiceControlsView`,
   `OrbLayers`, `UI.swift`, `IslandHandsChip`, y los huérfanos por arrastre. **`OnboardingView`
   se retira**: la bienvenida `Welcome*` es el único flujo (Karen, 2026-09-29, "cerrar toda
   esta brecha"; recuperable del historial). El baseline de conformance baja con cada borrado.
3. **Paletas locales**: `DataCardInk`, `AttachmentLook`, `ControlFill/Ink/Stroke` se funden en
   `Semantic` o quedan documentadas con su porqué como `IslandInk`/`AnswerInk` (isla siempre
   negra, ovx medido).
4. **`IslandView` por familias**: carpetas `Island/Data`, `Island/Work`, `Island/Attach`,
   `Island/Notices` (riesgo §4 de 16m). `IslandView.swift` queda como composición < 400 líneas.
5. **Fugas de TypeScale**: los 16 `.system(size:)` con expresión pasan por `Fonts`/`GeistFont`;
   `MenuMetrics.duration` usa `MotionTime.base`. Regla nueva del contrato que los detecte.

## 5. 16p-3 — Tipografía y pins

1. Interlineado por escalón en `TypeScale` (valores medidos: 11/1.35, 12/1.4, 13/1.5, 14/1.4,
   15/1.5, 16/1.3, 20/1.2, 22/1.2, 30/1.2, display 1.06) y roles que lo usan.
2. Pins para `MainWindowMetrics`, `AppsMetrics`, `AppPanelMetrics`, `ConnectingSheetMetrics`,
   `IslandAttachMetrics`, `IslandDropMetrics`.

## 6. Criterio de done

Gates verdes; baseline de conformance ≤ al de hoy en cada archivo tocado; cero vistas con 0
instancias en `Sources/`; `IslandView.swift` < 400 líneas; galería de snapshots regenerada con
cada familia nueva; PR final con bitácora por sesión.

## 7. Riesgos

- Borrar `ThreadView` y `HeaderView` arrastra helpers vivos: se mudan antes de borrar, con grep.
- Dos carriles tocan la isla (16h-2 añade la tarjeta de recibo): el carril de conversación
  rebasa sobre `feat/ui-gap` antes de su PR.
- Mermaid (16m-5) es la única dependencia nueva: vendoreada con versión y hash fijados, sin red,
  CSP cerrada, revisión de seguridad propia.
