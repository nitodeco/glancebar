import AppKit

private let settingsWindowWidth: CGFloat = 360
private let settingsWindowHeight: CGFloat = 410
private let settingsPadding: CGFloat = 16
private let settingsRowSpacing: CGFloat = 10
private let settingsSectionPadding: CGFloat = 14
private let settingsLabelWidth: CGFloat = 128
private let settingsValueWidth: CGFloat = 44
private let colorPresetMenuWidth: CGFloat = 150
private let advancedSliderWidth: CGFloat = 150
private let advancedPreviewSize: CGFloat = 28
private let metricListHeight: CGFloat = 116
private let metricCheckboxColumnID = NSUserInterfaceItemIdentifier("enabled")
private let metricNameColumnID = NSUserInterfaceItemIdentifier("metric")
private let metricPasteboardType = NSPasteboard.PasteboardType("dev.nitodeco.glancebar.metric")
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
private final class SettingsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private var configuration: AppConfiguration
    private let onChange: (AppConfiguration) -> Void
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let pollingValueLabel = NSTextField(labelWithString: "")
    private let gpuMultiplierValueLabel = NSTextField(labelWithString: "")
    private let yellowThresholdValueLabel = NSTextField(labelWithString: "")
    private let thresholdValueLabel = NSTextField(labelWithString: "")
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
    private let autoTextContrastButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let advancedColorRoleMenu = NSPopUpButton()
    private let advancedHueSlider = NSSlider()
    private let advancedSaturationSlider = NSSlider()
    private let advancedLightnessSlider = NSSlider()
    private let advancedHueValueLabel = NSTextField(labelWithString: "")
    private let advancedSaturationValueLabel = NSTextField(labelWithString: "")
    private let advancedLightnessValueLabel = NSTextField(labelWithString: "")
    private let advancedPreviewView = NSView()
    private let advancedResetButton = NSButton(title: "Reset", target: nil, action: nil)

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
            makeCheckboxRow(label: "Launch at login", checkbox: launchAtLoginButton),
            makeNumberRow(label: "Polling", valueLabel: pollingValueLabel, stepper: pollingStepper),
            makeNumberRow(label: "GPU every", valueLabel: gpuMultiplierValueLabel, stepper: gpuMultiplierStepper),
            makeNumberRow(label: "Yellow above", valueLabel: yellowThresholdValueLabel, stepper: yellowThresholdStepper),
            makeNumberRow(label: "Red above", valueLabel: thresholdValueLabel, stepper: thresholdStepper),
            makeMetricList()
        ]))
        tabView.addTabViewItem(makeTabViewItem(label: "Colors", arrangedSubviews: [
            makeColorRow(label: "Yellow", colorMenu: yellowColorMenu),
            makeColorRow(label: "Over threshold", colorMenu: warningColorMenu),
            makeColorRow(label: "Upload", colorMenu: uploadColorMenu),
            makeColorRow(label: "Download", colorMenu: downloadColorMenu),
            makeColorRow(label: "Base text", colorMenu: baseTextColorMenu),
            makeColorRow(label: "Label text", colorMenu: labelTextColorMenu),
            makeCheckboxRow(label: "Auto contrast", checkbox: autoTextContrastButton)
        ]))
        tabView.addTabViewItem(makeTabViewItem(label: "Advanced", arrangedSubviews: [
            makeAdvancedRoleRow(),
            makeAdvancedSliderRow(label: "Hue", valueLabel: advancedHueValueLabel, slider: advancedHueSlider),
            makeAdvancedSliderRow(label: "Saturation", valueLabel: advancedSaturationValueLabel, slider: advancedSaturationSlider),
            makeAdvancedSliderRow(label: "Lightness", valueLabel: advancedLightnessValueLabel, slider: advancedLightnessSlider),
            makeAdvancedPreviewRow()
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
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(updateLaunchAtLogin)
        pollingStepper.target = self
        pollingStepper.action = #selector(updatePollingInterval)
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
        autoTextContrastButton.target = self
        autoTextContrastButton.action = #selector(updateAutoTextContrast)
        configureAdvancedControls()
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

    private func makeMetricList() -> NSScrollView {
        let tableView = NSTableView()
        let checkboxColumn = NSTableColumn(identifier: metricCheckboxColumnID)
        let metricColumn = NSTableColumn(identifier: metricNameColumnID)
        checkboxColumn.width = 34
        metricColumn.width = settingsWindowWidth - settingsPadding * 2 - settingsSectionPadding * 2 - checkboxColumn.width
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.addTableColumn(checkboxColumn)
        tableView.addTableColumn(metricColumn)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.registerForDraggedTypes([metricPasteboardType])

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.widthAnchor.constraint(equalToConstant: settingsWindowWidth - settingsPadding * 2 - settingsSectionPadding * 2).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: metricListHeight).isActive = true

        return scrollView
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

    private func makeAdvancedRoleRow() -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: "Edit color")
        advancedColorRoleMenu.controlSize = .small
        advancedColorRoleMenu.widthAnchor.constraint(equalToConstant: colorPresetMenuWidth).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(advancedColorRoleMenu)

        return row
    }

    private func makeAdvancedSliderRow(label: String, valueLabel: NSTextField, slider: NSSlider) -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: label)
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: settingsValueWidth).isActive = true
        slider.controlSize = .small
        slider.widthAnchor.constraint(equalToConstant: advancedSliderWidth).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(valueLabel)
        row.addArrangedSubview(slider)

        return row
    }

    private func makeAdvancedPreviewRow() -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: "Preview")
        advancedPreviewView.wantsLayer = true
        advancedPreviewView.widthAnchor.constraint(equalToConstant: advancedPreviewSize).isActive = true
        advancedPreviewView.heightAnchor.constraint(equalToConstant: advancedPreviewSize).isActive = true
        advancedPreviewView.layer?.cornerRadius = 6
        advancedPreviewView.layer?.borderWidth = 1
        advancedPreviewView.layer?.borderColor = NSColor.separatorColor.cgColor
        advancedResetButton.controlSize = .small

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(advancedPreviewView)
        row.addArrangedSubview(advancedResetButton)

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

    private func configureAdvancedControls() {
        advancedColorRoleMenu.removeAllItems()
        advancedColorRoleMenu.target = self
        advancedColorRoleMenu.action = #selector(updateAdvancedColorRole)

        for colorRole in colorRoles {
            advancedColorRoleMenu.addItem(withTitle: colorRole.title)
            advancedColorRoleMenu.item(withTitle: colorRole.title)?.representedObject = colorRole.id
        }

        configureAdvancedSlider(advancedHueSlider, action: #selector(updateAdvancedColorAdjustment))
        configureAdvancedSlider(advancedSaturationSlider, action: #selector(updateAdvancedColorAdjustment))
        configureAdvancedSlider(advancedLightnessSlider, action: #selector(updateAdvancedColorAdjustment))
        advancedResetButton.target = self
        advancedResetButton.action = #selector(resetAdvancedColorAdjustment)
    }

    private func configureAdvancedSlider(_ slider: NSSlider, action: Selector) {
        slider.minValue = Double(minimumColorAdjustmentPercent)
        slider.maxValue = Double(maximumColorAdjustmentPercent)
        slider.numberOfTickMarks = 5
        slider.allowsTickMarkValuesOnly = false
        slider.target = self
        slider.action = action
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
        launchAtLoginButton.state = configuration.isLaunchAtLoginEnabled ? .on : .off

        pollingStepper.minValue = minimumPollingIntervalInSeconds
        pollingStepper.maxValue = maximumPollingIntervalInSeconds
        pollingStepper.increment = 1
        pollingStepper.doubleValue = configuration.pollingIntervalInSeconds
        pollingValueLabel.stringValue = "\(Int(configuration.pollingIntervalInSeconds))s"

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
        autoTextContrastButton.state = configuration.isAutoTextContrastEnabled ? .on : .off
        syncAdvancedControls()
    }

    private func syncAdvancedControls() {
        let colorRole = selectedColorRole()
        let colorAdjustment = getColorAdjustment(colorAdjustments: configuration.colorAdjustments, roleID: colorRole.id)
        advancedHueSlider.integerValue = colorAdjustment.huePercent
        advancedSaturationSlider.integerValue = colorAdjustment.saturationPercent
        advancedLightnessSlider.integerValue = colorAdjustment.lightnessPercent
        advancedHueValueLabel.stringValue = formatSignedPercent(colorAdjustment.huePercent)
        advancedSaturationValueLabel.stringValue = formatSignedPercent(colorAdjustment.saturationPercent)
        advancedLightnessValueLabel.stringValue = formatSignedPercent(colorAdjustment.lightnessPercent)
        advancedPreviewView.layer?.backgroundColor = getAdjustedColor(colorRole: colorRole).cgColor
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

    private func selectedColorRole() -> ColorRole {
        guard let maybeRoleID = advancedColorRoleMenu.selectedItem?.representedObject as? String else {
            return colorRoles.first ?? ColorRole(id: yellowColorKey, title: "Yellow", usesTextPresets: false)
        }

        return colorRoles.first { colorRole in
            colorRole.id == maybeRoleID
        } ?? ColorRole(id: yellowColorKey, title: "Yellow", usesTextPresets: false)
    }

    private func getAdjustedColor(colorRole: ColorRole) -> NSColor {
        let colorID = getColorID(colorRole: colorRole)
        let colorPreset = colorRole.usesTextPresets ? getTextColorPreset(id: colorID) : getColorPreset(id: colorID)
        let colorAdjustment = getColorAdjustment(colorAdjustments: configuration.colorAdjustments, roleID: colorRole.id)

        return applyColorAdjustment(color: colorPreset?.color ?? .white, colorAdjustment: colorAdjustment)
    }

    private func getColorID(colorRole: ColorRole) -> String {
        if colorRole.id == yellowColorKey {
            return configuration.yellowColorID
        }

        if colorRole.id == warningColorKey {
            return configuration.warningColorID
        }

        if colorRole.id == uploadColorKey {
            return configuration.uploadColorID
        }

        if colorRole.id == downloadColorKey {
            return configuration.downloadColorID
        }

        if colorRole.id == baseTextColorKey {
            return configuration.baseTextColorID
        }

        return configuration.labelTextColorID
    }

    private func formatSignedPercent(_ value: Int) -> String {
        if value > 0 {
            return "+\(value)"
        }

        return "\(value)"
    }

    private func getMetricTag(metricID: String) -> Int {
        availableMetrics.firstIndex { metricConfiguration in
            metricConfiguration.id == metricID
        } ?? -1
    }

    private func getMetricID(tag: Int) -> String? {
        availableMetrics.enumerated().first { metricOffset, _ in
            metricOffset == tag
        }?.element.id
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        configuration.orderedMetricIDs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let maybeMetricID = getOrderedMetricID(row: row), let metricConfiguration = getMetricConfiguration(id: maybeMetricID) else {
            return nil
        }

        if tableColumn?.identifier == metricCheckboxColumnID {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(updateMetricEnabled))
            checkbox.controlSize = .small
            checkbox.state = configuration.enabledMetricIDs.contains(metricConfiguration.id) ? .on : .off
            checkbox.tag = getMetricTag(metricID: metricConfiguration.id)

            return checkbox
        }

        let label = NSTextField(labelWithString: metricConfiguration.title)
        label.textColor = NSColor.labelColor

        return label
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let maybeMetricID = getOrderedMetricID(row: row) else {
            return nil
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(maybeMetricID, forType: metricPasteboardType)

        return pasteboardItem
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        tableView.setDropRow(row, dropOperation: .above)

        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let maybeMetricID = info.draggingPasteboard.string(forType: metricPasteboardType), let originalMetricIndex = configuration.orderedMetricIDs.firstIndex(of: maybeMetricID) else {
            return false
        }

        var orderedMetricIDs = configuration.orderedMetricIDs
        orderedMetricIDs.remove(at: originalMetricIndex)
        let insertMetricIndex = originalMetricIndex < row ? max(0, row - 1) : row
        orderedMetricIDs.insert(maybeMetricID, at: min(insertMetricIndex, orderedMetricIDs.count))
        configuration = makeConfiguration(orderedMetricIDs: orderedMetricIDs)
        tableView.reloadData()
        onChange(configuration)

        return true
    }

    private func getOrderedMetricID(row: Int) -> String? {
        configuration.orderedMetricIDs.enumerated().first { metricOffset, _ in
            metricOffset == row
        }?.element
    }

    private func makeConfiguration(
        pollingIntervalInSeconds: TimeInterval? = nil,
        isLaunchAtLoginEnabled: Bool? = nil,
        enabledMetricIDs: Set<String>? = nil,
        orderedMetricIDs: [String]? = nil,
        gpuPollingMultiplier: Int? = nil,
        yellowThresholdPercent: Int? = nil,
        yellowColorID: String? = nil,
        warningThresholdPercent: Int? = nil,
        warningColorID: String? = nil,
        uploadColorID: String? = nil,
        downloadColorID: String? = nil,
        baseTextColorID: String? = nil,
        labelTextColorID: String? = nil,
        isAutoTextContrastEnabled: Bool? = nil,
        colorAdjustments: [String: ColorAdjustment]? = nil
    ) -> AppConfiguration {
        AppConfiguration(
            pollingIntervalInSeconds: pollingIntervalInSeconds ?? configuration.pollingIntervalInSeconds,
            isLaunchAtLoginEnabled: isLaunchAtLoginEnabled ?? configuration.isLaunchAtLoginEnabled,
            enabledMetricIDs: enabledMetricIDs ?? configuration.enabledMetricIDs,
            orderedMetricIDs: orderedMetricIDs ?? configuration.orderedMetricIDs,
            gpuPollingMultiplier: gpuPollingMultiplier ?? configuration.gpuPollingMultiplier,
            yellowThresholdPercent: yellowThresholdPercent ?? configuration.yellowThresholdPercent,
            yellowColorID: yellowColorID ?? configuration.yellowColorID,
            warningThresholdPercent: warningThresholdPercent ?? configuration.warningThresholdPercent,
            warningColorID: warningColorID ?? configuration.warningColorID,
            uploadColorID: uploadColorID ?? configuration.uploadColorID,
            downloadColorID: downloadColorID ?? configuration.downloadColorID,
            baseTextColorID: baseTextColorID ?? configuration.baseTextColorID,
            labelTextColorID: labelTextColorID ?? configuration.labelTextColorID,
            isAutoTextContrastEnabled: isAutoTextContrastEnabled ?? configuration.isAutoTextContrastEnabled,
            colorAdjustments: colorAdjustments ?? configuration.colorAdjustments
        )
    }

    @objc private func updatePollingInterval() {
        configuration = makeConfiguration(pollingIntervalInSeconds: pollingStepper.doubleValue)
        syncControls()
        onChange(configuration)
    }

    @objc private func updateLaunchAtLogin() {
        configuration = makeConfiguration(isLaunchAtLoginEnabled: launchAtLoginButton.state == .on)
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
        syncControls()
        onChange(configuration)
    }

    @objc private func updateWarningColor() {
        configuration = makeConfiguration(warningColorID: selectedColorID(in: warningColorMenu, fallback: configuration.warningColorID))
        syncControls()
        onChange(configuration)
    }

    @objc private func updateUploadColor() {
        configuration = makeConfiguration(uploadColorID: selectedColorID(in: uploadColorMenu, fallback: configuration.uploadColorID))
        syncControls()
        onChange(configuration)
    }

    @objc private func updateDownloadColor() {
        configuration = makeConfiguration(downloadColorID: selectedColorID(in: downloadColorMenu, fallback: configuration.downloadColorID))
        syncControls()
        onChange(configuration)
    }

    @objc private func updateBaseTextColor() {
        configuration = makeConfiguration(baseTextColorID: selectedTextColorID(in: baseTextColorMenu, fallback: configuration.baseTextColorID))
        syncControls()
        onChange(configuration)
    }

    @objc private func updateLabelTextColor() {
        configuration = makeConfiguration(labelTextColorID: selectedTextColorID(in: labelTextColorMenu, fallback: configuration.labelTextColorID))
        syncControls()
        onChange(configuration)
    }

    @objc private func updateAutoTextContrast() {
        configuration = makeConfiguration(isAutoTextContrastEnabled: autoTextContrastButton.state == .on)
        syncControls()
        onChange(configuration)
    }

    @objc private func updateAdvancedColorRole() {
        syncAdvancedControls()
    }

    @objc private func updateAdvancedColorAdjustment() {
        let colorRole = selectedColorRole()
        var colorAdjustments = configuration.colorAdjustments
        colorAdjustments[colorRole.id] = ColorAdjustment(
            huePercent: advancedHueSlider.integerValue,
            saturationPercent: advancedSaturationSlider.integerValue,
            lightnessPercent: advancedLightnessSlider.integerValue
        )
        configuration = makeConfiguration(colorAdjustments: colorAdjustments)
        syncAdvancedControls()
        onChange(configuration)
    }

    @objc private func resetAdvancedColorAdjustment() {
        var colorAdjustments = configuration.colorAdjustments
        colorAdjustments[selectedColorRole().id] = ColorAdjustment(huePercent: 0, saturationPercent: 0, lightnessPercent: 0)
        configuration = makeConfiguration(colorAdjustments: colorAdjustments)
        syncAdvancedControls()
        onChange(configuration)
    }

    @objc private func updateMetricEnabled(_ sender: NSButton) {
        guard let maybeMetricID = getMetricID(tag: sender.tag) else {
            return
        }

        var enabledMetricIDs = configuration.enabledMetricIDs

        if sender.state == .on {
            enabledMetricIDs.insert(maybeMetricID)
        } else {
            enabledMetricIDs.remove(maybeMetricID)
        }

        configuration = makeConfiguration(enabledMetricIDs: enabledMetricIDs)
        rebuildSettingsView()
        onChange(configuration)
    }

    private func rebuildSettingsView() {
        for subview in subviews {
            subview.removeFromSuperview()
        }
        buildView()
        syncControls()
    }

}
