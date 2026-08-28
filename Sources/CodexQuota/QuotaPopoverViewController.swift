import AppKit
import CodexQuotaCore
import Foundation

@MainActor
final class QuotaPopoverViewController: NSViewController {
    var onRefresh: (() -> Void)?
    var onIntervalChanged: ((RefreshIntervalOption) -> Void)?
    var onQuit: (() -> Void)?
    var onPreferredContentSizeChanged: ((NSSize) -> Void)?

    private let fiveHourSection = QuotaSectionView(title: "5小时额度")
    private let weeklySection = QuotaSectionView(title: "1周额度")
    private let fiveHourSeparator = NSBox()
    private let resetCreditCountLabel = NSTextField(labelWithString: "正在读取")
    private let resetCreditRowsStack = NSStackView()
    private let intervalButton = MenuRowButton(
        title: "刷新频率",
        trailingText: "1分钟  ›",
        target: nil,
        action: nil
    )
    private let intervalOptionsStack = NSStackView()
    private var intervalOptionButtons: [IntervalChipButton] = []
    private var selectedInterval: RefreshIntervalOption = .oneMinute
    private var intervalOptionsAreExpanded = false
    private var contentStack: NSStackView?

    private static let panelWidth: CGFloat = 252
    private static let horizontalInset: CGFloat = 16
    private static let verticalInset: CGFloat = 12

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 220))

        let resetCreditTitleLabel = titleLabel("重置卡")
        configureValueLabel(resetCreditCountLabel)
        let resetCreditHeader = horizontalRow(
            left: resetCreditTitleLabel,
            right: resetCreditCountLabel
        )

        resetCreditRowsStack.orientation = .vertical
        resetCreditRowsStack.alignment = .leading
        resetCreditRowsStack.spacing = 4
        resetCreditRowsStack.isHidden = true

        let resetCreditSection = verticalStack([
            resetCreditHeader,
            resetCreditRowsStack,
        ], spacing: 6)

        intervalButton.target = self
        intervalButton.action = #selector(toggleIntervalOptions)
        configureIntervalOptions()

        let refreshButton = MenuRowButton(
            title: "立即刷新",
            trailingText: "⌘R",
            keyEquivalent: "r",
            target: self,
            action: #selector(refreshClicked)
        )
        let quitButton = MenuRowButton(
            title: "退出工具",
            trailingText: "⌘Q",
            keyEquivalent: "q",
            target: self,
            action: #selector(quitClicked)
        )
        let actionStack = verticalStack([refreshButton, quitButton], spacing: 0)

        fiveHourSeparator.boxType = .separator
        let weeklySeparator = separator()
        let resetCreditSeparator = separator()
        let refreshSeparator = separator()
        let contentStack = verticalStack([
            fiveHourSection,
            fiveHourSeparator,
            weeklySection,
            weeklySeparator,
            resetCreditSection,
            resetCreditSeparator,
            intervalButton,
            intervalOptionsStack,
            refreshSeparator,
            actionStack,
        ], spacing: 0)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        contentStack.setCustomSpacing(10, after: fiveHourSection)
        contentStack.setCustomSpacing(10, after: fiveHourSeparator)
        contentStack.setCustomSpacing(10, after: weeklySection)
        contentStack.setCustomSpacing(10, after: weeklySeparator)
        contentStack.setCustomSpacing(10, after: resetCreditSection)
        contentStack.setCustomSpacing(5, after: resetCreditSeparator)
        contentStack.setCustomSpacing(5, after: intervalButton)
        contentStack.setCustomSpacing(5, after: intervalOptionsStack)
        contentStack.setCustomSpacing(5, after: refreshSeparator)

        rootView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            rootView.widthAnchor.constraint(equalToConstant: Self.panelWidth),
            contentStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Self.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Self.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Self.verticalInset),
            fiveHourSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            weeklySection.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            resetCreditSection.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            resetCreditHeader.widthAnchor.constraint(equalTo: resetCreditSection.widthAnchor),
            resetCreditRowsStack.widthAnchor.constraint(equalTo: resetCreditSection.widthAnchor),
            intervalButton.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            intervalOptionsStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            actionStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            fiveHourSeparator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            weeklySeparator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            resetCreditSeparator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            refreshSeparator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            refreshButton.widthAnchor.constraint(equalTo: actionStack.widthAnchor),
            quitButton.widthAnchor.constraint(equalTo: actionStack.widthAnchor),
        ])
        self.contentStack = contentStack
        view = rootView
        updatePreferredContentSize()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        setIntervalOptionsExpanded(false)
    }

    func update(
        state: QuotaState,
        interval: RefreshIntervalOption
    ) {
        _ = view
        selectedInterval = interval
        updateIntervalPresentation()

        switch state {
        case .loading:
            setFiveHourSectionVisible(true)
            fiveHourSection.setLoading()
            weeklySection.setLoading()
            updateResetCredits(nil, placeholder: "正在读取")
        case let .available(snapshot):
            if let fiveHour = snapshot.fiveHour {
                setFiveHourSectionVisible(true)
                update(section: fiveHourSection, with: fiveHour)
            } else {
                setFiveHourSectionVisible(false)
            }
            update(section: weeklySection, with: snapshot.weekly)
            if let credits = snapshot.resetCredits {
                updateResetCredits(credits, placeholder: nil)
            } else {
                updateResetCredits(nil, placeholder: "暂不可用")
            }
        case let .unavailable(message):
            setFiveHourSectionVisible(false)
            weeklySection.setUnavailable(message: message)
            updateResetCredits(nil, placeholder: "读取失败")
        }
        updatePreferredContentSize()
    }

    func collapseIntervalOptions() {
        guard isViewLoaded else { return }
        setIntervalOptionsExpanded(false)
    }

    private func update(section: QuotaSectionView, with quota: QuotaWindow) {
        section.setAvailable(
            remainingPercent: quota.remainingPercent,
            countdown: Self.countdownText(to: quota.resetsAt),
            resetDate: Self.fullDateFormatter.string(from: quota.resetsAt)
        )
    }

    private func setFiveHourSectionVisible(_ visible: Bool) {
        fiveHourSection.isHidden = !visible
        fiveHourSeparator.isHidden = !visible
    }

    private func updateResetCredits(
        _ credits: [RateLimitResetCredit]?,
        placeholder: String?
    ) {
        for row in resetCreditRowsStack.arrangedSubviews {
            resetCreditRowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        guard let credits else {
            resetCreditCountLabel.stringValue = placeholder ?? "暂不可用"
            resetCreditRowsStack.isHidden = true
            return
        }

        resetCreditCountLabel.stringValue = "\(credits.count)张"
        for (index, credit) in credits.enumerated() {
            let expiry = Self.fullDateFormatter.string(from: credit.expiresAt)
            let row = NSTextField(labelWithString: "\(index + 1).过期时间：\(expiry)")
            row.font = .systemFont(ofSize: 11)
            row.textColor = .secondaryLabelColor
            row.lineBreakMode = .byTruncatingTail
            resetCreditRowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: resetCreditRowsStack.widthAnchor).isActive = true
        }
        resetCreditRowsStack.isHidden = credits.isEmpty
    }

    private func updatePreferredContentSize() {
        guard let contentStack else { return }
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let height = ceil(contentStack.fittingSize.height + Self.verticalInset * 2)
        let size = NSSize(width: Self.panelWidth, height: height)
        guard size != preferredContentSize else { return }
        preferredContentSize = size
        onPreferredContentSizeChanged?(size)
    }

    private func configureIntervalOptions() {
        intervalOptionsStack.orientation = .vertical
        intervalOptionsStack.alignment = .leading
        intervalOptionsStack.spacing = 5
        intervalOptionsStack.isHidden = true

        for options in RefreshIntervalPresentation.rows {
            let buttons = options.map { option in
                let button = IntervalChipButton(option: option)
                button.target = self
                button.action = #selector(intervalChipSelected(_:))
                intervalOptionButtons.append(button)
                return button
            }
            let row = NSStackView(views: buttons)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = 4
            intervalOptionsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: intervalOptionsStack.widthAnchor).isActive = true
        }
    }

    @objc private func toggleIntervalOptions() {
        setIntervalOptionsExpanded(!intervalOptionsAreExpanded)
    }

    @objc private func intervalChipSelected(_ sender: IntervalChipButton) {
        let option = sender.option
        selectedInterval = option
        updateIntervalPresentation()
        onIntervalChanged?(option)
        setIntervalOptionsExpanded(false)
    }

    private func setIntervalOptionsExpanded(_ expanded: Bool) {
        guard intervalOptionsAreExpanded != expanded else { return }
        intervalOptionsAreExpanded = expanded
        intervalOptionsStack.isHidden = !expanded
        updateIntervalPresentation()
        updatePreferredContentSize()
    }

    private func updateIntervalPresentation() {
        let arrow = intervalOptionsAreExpanded ? "⌃" : "⌄"
        intervalButton.trailingText = "\(selectedInterval.title)  \(arrow)"
        for button in intervalOptionButtons {
            button.isSelected = button.option == selectedInterval
        }
    }

    @objc private func refreshClicked() {
        onRefresh?()
    }

    @objc private func quitClicked() {
        onQuit?()
    }

    private func titleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func configureValueLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func horizontalRow(left: NSView, right: NSView) -> NSStackView {
        let row = NSStackView(views: [left, right])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10
        left.setContentHuggingPriority(.defaultLow, for: .horizontal)
        right.setContentHuggingPriority(.required, for: .horizontal)
        return row
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private static func countdownText(to date: Date, now: Date = Date()) -> String {
        let totalMinutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let days = totalMinutes / (24 * 60)
        let hours = totalMinutes % (24 * 60) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)天\(hours)小时后重置" : "\(days)天后重置"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)小时\(minutes)分钟后重置" : "\(hours)小时后重置"
        }
        if minutes > 0 {
            return "\(minutes)分钟后重置"
        }
        return "即将重置"
    }

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}

private final class QuotaSectionView: NSStackView {
    private let remainingLabel = NSTextField(labelWithString: "正在读取")
    private let progressView = QuotaProgressView()
    private let countdownLabel = NSTextField(labelWithString: "正在读取额度")
    private let resetDateLabel = NSTextField(wrappingLabelWithString: "重置时间：--")

    init(title: String) {
        super.init(frame: .zero)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        remainingLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        remainingLabel.textColor = .labelColor
        remainingLabel.alignment = .right
        remainingLabel.setContentHuggingPriority(.required, for: .horizontal)

        let header = NSStackView(views: [titleLabel, remainingLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        header.spacing = 10
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.heightAnchor.constraint(equalToConstant: 6).isActive = true

        countdownLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countdownLabel.textColor = .labelColor

        resetDateLabel.font = .systemFont(ofSize: 11)
        resetDateLabel.textColor = .secondaryLabelColor
        resetDateLabel.maximumNumberOfLines = 2

        orientation = .vertical
        alignment = .leading
        spacing = 7
        addArrangedSubview(header)
        addArrangedSubview(progressView)
        addArrangedSubview(countdownLabel)
        addArrangedSubview(resetDateLabel)

        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: widthAnchor),
            progressView.widthAnchor.constraint(equalTo: widthAnchor),
            countdownLabel.widthAnchor.constraint(equalTo: widthAnchor),
            resetDateLabel.widthAnchor.constraint(equalTo: widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("不支持从归档创建额度区域")
    }

    func setLoading() {
        remainingLabel.stringValue = "正在读取"
        progressView.percent = nil
        countdownLabel.stringValue = "正在读取额度"
        resetDateLabel.stringValue = "重置时间：--"
    }

    func setAvailable(
        remainingPercent: Int,
        countdown: String,
        resetDate: String
    ) {
        remainingLabel.stringValue = "剩余 \(remainingPercent)%"
        progressView.percent = remainingPercent
        countdownLabel.stringValue = countdown
        resetDateLabel.stringValue = "重置时间：\(resetDate)"
    }

    func setUnavailable(message: String) {
        remainingLabel.stringValue = "--%"
        progressView.percent = nil
        countdownLabel.stringValue = "额度读取失败"
        resetDateLabel.stringValue = message
    }
}

private final class QuotaProgressView: NSView {
    var percent: Int? {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let trackRect = bounds.insetBy(dx: 0, dy: 1)
        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackRect.height / 2,
            yRadius: trackRect.height / 2
        )
        NSColor.quaternaryLabelColor.setFill()
        trackPath.fill()

        guard let percent, percent > 0 else { return }
        let fillWidth = trackRect.width * CGFloat(min(percent, 100)) / 100
        let fillRect = NSRect(
            x: trackRect.minX,
            y: trackRect.minY,
            width: fillWidth,
            height: trackRect.height
        )
        let fillPath = NSBezierPath(
            roundedRect: fillRect,
            xRadius: fillRect.height / 2,
            yRadius: fillRect.height / 2
        )
        Self.color(for: percent).setFill()
        fillPath.fill()
    }

    private static func color(for percent: Int) -> NSColor {
        switch QuotaPresentation.colorBand(for: percent) {
        case .healthy:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .critical:
            return .systemRed
        }
    }
}

private final class IntervalChipButton: NSButton {
    let option: RefreshIntervalOption
    var isSelected = false {
        didSet {
            setAccessibilityValue(isSelected ? "已选择" : "未选择")
            needsDisplay = true
        }
    }
    private var isHovered = false
    private var trackingAreaReference: NSTrackingArea?

    init(option: RefreshIntervalOption) {
        self.option = option
        super.init(frame: .zero)
        title = option.compactTitle
        isBordered = false
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        setAccessibilityLabel(option.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建刷新频率按钮")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let backgroundColor: NSColor
        if isSelected {
            backgroundColor = .controlAccentColor
        } else if isHovered || isHighlighted {
            backgroundColor = .unemphasizedSelectedContentBackgroundColor
        } else {
            backgroundColor = .quaternaryLabelColor
        }
        backgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular),
            .foregroundColor: isSelected ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor,
        ]
        let textSize = title.size(withAttributes: attributes)
        title.draw(
            at: NSPoint(
                x: (bounds.width - textSize.width) / 2,
                y: (bounds.height - textSize.height) / 2
            ),
            withAttributes: attributes
        )
    }
}

private final class MenuRowButton: NSButton {
    var trailingText: String {
        didSet {
            needsDisplay = true
        }
    }
    private var isHovered = false
    private var trackingAreaReference: NSTrackingArea?

    init(
        title: String,
        trailingText: String,
        keyEquivalent: String = "",
        target: AnyObject?,
        action: Selector?
    ) {
        self.trailingText = trailingText
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        if !keyEquivalent.isEmpty {
            self.keyEquivalent = keyEquivalent
            keyEquivalentModifierMask = .command
        }
        isBordered = false
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 21).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建菜单按钮")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered || isHighlighted {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
        ]
        let trailingAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let titleSize = title.size(withAttributes: titleAttributes)
        let trailingSize = trailingText.size(withAttributes: trailingAttributes)
        title.draw(
            at: NSPoint(x: 0, y: (bounds.height - titleSize.height) / 2),
            withAttributes: titleAttributes
        )
        trailingText.draw(
            at: NSPoint(
                x: bounds.width - trailingSize.width,
                y: (bounds.height - trailingSize.height) / 2
            ),
            withAttributes: trailingAttributes
        )
    }
}
