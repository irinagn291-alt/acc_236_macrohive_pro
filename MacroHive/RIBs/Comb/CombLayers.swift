import UIKit

func hiveHexPath(in rect: CGRect, inset: CGFloat = 0) -> UIBezierPath {
    let r = rect.insetBy(dx: inset, dy: inset)
    let path = UIBezierPath()
    let radius = min(r.width, r.height) / 2
    let center = CGPoint(x: r.midX, y: r.midY)
    for index in 0..<6 {
        let angle = CGFloat(index) * .pi / 3 - .pi / 2
        let point = CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
        if index == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
    path.close()
    return path
}

/// Hex cell drawn in-layer: tabular value plus caption. Not UIView composition.
final class MacroCombLayer: CALayer {
    var caption: String = ""
    var valueText: String = "—"
    var fillFraction: CGFloat = 0
    var exceeded: Bool = false
    var iconName: String?

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        contentsScale = 3
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let layer = layer as? MacroCombLayer {
            caption = layer.caption
            valueText = layer.valueText
            fillFraction = layer.fillFraction
            exceeded = layer.exceeded
            iconName = layer.iconName
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        needsDisplayOnBoundsChange = true
    }

    override func draw(in ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        let bounds = self.bounds
        let path = hiveHexPath(in: bounds, inset: 2)
        ctx.setFillColor(HivePalette.surfaceCG)
        ctx.addPath(path.cgPath)
        ctx.fillPath()

        let clip = hiveHexPath(in: bounds, inset: 2)
        ctx.saveGState()
        ctx.addPath(clip.cgPath)
        ctx.clip()
        let fillHeight = bounds.height * min(max(fillFraction, 0), 1.2)
        let fillRect = CGRect(
            x: bounds.minX,
            y: bounds.maxY - fillHeight,
            width: bounds.width,
            height: fillHeight
        )
        ctx.setFillColor(exceeded ? HivePalette.inkCG : HivePalette.accentCG)
        ctx.setAlpha(exceeded ? 0.22 : 0.35)
        ctx.fill(fillRect)
        ctx.restoreGState()

        ctx.setStrokeColor(exceeded ? HivePalette.inkCG : HivePalette.accentCG)
        ctx.setLineWidth(exceeded ? 3 : 2)
        ctx.addPath(path.cgPath)
        ctx.strokePath()

        let value = valueText as NSString
        let valueFont = HiveType.font(.headline, bold: true, tabular: true)
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: HivePalette.ink
        ]
        let valueSize = value.size(withAttributes: valueAttrs)
        let valueOrigin = CGPoint(x: bounds.midX - valueSize.width / 2, y: bounds.midY - valueSize.height / 2 - 6)
        value.draw(at: valueOrigin, withAttributes: valueAttrs)

        let cap = caption as NSString
        let capFont = HiveType.font(.caption, bold: false)
        let capAttrs: [NSAttributedString.Key: Any] = [
            .font: capFont,
            .foregroundColor: HivePalette.muted
        ]
        let capSize = cap.size(withAttributes: capAttrs)
        cap.draw(
            at: CGPoint(x: bounds.midX - capSize.width / 2, y: valueOrigin.y + valueSize.height + 2),
            withAttributes: capAttrs
        )
        UIGraphicsPopContext()
    }
}

/// Hex progress comb using CAShapeLayer stroke, animated with CABasicAnimation.
final class ProgressCombLayer: CALayer {
    let track = CAShapeLayer()
    let fill = CAShapeLayer()
    private let valueLayer = CATextLayer()
    private let captionLayer = CATextLayer()

    var caption: String = "Energy" {
        didSet { captionLayer.string = caption }
    }

    override init() {
        super.init()
        addSublayer(track)
        addSublayer(fill)
        addSublayer(valueLayer)
        addSublayer(captionLayer)
        track.fillColor = HivePalette.surface.cgColor
        track.strokeColor = HivePalette.muted.cgColor
        track.lineWidth = 8
        fill.fillColor = UIColor.clear.cgColor
        fill.strokeColor = HivePalette.accent.cgColor
        fill.lineWidth = 8
        fill.lineCap = .round
        fill.strokeEnd = 0
        valueLayer.alignmentMode = .center
        valueLayer.contentsScale = 3
        valueLayer.foregroundColor = HivePalette.ink.cgColor
        captionLayer.alignmentMode = .center
        captionLayer.contentsScale = 3
        captionLayer.foregroundColor = HivePalette.muted.cgColor
        captionLayer.string = caption
        needsDisplayOnBoundsChange = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        track.frame = bounds
        fill.frame = bounds
        let path = hiveHexPath(in: bounds, inset: 10).cgPath
        track.path = path
        fill.path = path
        valueLayer.frame = CGRect(x: 12, y: bounds.midY - 28, width: bounds.width - 24, height: 36)
        captionLayer.frame = CGRect(x: 12, y: bounds.midY + 8, width: bounds.width - 24, height: 22)
        valueLayer.font = "Charter-Bold" as CFString
        valueLayer.fontSize = HiveType.font(.title, bold: true, tabular: true).pointSize
        captionLayer.font = "Charter-Roman" as CFString
        captionLayer.fontSize = HiveType.font(.caption).pointSize
        valueLayer.foregroundColor = HivePalette.ink.cgColor
        captionLayer.foregroundColor = HivePalette.muted.cgColor
        track.fillColor = HivePalette.surface.cgColor
        track.strokeColor = HivePalette.muted.cgColor
        fill.strokeColor = HivePalette.accent.cgColor
    }

    func setProgress(_ fraction: CGFloat, valueText: String, animated: Bool) {
        let clamped = min(max(fraction, 0), 1)
        valueLayer.string = valueText
        fill.strokeColor = fraction > 1 ? HivePalette.ink.cgColor : HivePalette.accent.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = fill.strokeEnd
            animation.toValue = clamped
            animation.duration = HiveMotion.duration
            animation.timingFunction = HiveMotion.timing()
            fill.strokeEnd = clamped
            fill.add(animation, forKey: "strokeEnd")
            if fraction > 1 {
                let pulse = CAKeyframeAnimation(keyPath: "lineWidth")
                pulse.values = [8, 12, 8]
                pulse.keyTimes = [0, 0.5, 1]
                pulse.duration = HiveMotion.duration
                pulse.timingFunction = HiveMotion.timing()
                fill.add(pulse, forKey: "pulse")
            }
        } else {
            fill.strokeEnd = clamped
        }
        CATransaction.commit()
    }
}

/// Honeycomb of member adherence hexes, drawn in a single layer.
final class HoneycombGridLayer: CALayer {
    struct Cell: Equatable {
        var title: String
        var valueText: String
        var fraction: CGFloat
    }

    var cells: [Cell] = [] {
        didSet { setNeedsDisplay() }
    }

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        contentsScale = 3
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let layer = layer as? HoneycombGridLayer {
            cells = layer.cells
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        needsDisplayOnBoundsChange = true
    }

    override func draw(in ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        let count = max(cells.count, 1)
        let columns = min(count, 4)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellW = bounds.width / CGFloat(columns)
        let cellH = bounds.height / CGFloat(max(rows, 1))
        for (index, cell) in cells.enumerated() {
            let col = index % columns
            let row = index / columns
            let rect = CGRect(
                x: CGFloat(col) * cellW,
                y: CGFloat(row) * cellH,
                width: cellW,
                height: cellH
            ).insetBy(dx: 4, dy: 4)
            let path = hiveHexPath(in: rect, inset: 2)
            ctx.setFillColor(HivePalette.surfaceCG)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
            ctx.saveGState()
            ctx.addPath(path.cgPath)
            ctx.clip()
            let fillH = rect.height * min(max(cell.fraction, 0), 1)
            ctx.setFillColor(HivePalette.accentCG)
            ctx.setAlpha(0.4)
            ctx.fill(CGRect(x: rect.minX, y: rect.maxY - fillH, width: rect.width, height: fillH))
            ctx.restoreGState()
            ctx.setStrokeColor(HivePalette.inkCG)
            ctx.setLineWidth(1.5)
            ctx.addPath(path.cgPath)
            ctx.strokePath()

            let value = cell.valueText as NSString
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: HiveType.font(.callout, bold: true, tabular: true),
                .foregroundColor: HivePalette.ink
            ]
            let valueSize = value.size(withAttributes: valueAttrs)
            value.draw(
                at: CGPoint(x: rect.midX - valueSize.width / 2, y: rect.midY - valueSize.height / 2 - 6),
                withAttributes: valueAttrs
            )
            let title = cell.title as NSString
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: HiveType.font(.caption),
                .foregroundColor: HivePalette.muted
            ]
            let titleSize = title.size(withAttributes: titleAttrs)
            title.draw(
                at: CGPoint(x: rect.midX - titleSize.width / 2, y: rect.midY + 8),
                withAttributes: titleAttrs
            )
        }
        UIGraphicsPopContext()
    }
}

final class CombCell: UIView {
    override class var layerClass: AnyClass { MacroCombLayer.self }

    var combLayer: MacroCombLayer {
        guard let layer = layer as? MacroCombLayer else {
            preconditionFailure("CombCell.layerClass is MacroCombLayer")
        }
        return layer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: CombCell, _) in
            view.combLayer.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isAccessibilityElement = true
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: CombCell, _) in
            view.combLayer.setNeedsDisplay()
        }
    }

    func render(caption: String, value: String, fraction: CGFloat, exceeded: Bool) {
        combLayer.caption = caption
        combLayer.valueText = value
        combLayer.fillFraction = fraction
        combLayer.exceeded = exceeded
        combLayer.setNeedsDisplay()
        accessibilityLabel = caption
        accessibilityValue = value
    }
}

final class ProgressCombView: UIView {
    override class var layerClass: AnyClass { ProgressCombLayer.self }

    var progressLayer: ProgressCombLayer {
        guard let layer = layer as? ProgressCombLayer else {
            preconditionFailure("ProgressCombView.layerClass is ProgressCombLayer")
        }
        return layer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "Energy"
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: ProgressCombView, _) in
            view.setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: ProgressCombView, _) in
            view.setNeedsLayout()
        }
    }
}

final class HoneycombGridView: UIView {
    override class var layerClass: AnyClass { HoneycombGridLayer.self }

    var gridLayer: HoneycombGridLayer {
        guard let layer = layer as? HoneycombGridLayer else {
            preconditionFailure("HoneycombGridView.layerClass is HoneycombGridLayer")
        }
        return layer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "Hive members"
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: HoneycombGridView, _) in
            view.gridLayer.setNeedsDisplay()
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: HoneycombGridView, _) in
            view.gridLayer.setNeedsDisplay()
        }
    }
}

final class CombEmptyView: UIView {
    let imageView = UIImageView()
    let titleLabel = UILabel()
    let bodyLabel = UILabel()
    let actionButton = UIButton(type: .system)

    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        titleLabel.font = HiveType.font(.title, bold: true)
        titleLabel.textColor = HivePalette.ink
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.font = HiveType.font(.body)
        bodyLabel.textColor = HivePalette.muted
        bodyLabel.numberOfLines = 0
        bodyLabel.adjustsFontForContentSizeCategory = true
        actionButton.titleLabel?.font = HiveType.font(.headline, bold: true)
        actionButton.setTitleColor(HivePalette.ink, for: .normal)
        actionButton.backgroundColor = HivePalette.accent
        actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        actionButton.addTarget(self, action: #selector(tap), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, bodyLabel, actionButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = HiveLayout.u(2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 120),
            imageView.widthAnchor.constraint(equalToConstant: 120)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("storyboard unused") // programmer error: this view is code-only
    }

    func render(image: String, title: String, body: String, action: String) {
        imageView.image = UIImage(named: image)
        titleLabel.text = title
        bodyLabel.text = body
        actionButton.setTitle(action, for: .normal)
        actionButton.accessibilityLabel = action
    }

    @objc private func tap() { onAction?() }
}

final class HiveTextField: UITextField {
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = HiveType.font(.body)
        textColor = HivePalette.ink
        backgroundColor = HivePalette.surface
        borderStyle = .none
        layer.borderColor = HivePalette.muted.cgColor
        layer.borderWidth = 1
        heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 44))
        leftViewMode = .always
        adjustsFontForContentSizeCategory = true
    }

    required init?(coder: NSCoder) {
        fatalError("storyboard unused") // programmer error: this view is code-only
    }
}

enum CombThumb {
    static func placeholder() -> UIImage? {
        UIImage(named: "mhv_ProductPlaceholder")
    }

    static func bundled(for product: CombProduct) -> UIImage? {
        if let name = product.shelfAsset, let image = UIImage(named: name) {
            return image
        }
        return placeholder()
    }
}

enum HiveVoice {
    static let searchIdle = "Type a name to forage Open Food Facts."
    static let searchEmpty = "The hive found no nectar under that name."
    static let searchError = "The foraging party lost the trail. Try again, or use the local shelf."
    static let notFound = "No comb in Open Food Facts matches this code."
    static let offline = "This comb is not on the local shelf and the hive is offline."
    static let missingEnergy = "Energy is unknown for this comb. Macros still apply."
    static let cameraDenied = "MacroHive needs the camera to read barcodes for the right hive member."
    static let cameraMissing = "No camera in this hive. Use a sample code or type a barcode."
    static let notMedical = "MacroHive is a personal food log, not medical advice. Nutrition data from Open Food Facts."
}
