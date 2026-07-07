import AppKit

private let settingsWindowWidth: CGFloat = 360
private let settingsWindowHeight: CGFloat = 340
private let settingsPadding: CGFloat = 16
private let settingsRowSpacing: CGFloat = 10
private let settingsSectionPadding: CGFloat = 14
private let settingsLabelWidth: CGFloat = 128
private let settingsValueWidth: CGFloat = 44
private let colorPresetMenuWidth: CGFloat = 150
private let colorSwatchGlyph = "■"

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(configuration: AppConfiguration, onChange: @escaping (AppConfiguration) -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let settingsView = SettingsView(configuration: configuration, onChange: onChange)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: settingsWindowWidth, height: settingsWindowHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GlanceBar Settings"
        window.contentView = settingsView
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
private final class SettingsView: NSView {
    private var configuration: AppConfiguration
    private let onChange: (AppConfiguration) -> Void
    private let pollingValueLabel = NSTextField(labelWithString: "")
    private let gpuMultiplierValueLabel = NSTextField(labelWithString: "")
    private let yellowThresholdValueLabel = NSTextField(labelWithString: "")
    private let thresholdValueLabel = NSTextField(labelWithString: "")
    private let gpuEnabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let pollingStepper = NSStepper()
    private let gpuMultiplierStepper = NSStepper()
    private let yellowThresholdStepper = NSStepper()
    private let thresholdStepper = NSStepper()
    private let yellowColorMenu = NSPopUpButton()
    private let warningColorMenu = NSPopUpButton()
    private let uploadColorMenu = NSPopUpButton()
    private let downloadColorMenu = NSPopUpButton()
    private let baseTextColorMenu = NSPopUpButton()
    private let labelTextColorMenu = NSPopUpButton()
    init(configuration: AppConfiguration, onChange: @escaping (AppConfiguration) -> Void) {
        self.configuration = configuration
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: settingsWindowWidth, height: settingsWindowHeight))
        buildView()
        syncControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    private func buildView() {
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabView)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: settingsPadding),
            tabView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -settingsPadding),
            tabView.topAnchor.constraint(equalTo: topAnchor, constant: settingsPadding),
            tabView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -settingsPadding)
        ])

        tabView.addTabViewItem(makeTabViewItem(label: "Metrics", arrangedSubviews: [
            makeNumberRow(label: "Polling", valueLabel: pollingValueLabel, stepper: pollingStepper),
            makeCheckboxRow(label: "GPU", checkbox: gpuEnabledButton),
            makeNumberRow(label: "GPU every", valueLabel: gpuMultiplierValueLabel, stepper: gpuMultiplierStepper),
            makeNumberRow(label: "Yellow above", valueLabel: yellowThresholdValueLabel, stepper: yellowThresholdStepper),
            makeNumberRow(label: "Red above", valueLabel: thresholdValueLabel, stepper: thresholdStepper)
        ]))
        tabView.addTabViewItem(makeTabViewItem(label: "Colors", arrangedSubviews: [
            makeColorRow(label: "Yellow", colorMenu: yellowColorMenu),
            makeColorRow(label: "Over threshold", colorMenu: warningColorMenu),
            makeColorRow(label: "Upload", colorMenu: uploadColorMenu),
            makeColorRow(label: "Download", colorMenu: downloadColorMenu),
            makeColorRow(label: "Base text", colorMenu: baseTextColorMenu),
            makeColorRow(label: "Label text", colorMenu: labelTextColorMenu)
        ]))
        configureControls()
    }

    private func makeTabViewItem(label: String, arrangedSubviews: [NSView]) -> NSTabViewItem {
        let tabViewItem = NSTabViewItem(identifier: label)
        let contentView = NSView()
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = settingsRowSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        for arrangedSubview in arrangedSubviews {
            stackView.addArrangedSubview(arrangedSubview)
        }

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: settingsSectionPadding),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -settingsSectionPadding),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: settingsSectionPadding),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -settingsSectionPadding)
        ])

        tabViewItem.label = label
        tabViewItem.view = contentView

        return tabViewItem
    }

    private func configureControls() {
        pollingStepper.target = self
        pollingStepper.action = #selector(updatePollingInterval)
        gpuEnabledButton.target = self
        gpuEnabledButton.action = #selector(updateGpuEnabled)
        gpuMultiplierStepper.target = self
        gpuMultiplierStepper.action = #selector(updateGpuPollingMultiplier)
        yellowThresholdStepper.target = self
        yellowThresholdStepper.action = #selector(updateYellowThreshold)
        thresholdStepper.target = self
        thresholdStepper.action = #selector(updateWarningThreshold)
        configureColorMenu(yellowColorMenu, presets: colorPresets, action: #selector(updateYellowColor))
        configureColorMenu(warningColorMenu, presets: colorPresets, action: #selector(updateWarningColor))
        configureColorMenu(uploadColorMenu, presets: colorPresets, action: #selector(updateUploadColor))
        configureColorMenu(downloadColorMenu, presets: colorPresets, action: #selector(updateDownloadColor))
        configureColorMenu(baseTextColorMenu, presets: textColorPresets, action: #selector(updateBaseTextColor))
        configureColorMenu(labelTextColorMenu, presets: textColorPresets, action: #selector(updateLabelTextColor))
    }

    private func makeNumberRow(label: String, valueLabel: NSTextField, stepper: NSStepper) -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: label)
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: settingsValueWidth).isActive = true
        stepper.controlSize = .small

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(stepper)

        return row
    }

    private func makeCheckboxRow(label: String, checkbox: NSButton) -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: label)
        checkbox.controlSize = .small

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(checkbox)

        return row
    }

    private func makeColorRow(label: String, colorMenu: NSPopUpButton) -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: label)
        colorMenu.controlSize = .small
        colorMenu.widthAnchor.constraint(equalToConstant: colorPresetMenuWidth).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(colorMenu)

        return row
    }

    private func makeRowStackView() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: settingsWindowWidth - settingsPadding * 2 - settingsSectionPadding * 2).isActive = true

        return row
    }

    private func makeTitleLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: settingsLabelWidth).isActive = true

        return label
    }

    private func configureColorMenu(_ colorMenu: NSPopUpButton, presets: [ColorPreset], action: Selector) {
        colorMenu.removeAllItems()
        colorMenu.target = self
        colorMenu.action = action

        for colorPreset in presets {
            let title = "\(colorSwatchGlyph) \(colorPreset.title)"
            colorMenu.addItem(withTitle: title)
            colorMenu.item(withTitle: title)?.representedObject = colorPreset.id
            colorMenu.item(withTitle: title)?.attributedTitle = makeColorPresetTitle(colorPreset: colorPreset)
        }
    }

    private func makeColorPresetTitle(colorPreset: ColorPreset) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: "\(colorSwatchGlyph) ",
            attributes: [
                .foregroundColor: colorPreset.color,
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
            ]
        )
        title.append(
            NSAttributedString(
                string: colorPreset.title,
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 12)
                ]
            )
        )

        return title
    }

    private func syncControls() {
        pollingStepper.minValue = minimumPollingIntervalInSeconds
        pollingStepper.maxValue = maximumPollingIntervalInSeconds
        pollingStepper.increment = 1
        pollingStepper.doubleValue = configuration.pollingIntervalInSeconds
        pollingValueLabel.stringValue = "\(Int(configuration.pollingIntervalInSeconds))s"

        gpuEnabledButton.state = configuration.isGpuEnabled ? .on : .off
        gpuMultiplierStepper.minValue = Double(minimumGpuPollingMultiplier)
        gpuMultiplierStepper.maxValue = Double(maximumGpuPollingMultiplier)
        gpuMultiplierStepper.increment = 1
        gpuMultiplierStepper.integerValue = configuration.gpuPollingMultiplier
        gpuMultiplierStepper.isEnabled = configuration.isGpuEnabled
        gpuMultiplierValueLabel.stringValue = "\(configuration.gpuPollingMultiplier)x"
        gpuMultiplierValueLabel.textColor = configuration.isGpuEnabled ? .labelColor : .disabledControlTextColor

        yellowThresholdStepper.minValue = Double(minimumWarningThresholdPercent)
        yellowThresholdStepper.maxValue = Double(max(minimumWarningThresholdPercent, configuration.warningThresholdPercent - 1))
        yellowThresholdStepper.increment = 1
        yellowThresholdStepper.integerValue = configuration.yellowThresholdPercent
        yellowThresholdValueLabel.stringValue = "\(configuration.yellowThresholdPercent)%"

        thresholdStepper.minValue = Double(minimumWarningThresholdPercent)
        thresholdStepper.maxValue = Double(maximumWarningThresholdPercent)
        thresholdStepper.increment = 1
        thresholdStepper.integerValue = configuration.warningThresholdPercent
        thresholdValueLabel.stringValue = "\(configuration.warningThresholdPercent)%"

        selectColorPreset(id: configuration.yellowColorID, in: yellowColorMenu)
        selectColorPreset(id: configuration.warningColorID, in: warningColorMenu)
        selectColorPreset(id: configuration.uploadColorID, in: uploadColorMenu)
        selectColorPreset(id: configuration.downloadColorID, in: downloadColorMenu)
        selectTextColorPreset(id: configuration.baseTextColorID, in: baseTextColorMenu)
        selectTextColorPreset(id: configuration.labelTextColorID, in: labelTextColorMenu)

    }

    private func selectColorPreset(id colorID: String, in colorMenu: NSPopUpButton) {
        guard let colorPreset = getColorPreset(id: colorID) else {
            return
        }

        colorMenu.selectItem(withTitle: "\(colorSwatchGlyph) \(colorPreset.title)")
    }

    private func selectTextColorPreset(id colorID: String, in colorMenu: NSPopUpButton) {
        guard let colorPreset = getTextColorPreset(id: colorID) else {
            return
        }

        colorMenu.selectItem(withTitle: "\(colorSwatchGlyph) \(colorPreset.title)")
    }

    private func selectedColorID(in colorMenu: NSPopUpButton, fallback: String) -> String {
        guard let maybeColorID = colorMenu.selectedItem?.representedObject as? String else {
            return fallback
        }

        return getColorPreset(id: maybeColorID)?.id ?? fallback
    }

    private func selectedTextColorID(in colorMenu: NSPopUpButton, fallback: String) -> String {
        guard let maybeColorID = colorMenu.selectedItem?.representedObject as? String else {
            return fallback
        }

        return getTextColorPreset(id: maybeColorID)?.id ?? fallback
    }

    private func makeConfiguration(
        pollingIntervalInSeconds: TimeInterval? = nil,
        isGpuEnabled: Bool? = nil,
        gpuPollingMultiplier: Int? = nil,
        yellowThresholdPercent: Int? = nil,
        yellowColorID: String? = nil,
        warningThresholdPercent: Int? = nil,
        warningColorID: String? = nil,
        uploadColorID: String? = nil,
        downloadColorID: String? = nil,
        baseTextColorID: String? = nil,
        labelTextColorID: String? = nil
    ) -> AppConfiguration {
        AppConfiguration(
            pollingIntervalInSeconds: pollingIntervalInSeconds ?? configuration.pollingIntervalInSeconds,
            isGpuEnabled: isGpuEnabled ?? configuration.isGpuEnabled,
            gpuPollingMultiplier: gpuPollingMultiplier ?? configuration.gpuPollingMultiplier,
            yellowThresholdPercent: yellowThresholdPercent ?? configuration.yellowThresholdPercent,
            yellowColorID: yellowColorID ?? configuration.yellowColorID,
            warningThresholdPercent: warningThresholdPercent ?? configuration.warningThresholdPercent,
            warningColorID: warningColorID ?? configuration.warningColorID,
            uploadColorID: uploadColorID ?? configuration.uploadColorID,
            downloadColorID: downloadColorID ?? configuration.downloadColorID,
            baseTextColorID: baseTextColorID ?? configuration.baseTextColorID,
            labelTextColorID: labelTextColorID ?? configuration.labelTextColorID
        )
    }

    @objc private func updatePollingInterval() {
        configuration = makeConfiguration(pollingIntervalInSeconds: pollingStepper.doubleValue)
        syncControls()
        onChange(configuration)
    }

    @objc private func updateGpuEnabled() {
        configuration = makeConfiguration(isGpuEnabled: gpuEnabledButton.state == .on)
        syncControls()
        onChange(configuration)
    }

    @objc private func updateGpuPollingMultiplier() {
        configuration = makeConfiguration(gpuPollingMultiplier: gpuMultiplierStepper.integerValue)
        syncControls()
        onChange(configuration)
    }

    @objc private func updateYellowThreshold() {
        configuration = makeConfiguration(yellowThresholdPercent: yellowThresholdStepper.integerValue)
        syncControls()
        onChange(configuration)
    }

    @objc private func updateWarningThreshold() {
        configuration = makeConfiguration(warningThresholdPercent: thresholdStepper.integerValue)
        syncControls()
        onChange(configuration)
    }

    @objc private func updateYellowColor() {
        configuration = makeConfiguration(yellowColorID: selectedColorID(in: yellowColorMenu, fallback: configuration.yellowColorID))
        onChange(configuration)
    }

    @objc private func updateWarningColor() {
        configuration = makeConfiguration(warningColorID: selectedColorID(in: warningColorMenu, fallback: configuration.warningColorID))
        onChange(configuration)
    }

    @objc private func updateUploadColor() {
        configuration = makeConfiguration(uploadColorID: selectedColorID(in: uploadColorMenu, fallback: configuration.uploadColorID))
        onChange(configuration)
    }

    @objc private func updateDownloadColor() {
        configuration = makeConfiguration(downloadColorID: selectedColorID(in: downloadColorMenu, fallback: configuration.downloadColorID))
        onChange(configuration)
    }

    @objc private func updateBaseTextColor() {
        configuration = makeConfiguration(baseTextColorID: selectedTextColorID(in: baseTextColorMenu, fallback: configuration.baseTextColorID))
        onChange(configuration)
    }

    @objc private func updateLabelTextColor() {
        configuration = makeConfiguration(labelTextColorID: selectedTextColorID(in: labelTextColorMenu, fallback: configuration.labelTextColorID))
        onChange(configuration)
    }

}
