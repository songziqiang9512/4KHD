import SwiftUI

@MainActor
@Observable
final class WorkspaceDetailPaneController {
    var isPresented: Bool = true

    var preferredContentIdealWidth: CGFloat {
        isPresented ? 380 : 760
    }

    var preferredContentMaxWidth: CGFloat {
        isPresented ? 430 : 10_000
    }

    var gridColumnLimit: Int? {
        isPresented ? 2 : nil
    }

    var preferredGridCardMinimumWidth: CGFloat {
        isPresented ? 148 : 136
    }

    var preferredGridCardMaximumWidth: CGFloat? {
        isPresented ? 210 : nil
    }

    func setPresented(_ isPresented: Bool) {
        self.isPresented = isPresented
    }

    func toggle() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isPresented.toggle()
        }
    }
}
