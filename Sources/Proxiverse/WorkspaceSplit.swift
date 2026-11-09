import AppKit
import SwiftUI

struct WorkspaceSplit<First: View, Second: View>: NSViewControllerRepresentable {
    let vertical: Bool
    let autosaveName: String
    let firstMinimum: CGFloat
    let secondMinimum: CGFloat
    let first: First
    let second: Second

    init(vertical: Bool, autosaveName: String, firstMinimum: CGFloat, secondMinimum: CGFloat,
         @ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) {
        self.vertical = vertical
        self.autosaveName = autosaveName
        self.firstMinimum = firstMinimum
        self.secondMinimum = secondMinimum
        self.first = first()
        self.second = second()
    }

    func makeNSViewController(context: Context) -> WorkspaceSplitController<First, Second> {
        WorkspaceSplitController(first: first, second: second)
    }

    func updateNSViewController(_ controller: WorkspaceSplitController<First, Second>, context: Context) {
        controller.firstHost.rootView = first
        controller.secondHost.rootView = second
        controller.configure(vertical: vertical, autosaveName: autosaveName,
                             firstMinimum: firstMinimum, secondMinimum: secondMinimum)
    }
}

final class WorkspaceSplitController<First: View, Second: View>: NSSplitViewController {
    let firstHost: NSHostingController<First>
    let secondHost: NSHostingController<Second>

    init(first: First, second: Second) {
        firstHost = NSHostingController(rootView: first)
        secondHost = NSHostingController(rootView: second)
        super.init(nibName: nil, bundle: nil)
        addSplitViewItem(NSSplitViewItem(viewController: firstHost))
        addSplitViewItem(NSSplitViewItem(viewController: secondHost))
        splitView.dividerStyle = .thin
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(vertical: Bool, autosaveName: String, firstMinimum: CGFloat, secondMinimum: CGFloat) {
        let name = NSSplitView.AutosaveName(autosaveName + (vertical ? ".vertical" : ".horizontal"))
        if splitView.isVertical != vertical || splitView.autosaveName != name {
            splitView.autosaveName = nil
            splitView.isVertical = vertical
            splitView.autosaveName = name
        }
        splitViewItems[0].minimumThickness = firstMinimum
        splitViewItems[1].minimumThickness = secondMinimum
    }
}
