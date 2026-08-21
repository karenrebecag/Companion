import CompanionCore
import SwiftUI

public struct CompanionRootView: View {
    var model: ChatViewModel

    public init(model: ChatViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.needsOnboarding {
                OnboardingView(model: model)
            } else {
                ThreadView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Color.bg)
        .onAppear { model.onAppear() }
    }
}
