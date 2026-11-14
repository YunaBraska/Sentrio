import SwiftUI

/// Shared native drag-and-drop behavior for priority rows in the menu and Settings.
struct PriorityDropDelegate: DropDelegate {
    let targetUID: String
    @Binding var draggedUID: String?
    let onMove: (String, String) -> Void

    func dropEntered(info _: DropInfo) {
        guard let source = draggedUID, source != targetUID else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            onMove(source, targetUID)
        }
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggedUID = nil
        return true
    }
}
