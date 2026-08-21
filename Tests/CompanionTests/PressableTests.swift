import CompanionUI
import Testing

@Test @MainActor func pressableTests() {
    testPressScaleShrinksUnlessReduceMotion()
    testPressOpacityDropsWhenPressed()
    testChipHoverScaleAndFill()
    testIconHoverScaleIsStrongerThanChip()
}

@MainActor func testPressScaleShrinksUnlessReduceMotion() {
    expectEq(PressMotion.scale(pressed: false, reduceMotion: false), 1,
             "press: reposo es identidad")
    expectEq(PressMotion.scale(pressed: true, reduceMotion: false), 0.98,
             "press: scale 0.98")
    expectEq(PressMotion.scale(pressed: true, reduceMotion: true), 1,
             "press: reduce-motion apaga el scale")
}

@MainActor func testPressOpacityDropsWhenPressed() {
    expectEq(PressMotion.opacity(pressed: false), 1,
             "press: reposo opaco")
    expectEq(PressMotion.opacity(pressed: true), 0.85,
             "press: el toque se siente")
}

@MainActor func testChipHoverScaleAndFill() {
    expectEq(PressMotion.hoverScale(false, reduceMotion: false, icon: false), 1,
             "chip: reposo es identidad")
    expectEq(PressMotion.hoverScale(true, reduceMotion: false, icon: false), 1.04,
             "chip: acerca un poco")
    expectEq(PressMotion.hoverScale(true, reduceMotion: true, icon: false), 1,
             "chip: reduce-motion apaga el scale; el color se queda")
    expectEq(PressMotion.fillOpacity(hovering: false), 0.55,
             "chip: superficie en reposo")
    expectEq(PressMotion.fillOpacity(hovering: true), 1,
             "chip: hover enciende")
    expect(PressMotion.fillOpacity(hovering: false)
            < PressMotion.fillOpacity(hovering: true),
           "chip: misma rampa, no sustituir surface por un tint mas debil")
    expectEq(PressMotion.strokeOpacity(hovering: false), 0.5,
             "chip: trazo suave en reposo")
    expectEq(PressMotion.strokeOpacity(hovering: true), 1,
             "chip: trazo entero al hover")
}

@MainActor func testIconHoverScaleIsStrongerThanChip() {
    expectEq(PressMotion.hoverScale(true, reduceMotion: false, icon: true), 1.05,
             "icono: hover 1.05")
    expect(PressMotion.hoverScale(true, reduceMotion: false, icon: true)
            > PressMotion.hoverScale(true, reduceMotion: false, icon: false),
           "icono: mas acercamiento que el chip")
}
