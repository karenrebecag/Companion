import AppKit
import CompanionUI
import Testing

@Test @MainActor func windowChromeTests() {
    testDesignSizeIsLandscapeLikeIncredible()
    testAspectRatioIsSixteenByTen()
    testContentFloorAndCeilingKeepAspect()
    testStyleMaskPaintsUnderTitlebar()
    testWindowStaysRetainedOnClose()
}

// Spec 16j §8: the window is Incredible's, a sidebar and a page, landscape
// (its recording measures 2286x1440, 16:10), no longer the 2:3 chat column.
@MainActor func testDesignSizeIsLandscapeLikeIncredible() {
    expectEq(WindowChrome.designSize, NSSize(width: 1120, height: 700),
             "ventana: 1120x700 de diseño")
}

@MainActor func testAspectRatioIsSixteenByTen() {
    expectEq(WindowChrome.aspectRatio, NSSize(width: 16, height: 10),
             "ventana: 16:10 como Incredible")
}

@MainActor func testContentFloorAndCeilingKeepAspect() {
    expectEq(WindowChrome.contentMinSize, NSSize(width: 880, height: 550),
             "ventana: piso 880x550, cabe la barra lateral y la tarjeta de pasos")
    expectEq(WindowChrome.contentMaxSize, NSSize(width: 1440, height: 900),
             "ventana: techo 1440x900")
    let minH = WindowChrome.contentMinSize.width
        * WindowChrome.aspectRatio.height / WindowChrome.aspectRatio.width
    let maxH = WindowChrome.contentMaxSize.width
        * WindowChrome.aspectRatio.height / WindowChrome.aspectRatio.width
    expectEq(minH, WindowChrome.contentMinSize.height,
             "ventana: piso respeta 16:10")
    expectEq(maxH, WindowChrome.contentMaxSize.height,
             "ventana: techo respeta 16:10")
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
