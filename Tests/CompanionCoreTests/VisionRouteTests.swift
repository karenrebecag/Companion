import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func visionRouteTests() {
    testVisionIsChosenByKey()
    testHoldCapturesOnlyWithAVisionKey()
}

@MainActor func testVisionIsChosenByKey() {
    expectEq(VisionRoute.provider(keys: [.cerebras])?.model, "qwen-3.8-27b",
             "vision: solo Cerebras elige qwen")
    expectEq(VisionRoute.provider(keys: [.openAI])?.model, "gpt-4o-mini",
             "vision: solo OpenAI elige gpt-4o-mini")
    expectEq(VisionRoute.provider(keys: [.cerebras, .openAI])?.id, "cerebras",
             "vision: con las dos keys gana Cerebras")
    expect(VisionRoute.provider(keys: [.brave, .exa]) == nil,
           "vision: sin key de visión no hay proveedor")
}

@MainActor func testHoldCapturesOnlyWithAVisionKey() {
    expect(VisionRoute.holdCaptures(seesScreen: true, keys: [.cerebras]),
           "hold: captura con solo la key de Cerebras")
    expect(!VisionRoute.holdCaptures(seesScreen: false, keys: [.cerebras]),
           "hold: sin permiso de pantalla no captura")
    expect(!VisionRoute.holdCaptures(seesScreen: true, keys: [.brave]),
           "hold: sin key de visión no captura")
}
