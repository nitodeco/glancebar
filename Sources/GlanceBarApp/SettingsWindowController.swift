import AppKit

private let settingsWindowWidth: CGFloat = 430
private let settingsWindowHeight: CGFloat = 470
private let settingsPadding: CGFloat = 16
private let settingsRowSpacing: CGFloat = 10
private let settingsLabelWidth: CGFloat = 145
private let settingsValueWidth: CGFloat = 52
private let colorPresetMenuWidth: CGFloat = 155
private let metricListHeight: CGFloat = 140
private let metricCheckboxColumnID = NSUserInterfaceItemIdentifier("enabled")
private let metricNameColumnID = NSUserInterfaceItemIdentifier("metric")
private let metricPasteboardType = NSPasteboard.PasteboardType("dev.nitodeco.glancebar.metric")
private let colorSwatchGlyph = "■"

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void
    private let settingsView: SettingsView

    init(
        configuration: AppConfiguration,
        isAutoUpdateEnabled: Bool = true,
        onChange: @escaping (AppConfiguration) -> Void,
        onAutoUpdateChange: @escaping (Bool) -> Void = { _ in },
        onUninstall: @escaping () -> Void = {},
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        settingsView = SettingsView(
            configuration: configuration,
            isAutoUpdateEnabled: isAutoUpdateEnabled,
            onChange: onChange,
            onAutoUpdateChange: onAutoUpdateChange,
            onUninstall: onUninstall
        )
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

    func update(configuration: AppConfiguration, isAutoUpdateEnabled: Bool? = nil) {
        settingsView.update(
            configuration: configuration,
            isAutoUpdateEnabled: isAutoUpdateEnabled ?? settingsView.isAutoUpdateEnabled
        )
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

@MainActor
private final class SettingsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private(set) var isAutoUpdateEnabled: Bool
    private var configuration: AppConfiguration
    private let onChange: (AppConfiguration) -> Void
    private let onAutoUpdateChange: (Bool) -> Void
    private let onUninstall: () -> Void
    private let autoUpdateButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let lowPowerModeButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let autoTextContrastButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let warningThresholdValueLabel = NSTextField(labelWithString: "")
    private let criticalThresholdValueLabel = NSTextField(labelWithString: "")
    private let warningThresholdStepper = NSStepper()
    private let criticalThresholdStepper = NSStepper()
    private let metricTableView = NSTableView()
    private var pollingValueLabelByMetricID: [String: NSTextField] = [:]
    private var pollingStepperByMetricID: [String: NSStepper] = [:]
    private var colorMenuByRoleID: [String: NSPopUpButton] = [:]
    private var colorEditorWindowController: ColorEditorWindowController?

    init(
        configuration: AppConfiguration,
        isAutoUpdateEnabled: Bool,
        onChange: @escaping (AppConfiguration) -> Void,
        onAutoUpdateChange: @escaping (Bool) -> Void,
        onUninstall: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.isAutoUpdateEnabled = isAutoUpdateEnabled
        self.onChange = onChange
        self.onAutoUpdateChange = onAutoUpdateChange
        self.onUninstall = onUninstall
        super.init(frame: NSRect(x: 0, y: 0, width: settingsWindowWidth, height: settingsWindowHeight))
        buildView()
        syncControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(configuration: AppConfiguration, isAutoUpdateEnabled: Bool) {
        self.configuration = configuration
        self.isAutoUpdateEnabled = isAutoUpdateEnabled
        syncControls()
        metricTableView.reloadData()
        colorEditorWindowController?.update(configuration: configuration)
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

        tabView.addTabViewItem(makeGeneralTab())
        tabView.addTabViewItem(makeMetricsTab())
        tabView.addTabViewItem(makeColorsTab())
        configureActions()
    }

    private func makeGeneralTab() -> NSTabViewItem {
        let contentView = NSView()
        let topStack = NSStackView(views: [
            makeCheckboxRow(label: "Auto-update", checkbox: autoUpdateButton),
            makeCheckboxRow(label: "Launch at login", checkbox: launchAtLoginButton),
            makeMetricList(),
            makeNumberRow(
                label: "Warning above",
                valueLabel: warningThresholdValueLabel,
                stepper: warningThresholdStepper
            ),
            makeNumberRow(
                label: "Critical above",
                valueLabel: criticalThresholdValueLabel,
                stepper: criticalThresholdStepper
            )
        ])
        topStack.orientation = .vertical
        topStack.alignment = .leading
        topStack.spacing = settingsRowSpacing
        topStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(topStack)

        let uninstallButton = NSButton(title: "Uninstall", target: self, action: #selector(uninstall))
        uninstallButton.bezelStyle = .rounded
        uninstallButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(uninstallButton)

        NSLayoutConstraint.activate([
            topStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: settingsPadding),
            topStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -settingsPadding),
            topStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: settingsPadding),
            uninstallButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -settingsPadding),
            uninstallButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -settingsPadding)
        ])

        let tabViewItem = NSTabViewItem(identifier: "general")
        tabViewItem.label = "General"
        tabViewItem.view = contentView

        return tabViewItem
    }

    private func makeMetricsTab() -> NSTabViewItem {
        let pollingRows = availableMetrics.map { metricConfiguration in
            let valueLabel = NSTextField(labelWithString: "")
            let stepper = NSStepper()
            pollingValueLabelByMetricID[metricConfiguration.id] = valueLabel
            pollingStepperByMetricID[metricConfiguration.id] = stepper
            stepper.identifier = NSUserInterfaceItemIdentifier(metricConfiguration.id)

            return makeNumberRow(label: metricConfiguration.title, valueLabel: valueLabel, stepper: stepper)
        }
        let arrangedSubviews = pollingRows + [
            makeCheckboxRow(label: "Low Power Mode ×5", checkbox: lowPowerModeButton)
        ]

        return makeTabViewItem(label: "Metrics", arrangedSubviews: arrangedSubviews)
    }

    private func makeColorsTab() -> NSTabViewItem {
        let colorRows = colorRoles.map { colorRole in
            let colorMenu = NSPopUpButton()
            colorMenu.identifier = NSUserInterfaceItemIdentifier(colorRole.id)
            colorMenuByRoleID[colorRole.id] = colorMenu

            return makeColorRow(colorRole: colorRole, colorMenu: colorMenu)
        }

        return makeTabViewItem(
            label: "Colors",
            arrangedSubviews: colorRows + [
                makeCheckboxRow(label: "Auto contrast", checkbox: autoTextContrastButton)
            ]
        )
    }

    private func makeTabViewItem(label: String, arrangedSubviews: [NSView]) -> NSTabViewItem {
        let contentView = NSView()
        let stackView = NSStackView(views: arrangedSubviews)
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = settingsRowSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: settingsPadding),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -settingsPadding),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: settingsPadding)
        ])

        let tabViewItem = NSTabViewItem(identifier: label.lowercased())
        tabViewItem.label = label
        tabViewItem.view = contentView

        return tabViewItem
    }

    private func makeCheckboxRow(label: String, checkbox: NSButton) -> NSView {
        let labelField = makeSettingsLabel(label)
        checkbox.controlSize = .small
        let row = NSStackView(views: [labelField, checkbox])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        return row
    }

    private func makeNumberRow(label: String, valueLabel: NSTextField, stepper: NSStepper) -> NSView {
        let labelField = makeSettingsLabel(label)
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: settingsValueWidth).isActive = true
        stepper.controlSize = .small
        let row = NSStackView(views: [labelField, valueLabel, stepper])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        return row
    }

    private func makeColorRow(colorRole: ColorRole, colorMenu: NSPopUpButton) -> NSView {
        let labelField = makeSettingsLabel(colorRole.title)
        colorMenu.controlSize = .small
        colorMenu.widthAnchor.constraint(equalToConstant: colorPresetMenuWidth).isActive = true
        let editButton = NSButton(title: "Edit", target: self, action: #selector(editColor(_:)))
        editButton.controlSize = .small
        editButton.identifier = NSUserInterfaceItemIdentifier(colorRole.id)
        let row = NSStackView(views: [labelField, colorMenu, editButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        return row
    }

    private func makeSettingsLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: settingsLabelWidth).isActive = true

        return label
    }

    private func makeMetricList() -> NSView {
        let checkboxColumn = NSTableColumn(identifier: metricCheckboxColumnID)
        checkboxColumn.width = 32
        checkboxColumn.minWidth = 32
        checkboxColumn.maxWidth = 32
        checkboxColumn.resizingMask = []
        let nameColumn = NSTableColumn(identifier: metricNameColumnID)
        nameColumn.width = 255
        metricTableView.addTableColumn(checkboxColumn)
        metricTableView.addTableColumn(nameColumn)
        metricTableView.headerView = nil
        metricTableView.rowHeight = 24
        metricTableView.backgroundColor = .clear
        metricTableView.dataSource = self
        metricTableView.delegate = self
        metricTableView.registerForDraggedTypes([metricPasteboardType])
        metricTableView.setDraggingSourceOperationMask(.move, forLocal: true)

        let scrollView = NSScrollView()
        scrollView.documentView = metricTableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .bezelBorder
        scrollView.widthAnchor.constraint(equalToConstant: 305).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: metricListHeight).isActive = true

        return scrollView
    }

    private func configureActions() {
        autoUpdateButton.target = self
        autoUpdateButton.action = #selector(updateAutoUpdate)
        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(updateLaunchAtLogin)
        lowPowerModeButton.target = self
        lowPowerModeButton.action = #selector(updateLowPowerModeAdjustment)
        autoTextContrastButton.target = self
        autoTextContrastButton.action = #selector(updateAutoTextContrast)
        warningThresholdStepper.target = self
        warningThresholdStepper.action = #selector(updateWarningThreshold)
        criticalThresholdStepper.target = self
        criticalThresholdStepper.action = #selector(updateCriticalThreshold)

        for stepper in pollingStepperByMetricID.values {
            stepper.target = self
            stepper.action = #selector(updatePollingInterval(_:))
        }

        for colorMenu in colorMenuByRoleID.values {
            colorMenu.target = self
            colorMenu.action = #selector(updateColorPreset(_:))
        }
    }

    private func syncControls() {
        autoUpdateButton.state = isAutoUpdateEnabled ? .on : .off
        launchAtLoginButton.state = configuration.isLaunchAtLoginEnabled ? .on : .off
        lowPowerModeButton.state = configuration.isLowPowerModePollingAdjustmentEnabled ? .on : .off
        autoTextContrastButton.state = configuration.isAutoTextContrastEnabled ? .on : .off

        for metricConfiguration in availableMetrics {
            guard let valueLabel = pollingValueLabelByMetricID[metricConfiguration.id],
                  let stepper = pollingStepperByMetricID[metricConfiguration.id]
            else {
                continue
            }

            let pollingIntervalInSeconds = configuration.pollingIntervalInSeconds(metricID: metricConfiguration.id)
            stepper.minValue = minimumPollingIntervalInSeconds
            stepper.maxValue = maximumPollingIntervalInSeconds
            stepper.increment = 1
            stepper.doubleValue = pollingIntervalInSeconds
            valueLabel.stringValue = "\(Int(pollingIntervalInSeconds))s"
        }

        warningThresholdStepper.minValue = Double(minimumThresholdPercent)
        warningThresholdStepper.maxValue = Double(max(minimumThresholdPercent, configuration.criticalThresholdPercent - 1))
        warningThresholdStepper.increment = 1
        warningThresholdStepper.integerValue = configuration.warningThresholdPercent
        warningThresholdValueLabel.stringValue = "\(configuration.warningThresholdPercent)%"

        criticalThresholdStepper.minValue = Double(minimumThresholdPercent)
        criticalThresholdStepper.maxValue = Double(maximumThresholdPercent)
        criticalThresholdStepper.increment = 1
        criticalThresholdStepper.integerValue = configuration.criticalThresholdPercent
        criticalThresholdValueLabel.stringValue = "\(configuration.criticalThresholdPercent)%"

        for colorRole in colorRoles {
            guard let colorMenu = colorMenuByRoleID[colorRole.id] else {
                continue
            }

            populate(colorMenu: colorMenu, colorRole: colorRole)
        }
    }

    private func populate(colorMenu: NSPopUpButton, colorRole: ColorRole) {
        let presets = colorRole.usesTextPresets ? textColorPresets : colorPresets
        let selectedColorID = getSelectedColorID(colorRoleID: colorRole.id)
        colorMenu.removeAllItems()

        for colorPreset in presets {
            colorMenu.addItem(withTitle: colorPreset.title)
            colorMenu.lastItem?.representedObject = colorPreset.id
            colorMenu.lastItem?.attributedTitle = makeColorPresetTitle(colorPreset: colorPreset)
        }

        if let selectedItem = colorMenu.itemArray.first(where: { menuItem in
            menuItem.representedObject as? String == selectedColorID
        }) {
            colorMenu.select(selectedItem)
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
        title.append(NSAttributedString(string: colorPreset.title, attributes: [.foregroundColor: NSColor.labelColor]))

        return title
    }

    private func getSelectedColorID(colorRoleID: String) -> String {
        if colorRoleID == warningColorKey {
            return configuration.warningColorID
        }

        if colorRoleID == criticalColorKey {
            return configuration.criticalColorID
        }

        if colorRoleID == uploadColorKey {
            return configuration.uploadColorID
        }

        if colorRoleID == downloadColorKey {
            return configuration.downloadColorID
        }

        if colorRoleID == baseTextColorKey {
            return configuration.baseTextColorID
        }

        return configuration.labelTextColorID
    }

    private func makeConfiguration(
        isLaunchAtLoginEnabled: Bool? = nil,
        enabledMetricIDs: Set<String>? = nil,
        orderedMetricIDs: [String]? = nil,
        pollingIntervalsByMetricID: [String: TimeInterval]? = nil,
        isLowPowerModePollingAdjustmentEnabled: Bool? = nil,
        warningThresholdPercent: Int? = nil,
        warningColorID: String? = nil,
        criticalThresholdPercent: Int? = nil,
        criticalColorID: String? = nil,
        uploadColorID: String? = nil,
        downloadColorID: String? = nil,
        baseTextColorID: String? = nil,
        labelTextColorID: String? = nil,
        isAutoTextContrastEnabled: Bool? = nil,
        colorAdjustments: [String: ColorAdjustment]? = nil
    ) -> AppConfiguration {
        AppConfiguration(
            isLaunchAtLoginEnabled: isLaunchAtLoginEnabled ?? configuration.isLaunchAtLoginEnabled,
            enabledMetricIDs: enabledMetricIDs ?? configuration.enabledMetricIDs,
            orderedMetricIDs: orderedMetricIDs ?? configuration.orderedMetricIDs,
            pollingIntervalsByMetricID: pollingIntervalsByMetricID ?? configuration.pollingIntervalsByMetricID,
            isLowPowerModePollingAdjustmentEnabled: isLowPowerModePollingAdjustmentEnabled
                ?? configuration.isLowPowerModePollingAdjustmentEnabled,
            warningThresholdPercent: warningThresholdPercent ?? configuration.warningThresholdPercent,
            warningColorID: warningColorID ?? configuration.warningColorID,
            criticalThresholdPercent: criticalThresholdPercent ?? configuration.criticalThresholdPercent,
            criticalColorID: criticalColorID ?? configuration.criticalColorID,
            uploadColorID: uploadColorID ?? configuration.uploadColorID,
            downloadColorID: downloadColorID ?? configuration.downloadColorID,
            baseTextColorID: baseTextColorID ?? configuration.baseTextColorID,
            labelTextColorID: labelTextColorID ?? configuration.labelTextColorID,
            isAutoTextContrastEnabled: isAutoTextContrastEnabled ?? configuration.isAutoTextContrastEnabled,
            colorAdjustments: colorAdjustments ?? configuration.colorAdjustments
        )
    }

    private func publish(configuration: AppConfiguration) {
        self.configuration = configuration
        syncControls()
        metricTableView.reloadData()
        colorEditorWindowController?.update(configuration: configuration)
        onChange(configuration)
    }

    @objc private func updateAutoUpdate() {
        isAutoUpdateEnabled = autoUpdateButton.state == .on
        onAutoUpdateChange(isAutoUpdateEnabled)
    }

    @objc private func updateLaunchAtLogin() {
        publish(configuration: makeConfiguration(isLaunchAtLoginEnabled: launchAtLoginButton.state == .on))
    }

    @objc private func updateLowPowerModeAdjustment() {
        publish(configuration: makeConfiguration(
            isLowPowerModePollingAdjustmentEnabled: lowPowerModeButton.state == .on
        ))
    }

    @objc private func updateAutoTextContrast() {
        publish(configuration: makeConfiguration(isAutoTextContrastEnabled: autoTextContrastButton.state == .on))
    }

    @objc private func updatePollingInterval(_ sender: NSStepper) {
        guard let metricID = sender.identifier?.rawValue else {
            return
        }

        var pollingIntervalsByMetricID = configuration.pollingIntervalsByMetricID
        pollingIntervalsByMetricID[metricID] = sender.doubleValue
        publish(configuration: makeConfiguration(pollingIntervalsByMetricID: pollingIntervalsByMetricID))
    }

    @objc private func updateWarningThreshold() {
        publish(configuration: makeConfiguration(warningThresholdPercent: warningThresholdStepper.integerValue))
    }

    @objc private func updateCriticalThreshold() {
        publish(configuration: makeConfiguration(criticalThresholdPercent: criticalThresholdStepper.integerValue))
    }

    @objc private func updateColorPreset(_ sender: NSPopUpButton) {
        guard let colorRoleID = sender.identifier?.rawValue,
              let colorID = sender.selectedItem?.representedObject as? String
        else {
            return
        }

        if colorRoleID == warningColorKey {
            publish(configuration: makeConfiguration(warningColorID: colorID))
        } else if colorRoleID == criticalColorKey {
            publish(configuration: makeConfiguration(criticalColorID: colorID))
        } else if colorRoleID == uploadColorKey {
            publish(configuration: makeConfiguration(uploadColorID: colorID))
        } else if colorRoleID == downloadColorKey {
            publish(configuration: makeConfiguration(downloadColorID: colorID))
        } else if colorRoleID == baseTextColorKey {
            publish(configuration: makeConfiguration(baseTextColorID: colorID))
        } else if colorRoleID == labelTextColorKey {
            publish(configuration: makeConfiguration(labelTextColorID: colorID))
        }
    }

    @objc private func editColor(_ sender: NSButton) {
        guard let colorRoleID = sender.identifier?.rawValue,
              let colorRole = colorRoles.first(where: { colorRole in colorRole.id == colorRoleID })
        else {
            return
        }

        let colorEditorWindowController = colorEditorWindowController ?? ColorEditorWindowController(
            configuration: configuration,
            colorRole: colorRole,
            onAdjustmentChange: { [weak self] colorRoleID, colorAdjustment in
                guard let self else {
                    return
                }

                var colorAdjustments = configuration.colorAdjustments
                colorAdjustments[colorRoleID] = colorAdjustment
                publish(configuration: makeConfiguration(colorAdjustments: colorAdjustments))
            }
        )
        self.colorEditorWindowController = colorEditorWindowController
        colorEditorWindowController.edit(colorRole: colorRole, configuration: configuration)
    }

    @objc private func uninstall() {
        onUninstall()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        configuration.orderedMetricIDs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let metricID = configuration.orderedMetricIDs.enumerated().first(where: { offset, _ in
            offset == row
        })?.element,
              let metricConfiguration = getMetricConfiguration(id: metricID)
        else {
            return nil
        }

        if tableColumn?.identifier == metricCheckboxColumnID {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(updateMetricEnabled(_:)))
            checkbox.controlSize = .small
            checkbox.state = configuration.enabledMetricIDs.contains(metricID) ? .on : .off
            checkbox.identifier = NSUserInterfaceItemIdentifier(metricID)

            return checkbox
        }

        return NSTextField(labelWithString: metricConfiguration.title)
    }

    @objc private func updateMetricEnabled(_ sender: NSButton) {
        guard let metricID = sender.identifier?.rawValue else {
            return
        }

        publish(configuration: makeConfiguration(
            enabledMetricIDs: getEnabledMetricIDsAfterToggle(
                metricID: metricID,
                enabledMetricIDs: configuration.enabledMetricIDs
            )
        ))
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard let metricID = configuration.orderedMetricIDs.enumerated().first(where: { offset, _ in
            offset == row
        })?.element else {
            return nil
        }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(metricID, forType: metricPasteboardType)

        return pasteboardItem
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        tableView.setDropRow(row, dropOperation: .above)

        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let metricID = info.draggingPasteboard.string(forType: metricPasteboardType),
              let originalMetricIndex = configuration.orderedMetricIDs.firstIndex(of: metricID)
        else {
            return false
        }

        var orderedMetricIDs = configuration.orderedMetricIDs
        orderedMetricIDs.remove(at: originalMetricIndex)
        let insertMetricIndex = originalMetricIndex < row ? max(0, row - 1) : row
        orderedMetricIDs.insert(metricID, at: min(insertMetricIndex, orderedMetricIDs.count))
        publish(configuration: makeConfiguration(orderedMetricIDs: orderedMetricIDs))

        return true
    }
}

@MainActor
private final class ColorEditorWindowController: NSWindowController {
    private var configuration: AppConfiguration
    private var colorRole: ColorRole
    private let onAdjustmentChange: (String, ColorAdjustment) -> Void
    private let previewView = NSView()
    private let hueSlider = NSSlider()
    private let saturationSlider = NSSlider()
    private let lightnessSlider = NSSlider()
    private let hueValueLabel = NSTextField(labelWithString: "")
    private let saturationValueLabel = NSTextField(labelWithString: "")
    private let lightnessValueLabel = NSTextField(labelWithString: "")

    init(
        configuration: AppConfiguration,
        colorRole: ColorRole,
        onAdjustmentChange: @escaping (String, ColorAdjustment) -> Void
    ) {
        self.configuration = configuration
        self.colorRole = colorRole
        self.onAdjustmentChange = onAdjustmentChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView()
        window.center()
        configureSliders()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func edit(colorRole: ColorRole, configuration: AppConfiguration) {
        self.colorRole = colorRole
        self.configuration = configuration
        window?.title = "Edit \(colorRole.title) Color"
        syncControls()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func update(configuration: AppConfiguration) {
        self.configuration = configuration
        syncControls()
    }

    private func makeContentView() -> NSView {
        let contentView = NSView()
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 8
        previewView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        previewView.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let sliderRows = [
            makeSliderRow(label: "Hue", slider: hueSlider, valueLabel: hueValueLabel),
            makeSliderRow(label: "Saturation", slider: saturationSlider, valueLabel: saturationValueLabel),
            makeSliderRow(label: "Lightness", slider: lightnessSlider, valueLabel: lightnessValueLabel)
        ]
        let resetButton = NSButton(title: "Reset", target: self, action: #selector(reset))
        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [resetButton, doneButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let stackView = NSStackView(views: [previewView] + sliderRows + [buttonRow])
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18)
        ])

        return contentView
    }

    private func makeSliderRow(label: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.widthAnchor.constraint(equalToConstant: 75).isActive = true
        slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 35).isActive = true
        let row = NSStackView(views: [labelField, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        return row
    }

    private func configureSliders() {
        for slider in [hueSlider, saturationSlider, lightnessSlider] {
            slider.minValue = Double(minimumColorAdjustmentPercent)
            slider.maxValue = Double(maximumColorAdjustmentPercent)
            slider.isContinuous = true
            slider.target = self
            slider.action = #selector(updateAdjustment)
        }
    }

    private func syncControls() {
        let colorAdjustment = getColorAdjustment(
            colorAdjustments: configuration.colorAdjustments,
            roleID: colorRole.id
        )
        hueSlider.integerValue = colorAdjustment.huePercent
        saturationSlider.integerValue = colorAdjustment.saturationPercent
        lightnessSlider.integerValue = colorAdjustment.lightnessPercent
        hueValueLabel.stringValue = formatSignedPercent(colorAdjustment.huePercent)
        saturationValueLabel.stringValue = formatSignedPercent(colorAdjustment.saturationPercent)
        lightnessValueLabel.stringValue = formatSignedPercent(colorAdjustment.lightnessPercent)
        previewView.layer?.backgroundColor = getColor(configuration: configuration, colorRoleID: colorRole.id).cgColor
    }

    @objc private func updateAdjustment() {
        onAdjustmentChange(
            colorRole.id,
            ColorAdjustment(
                huePercent: hueSlider.integerValue,
                saturationPercent: saturationSlider.integerValue,
                lightnessPercent: lightnessSlider.integerValue
            )
        )
    }

    @objc private func reset() {
        onAdjustmentChange(colorRole.id, ColorAdjustment(huePercent: 0, saturationPercent: 0, lightnessPercent: 0))
    }

    @objc private func done() {
        close()
    }
}

private func getColor(configuration: AppConfiguration, colorRoleID: String) -> NSColor {
    if colorRoleID == warningColorKey {
        return configuration.warningColor
    }

    if colorRoleID == criticalColorKey {
        return configuration.criticalColor
    }

    if colorRoleID == uploadColorKey {
        return configuration.uploadColor
    }

    if colorRoleID == downloadColorKey {
        return configuration.downloadColor
    }

    if colorRoleID == baseTextColorKey {
        return configuration.baseTextColor
    }

    return configuration.labelTextColor
}

private func formatSignedPercent(_ value: Int) -> String {
    if value > 0 {
        return "+\(value)"
    }

    return "\(value)"
}
