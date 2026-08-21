import AppKit
import CompanionUI
import Testing

@Test @MainActor func windowChromeTests() {
    testDesignSizeIsPortraitColumn()
    testAspectRatioIsTwoByThree()
    testContentFloorAndCeilingKeepAspect()
    testStyleMaskPaintsUnderTitlebar()
    testWindowStaysRetainedOnClose()
}

@MainActor func testDesignSizeIsPortraitColumn() {
    expectEq(WindowChrome.designSize, NSSize(width: 560, height: 840),
             "ventana: 560x840 de diseño")
}

@MainActor func testAspectRatioIsTwoByThree() {
    expectEq(WindowChrome.aspectRatio, NSSize(width: 2, height: 3),
             "ventana: columna 2:3")
}

@MainActor func testContentFloorAndCeilingKeepAspect() {
    expectEq(WindowChrome.contentMinSize, NSSize(width: 440, height: 660),
             "ventana: piso 440x660")
    expectEq(WindowChrome.contentMaxSize, NSSize(width: 680, height: 1020),
             "ventana: techo 680x1020")
    let minH = WindowChrome.contentMinSize.width
        * WindowChrome.aspectRatio.height / WindowChrome.aspectRatio.width
    let maxH = WindowChrome.contentMaxSize.width
        * WindowChrome.aspectRatio.height / WindowChrome.aspectRatio.width
    expectEq(minH, WindowChrome.contentMinSize.height,
             "ventana: piso respeta 2:3")
    expectEq(maxH, WindowChrome.contentMaxSize.height,
             "ventana: techo respeta 2:3")
}

@MainActor func testStyleMaskPaintsUnderTitlebar() {
    let mask = WindowChrome.styleMask
    expect(mask.contains(.fullSizeContentView),
           "ventana: contenido pinta bajo la titlebar")
    expect(mask.contains(.titled) && mask.contains(.closable)
            && mask.contains(.miniaturizable) && mask.contains(.resizable),
           "ventana: chrome de documento, no panel")
}

@MainActor func testWindowStaysRetainedOnClose() {
    // AppDelegate keeps the window; AppKit must not deallocate on close.
    expect(!WindowChrome.releasedWhenClosed,
           "ventana: isReleasedWhenClosed = false")
}
