import AppKit

// Only visible fold controls get native buttons. Large JSON bodies do not
// create a view/button for every line or rebuild the text view when folding.
final class JSONFoldGutter: NSView {
    weak var textView: NSTextView?
    var controls: [JSONFoldControl] = [] { didSet { needsLayout = true } }
    var onToggle: ((Int) -> Void)?
    var lineStarts: [Int] = [] { didSet { needsDisplay = true } }
    private var buttons: [Int: NSButton] = [:]
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { true }

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityChildren() -> [Any]? {
        buttons.values.sorted { $0.frame.minY < $1.frame.minY }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        for button in buttons.values {
            button.contentTintColor = .secondaryLabelColor
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !lineStarts.isEmpty, let textView, let manager = textView.layoutManager,
              let container = textView.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        func drawNumber(_ index: Int, rect: NSRect) {
            let label = "\(index + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            let point = textView.convert(NSPoint(x: 0, y: rect.midY + origin.y), to: self)
            label.draw(at: NSPoint(x: bounds.maxX - size.width - 6, y: point.y - size.height / 2),
                       withAttributes: attributes)
        }
        manager.enumerateLineFragments(forGlyphRange: glyphs) { [self] rect, _, _, range, _ in
            let character = manager.characterIndexForGlyph(at: range.location)
            var low = 0
            var high = lineStarts.count
            while low < high {
                let middle = (low + high) / 2
                if lineStarts[middle] <= character { low = middle + 1 }
                else { high = middle }
            }
            let index = max(0, low - 1)
            if character == lineStarts[index] { drawNumber(index, rect: rect) }
        }
        if manager.extraLineFragmentTextContainer === container {
            drawNumber(lineStarts.count - 1, rect: manager.extraLineFragmentRect)
        }
    }

    override func layout() {
        super.layout()
        guard let textView, let manager = textView.layoutManager, let container = textView.textContainer else { return }
        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var visibleIDs = Set<Int>()
        for control in controls where NSLocationInRange(control.location, characters) {
            let glyph = manager.glyphIndexForCharacter(at: control.location)
            let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let point = textView.convert(NSPoint(x: 0, y: line.midY + origin.y), to: self)
            let frame = NSRect(x: 2, y: point.y - 9, width: 20, height: 18)
            guard frame.intersects(bounds) else { continue }
            visibleIDs.insert(control.id)
            let button: NSButton
            if let existing = buttons[control.id] { button = existing }
            else {
                button = NSButton()
                button.isBordered = false
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleProportionallyDown
                button.target = self
                button.action = #selector(toggle(_:))
                buttons[control.id] = button
                addSubview(button)
            }
            let label = "\(control.collapsed ? "Expand" : "Collapse") JSON at line \(control.line + 1)"
            if button.frame != frame { button.frame = frame }
            if button.toolTip != label {
                button.tag = control.id
                button.image = NSImage(systemSymbolName: control.collapsed ? "chevron.right" : "chevron.down",
                                       accessibilityDescription: label)
                button.contentTintColor = .secondaryLabelColor
                button.toolTip = label
                button.setAccessibilityLabel(label)
            }
        }
        for id in Array(buttons.keys) where !visibleIDs.contains(id) {
            buttons.removeValue(forKey: id)?.removeFromSuperview()
        }
    }

    @objc private func toggle(_ sender: NSButton) { onToggle?(sender.tag) }
}

final class JSONPreviewContainer: NSView {
    let scrollView = NSScrollView()
    let textView: NSTextView
    let gutter: JSONFoldGutter
    private let gutterWidth: NSLayoutConstraint

    override convenience init(frame frameRect: NSRect) {
        self.init(textView: NSTextView())
        frame = frameRect
    }

    init(textView: NSTextView) {
        self.textView = textView
        gutter = JSONFoldGutter(textView: textView)
        gutterWidth = gutter.widthAnchor.constraint(equalToConstant: 0)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        for view in [gutter, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutter.topAnchor.constraint(equalTo: topAnchor),
            gutter.bottomAnchor.constraint(equalTo: bottomAnchor), gutterWidth,
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textView.backgroundColor = .textBackgroundColor
        gutter.needsDisplay = true
    }

    func setFoldControls(_ controls: [JSONFoldControl], lineStarts: [Int] = []) {
        gutterWidth.constant = lineStarts.isEmpty ? (controls.isEmpty ? 0 : 24) : max(64, 30 + CGFloat("\(lineStarts.count)".count) * 7)
        gutter.lineStarts = lineStarts
        gutter.controls = controls
    }
}
