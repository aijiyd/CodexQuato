import AppKit
import CodexQuotaCore
import Foundation

@MainActor
final class QuotaPopoverViewController: NSViewController {
    var onRefresh: (() -> Void)?
    var onIntervalChanged: ((RefreshIntervalOption) -> Void)?
    var onLoginItemChanged: ((Bool) -> Void)?
    var onQuit: (() -> Void)?
    var onPreferredContentSizeChanged: ((NSSize) -> Void)?

    private let resetLabel = NSTextField(wrappingLabelWithString: "额度重置：正在读取")
    private let resetCreditCountLabel = NSTextField(labelWithString: "重置卡：正在读取")
    private let resetCreditRowsStack = NSStackView()
    private let intervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let loginItemCheckbox = NSButton(
        checkboxWithTitle: "登录时启动",
        target: nil,
        action: nil
    )
    private var selectedInterval: RefreshIntervalOption = .oneMinute
    private var contentStack: NSStackView?

    private static let panelWidth: CGFloat = 252
    private static let horizontalInset: CGFloat = 14
    private static let verticalInset: CGFloat = 12

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 145))

        resetLabel.font = .systemFont(ofSize: 12)
        resetLabel.textColor = .labelColor
        resetLabel.maximumNumberOfLines = 2

        resetCreditCountLabel.font = .systemFont(ofSize: 12, weight: .medium)
        resetCreditCountLabel.textColor = .labelColor

        resetCreditRowsStack.orientation = .vertical
        resetCreditRowsStack.alignment = .leading
        resetCreditRowsStack.spacing = 4
        resetCreditRowsStack.isHidden = true

        let resetCreditSeparator = separator()
        let quotaInfoStack = NSStackView(views: [
            resetLabel,
            resetCreditSeparator,
            resetCreditCountLabel,
            resetCreditRowsStack,
        ])
        quotaInfoStack.orientation = .vertical
        quotaInfoStack.alignment = .leading
        quotaInfoStack.spacing = 4

        let refreshTitle = NSTextField(labelWithString: "刷新频率")
        refreshTitle.font = .systemFont(ofSize: 12)
        intervalPopup.target = self
        intervalPopup.action = #selector(intervalChanged)
        intervalPopup.controlSize = .small
        for option in RefreshIntervalOption.allCases {
            intervalPopup.addItem(withTitle: option.title)
            intervalPopup.lastItem?.tag = option.rawValue
        }

        let refreshRow = NSStackView(views: [refreshTitle, intervalPopup])
        refreshRow.orientation = .horizontal
        refreshRow.alignment = .centerY
        refreshRow.distribution = .fill
        refreshRow.spacing = 12
        refreshTitle.setContentHuggingPriority(.defaultLow, for: .horizontal)
        intervalPopup.setContentHuggingPriority(.required, for: .horizontal)

        loginItemCheckbox.target = self
        loginItemCheckbox.action = #selector(loginItemChanged)
        loginItemCheckbox.font = .systemFont(ofSize: 12)

        let settingsStack = NSStackView(views: [refreshRow, loginItemCheckbox])
        settingsStack.orientation = .vertical
        settingsStack.alignment = .leading
        settingsStack.spacing = 8

        let refreshButton = NSButton(title: "立即刷新", target: self, action: #selector(refreshClicked))
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small
        let quitButton = NSButton(title: "退出工具", target: self, action: #selector(quitClicked))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .small

        let buttonRow = NSStackView(views: [refreshButton, quitButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 8

        let topSeparator = separator()
        let bottomSeparator = separator()
        let contentStack = NSStackView(views: [
            quotaInfoStack,
            topSeparator,
            settingsStack,
            bottomSeparator,
            buttonRow,
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            rootView.widthAnchor.constraint(equalToConstant: Self.panelWidth),
            contentStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: Self.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -Self.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: Self.verticalInset),
            quotaInfoStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            resetLabel.widthAnchor.constraint(equalTo: quotaInfoStack.widthAnchor),
            resetCreditSeparator.widthAnchor.constraint(equalTo: quotaInfoStack.widthAnchor),
            resetCreditCountLabel.widthAnchor.constraint(equalTo: quotaInfoStack.widthAnchor),
            resetCreditRowsStack.widthAnchor.constraint(equalTo: quotaInfoStack.widthAnchor),
            settingsStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            refreshRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            topSeparator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            bottomSeparator.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])
        self.contentStack = contentStack
        view = rootView
        updatePreferredContentSize()
    }

    func update(
        state: QuotaState,
        interval: RefreshIntervalOption,
        loginItemState: LoginItemState
    ) {
        _ = view
        selectedInterval = interval
        intervalPopup.selectItem(withTag: interval.rawValue)
        updateLoginItem(state: loginItemState)

        switch state {
        case .loading:
            resetLabel.stringValue = "额度重置：正在读取"
            updateResetCredits(nil, placeholder: "重置卡：正在读取")
        case let .available(quota):
            resetLabel.stringValue = "额度重置：\(Self.fullDateFormatter.string(from: quota.resetsAt))"
            if let credits = quota.resetCredits {
                updateResetCredits(credits, placeholder: nil)
            } else {
                updateResetCredits(nil, placeholder: "重置卡：暂不可用")
            }
        case let .unavailable(message):
            resetLabel.stringValue = "额度重置：读取失败（\(message)）"
            updateResetCredits(nil, placeholder: "重置卡：读取失败")
        }
        updatePreferredContentSize()
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
            resetCreditCountLabel.stringValue = placeholder ?? "重置卡：暂不可用"
            resetCreditRowsStack.isHidden = true
            return
        }

        resetCreditCountLabel.stringValue = "重置卡：\(credits.count) 张"
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
        view.frame.size = size
        onPreferredContentSizeChanged?(size)
    }

    private func updateLoginItem(state: LoginItemState) {
        loginItemCheckbox.allowsMixedState = true
        loginItemCheckbox.isEnabled = true
        switch state {
        case .enabled:
            loginItemCheckbox.state = .on
            loginItemCheckbox.title = "登录时启动"
        case .disabled:
            loginItemCheckbox.state = .off
            loginItemCheckbox.title = "登录时启动"
        case .requiresApproval:
            loginItemCheckbox.state = .mixed
            loginItemCheckbox.title = "登录时启动（待系统批准）"
        case .unavailable:
            loginItemCheckbox.state = .off
            loginItemCheckbox.title = "登录时启动（不可用）"
            loginItemCheckbox.isEnabled = false
        }
    }

    @objc private func intervalChanged() {
        guard let option = RefreshIntervalOption(rawValue: intervalPopup.selectedTag()) else {
            intervalPopup.selectItem(withTag: selectedInterval.rawValue)
            return
        }
        selectedInterval = option
        onIntervalChanged?(option)
    }

    @objc private func loginItemChanged() {
        onLoginItemChanged?(loginItemCheckbox.state == .on)
    }

    @objc private func refreshClicked() {
        onRefresh?()
    }

    @objc private func quitClicked() {
        onQuit?()
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
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
