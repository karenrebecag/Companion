import AppKit
import SwiftUI

/// Captures a keyboard shortcut by listening for key presses.
struct ShortcutCaptureField: View {
    let onCapture: (UInt16, KeyModifiers) -> Void
    @State private var isCapturing = false
    @State private var displayText = "Presiona una tecla..."
    private let captureState = CaptureState()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Button(action: toggleCapture) {
                HStack {
                    Text(isCapturing ? "Escuchando..." : displayText)
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(
                            isCapturing ? Semantic.accent : Semantic.foreground
                        )
                    Spacer()
                    Image(systemName: isCapturing ? "stop.circle.fill" : "keyboard")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(
                            isCapturing ? Semantic.accent : Semantic.mutedForeground
                        )
                }
                .padding(Space.x2)
                .background(Semantic.surface)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Semantic.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if isCapturing {
                Text("Presiona Esc para cancelar")
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .onAppear { startMonitoring() }
        .onDisappear { stopMonitoring() }
    }

    private func toggleCapture() {
        isCapturing.toggle()
        if isCapturing {
            displayText = "Escuchando..."
        } else {
            displayText = "Presiona una tecla..."
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard isCapturing else { return }

        let onCapture = self.onCapture
        captureState.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels the capture.
            if event.keyCode == 53 {
                return event
            }

            let modifiers = KeyModifiers.from(event.modifierFlags)
            let keyCode = event.keyCode

            // Notify parent of the captured shortcut.
            Task { @MainActor in
                onCapture(keyCode, modifiers)
            }

            // Consume the event.
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor = captureState.monitor {
            NSEvent.removeMonitor(monitor)
            captureState.monitor = nil
        }
    }
}

/// Holder for the monitor reference.
private class CaptureState {
    var monitor: Any?
}

