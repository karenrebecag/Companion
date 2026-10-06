import CompanionCore
import CompanionServices
import CompanionTestKit
import Testing

// The chosen microphone is a uid. What capture pins is whatever the HAL can
// still give: a gone, silent or aggregate device must never be the pin.

private func mic(_ id: UInt32, _ uid: String, channels: Int = 1,
                 _ kind: MicInputCandidate.Kind = .other) -> MicInputCandidate {
    MicInputCandidate(id: id, uid: uid, inputChannels: channels, kind: kind)
}

private let builtIn = mic(1, "mac", .builtIn)
private let usb = mic(2, "usb")

@Suite struct MicInputChooserTests {
    @Test func theChosenDeviceIsPinnedWhenItHasInputs() {
        expectEq(MicInputChooser.choose(target: .device("usb"), candidates: [builtIn, usb], defaultID: 1),
                 2, "elegido: el dispositivo con entradas")
    }

    @Test func aChosenDeviceWithoutInputsFollowsTheDefault() {
        let outputOnly = mic(2, "usb", channels: 0)
        expectEq(MicInputChooser.choose(target: .device("usb"), candidates: [builtIn, outputOnly], defaultID: 1),
                 1, "elegido sin entradas: el del sistema")
    }

    @Test func aChosenDeviceThatIsGoneFollowsTheDefault() {
        expectEq(MicInputChooser.choose(target: .device("gone"), candidates: [builtIn, usb], defaultID: 2),
                 2, "elegido ausente: el del sistema")
    }

    @Test func anAggregateDefaultIsSkippedForTheBuiltInMic() {
        let aggregate = mic(9, "agg", .aggregate)
        expectEq(MicInputChooser.choose(target: .systemDefault, candidates: [builtIn, aggregate], defaultID: 9),
                 1, "agregado: se salta, queda el integrado")
    }

    @Test func noDefaultFallsBackToTheBuiltInMic() {
        expectEq(MicInputChooser.choose(target: .systemDefault, candidates: [usb, builtIn], defaultID: nil),
                 1, "sin predeterminado: el integrado")
        expectEq(MicInputChooser.choose(target: .systemDefault, candidates: [builtIn, usb], defaultID: 99),
                 1, "predeterminado desconocido: el integrado")
    }

    @Test func theBuiltInTargetPinsTheBuiltInMicWhateverTheDefaultIs() {
        expectEq(MicInputChooser.choose(target: .builtIn, candidates: [usb, builtIn], defaultID: 2),
                 1, "integrado: no sigue al predeterminado")
        expectEq(MicInputChooser.choose(target: .builtIn, candidates: [usb], defaultID: 2),
                 2, "integrado ausente: el del sistema")
    }

    @Test func nothingToPinIsNil() {
        expectEq(MicInputChooser.choose(target: .systemDefault, candidates: [], defaultID: nil),
                 nil, "vacío: nada que fijar")
        expectEq(MicInputChooser.choose(target: .systemDefault, candidates: [mic(3, "x", channels: 0)], defaultID: 3),
                 nil, "sin entradas: nada que fijar")
    }
}
