import SwiftUI

/// The app's general grid, reduced to its useful minimum: content lives on a
/// centered reading column (`Container.sheet`) with token gutters, whatever
/// the window does around it. One container so every full-screen sheet
/// centers the same way instead of each view improvising its own frame.
package struct SheetColumn<Content: View>: View {
    @ViewBuilder let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        content
            .padding(.horizontal, Space.x8)
            .frame(maxWidth: Container.sheet)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
