import AppKit

private let settingsWindowWidth: CGFloat = 280
private let settingsWindowHeight: CGFloat = 496
private let settingsPadding: CGFloat = 16
private let settingsRowSpacing: CGFloat = 10
private let settingsValueWidth: CGFloat = 44
private let colorPresetMenuWidth: CGFloat = 116
private let backgroundWheelSize: CGFloat = 72
private let backgroundOpacitySliderWidth: CGFloat = 108
private let backgroundPreviewSize: CGFloat = 28
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
    private let gpuEnabledButton = NSButton(checkboxWithTitle: "Show GPU", target: nil, action: nil)
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
    private let backgroundEnabledButton = NSButton(checkboxWithTitle: "Background", target: nil, action: nil)
    private let backgroundColorWheel = SimplifiedColorWheelView(frame: NSRect(x: 0, y: 0, width: backgroundWheelSize, height: backgroundWheelSize))
    private let backgroundOpacitySlider = NSSlider()
    private let backgroundOpacityValueLabel = NSTextField(labelWithString: "")
    private let backgroundPreviewView = NSView()

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
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = settingsRowSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: settingsPadding),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -settingsPadding),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: settingsPadding),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -settingsPadding)
        ])

        stackView.addArrangedSubview(makeNumberRow(label: "Polling", valueLabel: pollingValueLabel, stepper: pollingStepper))
        stackView.addArrangedSubview(gpuEnabledButton)
        stackView.addArrangedSubview(makeNumberRow(label: "GPU every", valueLabel: gpuMultiplierValueLabel, stepper: gpuMultiplierStepper))
        stackView.addArrangedSubview(makeNumberRow(label: "Yellow above", valueLabel: yellowThresholdValueLabel, stepper: yellowThresholdStepper))
        stackView.addArrangedSubview(makeNumberRow(label: "Red above", valueLabel: thresholdValueLabel, stepper: thresholdStepper))
        stackView.addArrangedSubview(makeColorRow(label: "Yellow", colorMenu: yellowColorMenu))
        stackView.addArrangedSubview(makeColorRow(label: "Over threshold", colorMenu: warningColorMenu))
        stackView.addArrangedSubview(makeColorRow(label: "Upload", colorMenu: uploadColorMenu))
        stackView.addArrangedSubview(makeColorRow(label: "Download", colorMenu: downloadColorMenu))
        stackView.addArrangedSubview(makeColorRow(label: "Base text", colorMenu: baseTextColorMenu))
        stackView.addArrangedSubview(makeColorRow(label: "Label text", colorMenu: labelTextColorMenu))
        stackView.addArrangedSubview(backgroundEnabledButton)
        stackView.addArrangedSubview(makeBackgroundColorRow())
        stackView.addArrangedSubview(makeBackgroundOpacityRow())

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
        backgroundEnabledButton.target = self
        backgroundEnabledButton.action = #selector(updateBackgroundEnabled)
        backgroundColorWheel.onChange = { [weak self] hue, saturation in
            self?.updateBackgroundColor(hue: hue, saturation: saturation)
        }
        backgroundOpacitySlider.target = self
        backgroundOpacitySlider.action = #selector(updateBackgroundOpacity)
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

    private func makeColorRow(label: String, colorMenu: NSPopUpButton) -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: label)
        colorMenu.controlSize = .small
        colorMenu.widthAnchor.constraint(equalToConstant: colorPresetMenuWidth).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(colorMenu)

        return row
    }

    private func makeBackgroundColorRow() -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: "Background")
        backgroundColorWheel.widthAnchor.constraint(equalToConstant: backgroundWheelSize).isActive = true
        backgroundColorWheel.heightAnchor.constraint(equalToConstant: backgroundWheelSize).isActive = true
        backgroundPreviewView.wantsLayer = true
        backgroundPreviewView.widthAnchor.constraint(equalToConstant: backgroundPreviewSize).isActive = true
        backgroundPreviewView.heightAnchor.constraint(equalToConstant: backgroundPreviewSize).isActive = true
        backgroundPreviewView.layer?.cornerRadius = 6
        backgroundPreviewView.layer?.borderWidth = 1
        backgroundPreviewView.layer?.borderColor = NSColor.separatorColor.cgColor

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(backgroundColorWheel)
        row.addArrangedSubview(backgroundPreviewView)

        return row
    }

    private func makeBackgroundOpacityRow() -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: "Opacity")
        backgroundOpacityValueLabel.alignment = .right
        backgroundOpacityValueLabel.widthAnchor.constraint(equalToConstant: settingsValueWidth).isActive = true
        backgroundOpacitySlider.controlSize = .small
        backgroundOpacitySlider.widthAnchor.constraint(equalToConstant: backgroundOpacitySliderWidth).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(backgroundOpacityValueLabel)
        row.addArrangedSubview(backgroundOpacitySlider)

        return row
    }

    private func makeRowStackView() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: settingsWindowWidth - settingsPadding * 2).isActive = true

        return row
    }

    private func makeTitleLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

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

        backgroundEnabledButton.state = configuration.isBackgroundEnabled ? .on : .off
        backgroundColorWheel.hue = configuration.backgroundHue
        backgroundColorWheel.saturation = configuration.backgroundSaturation
        backgroundColorWheel.isEnabled = configuration.isBackgroundEnabled
        backgroundOpacitySlider.minValue = Double(minimumBackgroundOpacityPercent)
        backgroundOpacitySlider.maxValue = Double(maximumBackgroundOpacityPercent)
        backgroundOpacitySlider.doubleValue = Double(configuration.backgroundOpacityPercent)
        backgroundOpacitySlider.isEnabled = configuration.isBackgroundEnabled
        backgroundOpacityValueLabel.stringValue = "\(configuration.backgroundOpacityPercent)%"
        backgroundOpacityValueLabel.textColor = configuration.isBackgroundEnabled ? .labelColor : .disabledControlTextColor
        backgroundPreviewView.layer?.backgroundColor = configuration.backgroundColor.cgColor
        backgroundPreviewView.alphaValue = configuration.isBackgroundEnabled ? 1 : 0.35
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
        labelTextColorID: String? = nil,
        isBackgroundEnabled: Bool? = nil,
        backgroundHue: Double? = nil,
        backgroundSaturation: Double? = nil,
        backgroundOpacityPercent: Int? = nil
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
            labelTextColorID: labelTextColorID ?? configuration.labelTextColorID,
            isBackgroundEnabled: isBackgroundEnabled ?? configuration.isBackgroundEnabled,
            backgroundHue: backgroundHue ?? configuration.backgroundHue,
            backgroundSaturation: backgroundSaturation ?? configuration.backgroundSaturation,
            backgroundOpacityPercent: backgroundOpacityPercent ?? configuration.backgroundOpacityPercent
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

    @objc private func updateBackgroundEnabled() {
        configuration = makeConfiguration(isBackgroundEnabled: backgroundEnabledButton.state == .on)
        syncControls()
        onChange(configuration)
    }

    private func updateBackgroundColor(hue: Double, saturation: Double) {
        configuration = makeConfiguration(backgroundHue: hue, backgroundSaturation: saturation)
        syncControls()
        onChange(configuration)
    }

    @objc private func updateBackgroundOpacity() {
        configuration = makeConfiguration(backgroundOpacityPercent: backgroundOpacitySlider.integerValue)
        syncControls()
        onChange(configuration)
    }
}

@MainActor
private final class SimplifiedColorWheelView: NSView {
    var hue = 0.62 {
        didSet {
            needsDisplay = true
        }
    }

    var saturation = 0.18 {
        didSet {
            needsDisplay = true
        }
    }

    var isEnabled = true {
        didSet {
            needsDisplay = true
        }
    }

    var onChange: ((Double, Double) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let wheelRect = bounds.insetBy(dx: 2, dy: 2)
        let radius = min(wheelRect.width, wheelRect.height) / 2
        let centerPoint = NSPoint(x: wheelRect.midX, y: wheelRect.midY)
        let cellSize: CGFloat = 2

        for cellX in stride(from: wheelRect.minX, to: wheelRect.maxX, by: cellSize) {
            for cellY in stride(from: wheelRect.minY, to: wheelRect.maxY, by: cellSize) {
                let deltaX = cellX + cellSize / 2 - centerPoint.x
                let deltaY = cellY + cellSize / 2 - centerPoint.y
                let distance = sqrt(deltaX * deltaX + deltaY * deltaY)

                guard distance <= radius else {
                    continue
                }

                NSColor(
                    calibratedHue: getHue(deltaX: deltaX, deltaY: deltaY),
                    saturation: distance / radius,
                    brightness: 0.9,
                    alpha: isEnabled ? 1 : 0.35
                ).setFill()
                NSRect(x: cellX, y: cellY, width: cellSize, height: cellSize).fill()
            }
        }

        NSColor.separatorColor.setStroke()
        NSBezierPath(ovalIn: wheelRect).stroke()
        drawHandle(centerPoint: centerPoint, radius: radius)
    }

    override func mouseDown(with event: NSEvent) {
        updateSelection(event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(event: event)
    }

    private func drawHandle(centerPoint: NSPoint, radius: CGFloat) {
        let angle = CGFloat(hue) * CGFloat.pi * 2
        let handleRadius = CGFloat(saturation) * radius
        let handleCenter = NSPoint(
            x: centerPoint.x + cos(angle) * handleRadius,
            y: centerPoint.y + sin(angle) * handleRadius
        )
        let handleRect = NSRect(x: handleCenter.x - 4, y: handleCenter.y - 4, width: 8, height: 8)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: handleRect).fill()
        NSColor.black.withAlphaComponent(0.75).setStroke()
        NSBezierPath(ovalIn: handleRect).stroke()
    }

    private func updateSelection(event: NSEvent) {
        guard isEnabled else {
            return
        }

        let wheelRect = bounds.insetBy(dx: 2, dy: 2)
        let radius = min(wheelRect.width, wheelRect.height) / 2
        let centerPoint = NSPoint(x: wheelRect.midX, y: wheelRect.midY)
        let eventPoint = convert(event.locationInWindow, from: nil)
        let deltaX = eventPoint.x - centerPoint.x
        let deltaY = eventPoint.y - centerPoint.y
        let distance = min(sqrt(deltaX * deltaX + deltaY * deltaY), radius)

        hue = Double(getHue(deltaX: deltaX, deltaY: deltaY))
        saturation = Double(distance / radius)
        onChange?(hue, saturation)
    }

    private func getHue(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat {
        let angle = atan2(deltaY, deltaX)

        if angle >= 0 {
            return angle / (CGFloat.pi * 2)
        }

        return (angle + CGFloat.pi * 2) / (CGFloat.pi * 2)
    }
}
