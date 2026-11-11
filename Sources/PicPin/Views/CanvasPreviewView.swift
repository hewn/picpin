import SwiftUI

struct CanvasPreviewView: View {
    @ObservedObject var store: CompositionStore
    var body: some View { Color(nsColor: .windowBackgroundColor) }
}
