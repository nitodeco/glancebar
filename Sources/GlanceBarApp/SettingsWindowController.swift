import AppKit

private let settingsWindowWidth: CGFloat = 280
private let settingsWindowHeight: CGFloat = 282
private let settingsPadding: CGFloat = 16
private let settingsRowSpacing: CGFloat = 10
private let settingsValueWidth: CGFloat = 44
private let colorPresetMenuWidth: CGFloat = 116
private let colorSwatchGlyph = "■"

@MainActor
final class SettingsWindowController: NSWindowController {
    init(configuration: AppConfiguration, onChange: @escaping (AppConfiguration) -> Void) {
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class SettingsView: NSView {
    private var configuration: AppConfiguration
    private let onChange: (AppConfiguration) -> Void
    private let pollingValueLabel = NSTextField(labelWithString: "")
    private let gpuPollingValueLabel = NSTextField(labelWithString: "")
    private let thresholdValueLabel = NSTextField(labelWithString: "")
    private let gpuEnabledButton = NSButton(checkboxWithTitle: "Show GPU", target: nil, action: nil)
    private let pollingStepper = NSStepper()
    private let gpuPollingStepper = NSStepper()
    private let thresholdStepper = NSStepper()
    private let warningColorMenu = NSPopUpButton()
    private let uploadColorMenu = NSPopUpButton()
    private let downloadColorMenu = NSPopUpButton()

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
        stackView.addArrangedSubview(makeNumberRow(label: "GPU polling", valueLabel: gpuPollingValueLabel, stepper: gpuPollingStepper))
        stackView.addArrangedSubview(makeNumberRow(label: "Red above", valueLabel: thresholdValueLabel, stepper: thresholdStepper))
        stackView.addArrangedSubview(makeColorRow(label: "Over threshold", colorMenu: warningColorMenu))
        stackView.addArrangedSubview(makeColorRow(label: "Upload", colorMenu: uploadColorMenu))
        stackView.addArrangedSubview(makeColorRow(label: "Download", colorMenu: downloadColorMenu))

        pollingStepper.target = self
        pollingStepper.action = #selector(updatePollingInterval)
        gpuEnabledButton.target = self
        gpuEnabledButton.action = #selector(updateGpuEnabled)
        gpuPollingStepper.target = self
        gpuPollingStepper.action = #selector(updateGpuPollingInterval)
        thresholdStepper.target = self
        thresholdStepper.action = #selector(updateWarningThreshold)
        configureColorMenu(warningColorMenu, action: #selector(updateWarningColor))
        configureColorMenu(uploadColorMenu, action: #selector(updateUploadColor))
        configureColorMenu(downloadColorMenu, action: #selector(updateDownloadColor))
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

    private func configureColorMenu(_ colorMenu: NSPopUpButton, action: Selector) {
        colorMenu.removeAllItems()
        colorMenu.target = self
        colorMenu.action = action

        for colorPreset in colorPresets {
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
        gpuPollingStepper.minValue = minimumGpuPollingIntervalInSeconds
        gpuPollingStepper.maxValue = maximumGpuPollingIntervalInSeconds
        gpuPollingStepper.increment = 1
        gpuPollingStepper.doubleValue = configuration.gpuPollingIntervalInSeconds
        gpuPollingStepper.isEnabled = configuration.isGpuEnabled
        gpuPollingValueLabel.stringValue = "\(Int(configuration.gpuPollingIntervalInSeconds))s"
        gpuPollingValueLabel.textColor = configuration.isGpuEnabled ? .labelColor : .disabledControlTextColor

        thresholdStepper.minValue = Double(minimumWarningThresholdPercent)
        thresholdStepper.maxValue = Double(maximumWarningThresholdPercent)
        thresholdStepper.increment = 1
        thresholdStepper.integerValue = configuration.warningThresholdPercent
        thresholdValueLabel.stringValue = "\(configuration.warningThresholdPercent)%"

        selectColorPreset(id: configuration.warningColorID, in: warningColorMenu)
        selectColorPreset(id: configuration.uploadColorID, in: uploadColorMenu)
        selectColorPreset(id: configuration.downloadColorID, in: downloadColorMenu)
    }

    private func selectColorPreset(id colorID: String, in colorMenu: NSPopUpButton) {
        guard let colorPreset = getColorPreset(id: colorID) else {
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

    @objc private func updatePollingInterval() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: pollingStepper.doubleValue,
            isGpuEnabled: configuration.isGpuEnabled,
            gpuPollingIntervalInSeconds: configuration.gpuPollingIntervalInSeconds,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColorID: configuration.warningColorID,
            uploadColorID: configuration.uploadColorID,
            downloadColorID: configuration.downloadColorID
        )
        syncControls()
        onChange(configuration)
    }

    @objc private func updateGpuEnabled() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            isGpuEnabled: gpuEnabledButton.state == .on,
            gpuPollingIntervalInSeconds: configuration.gpuPollingIntervalInSeconds,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColorID: configuration.warningColorID,
            uploadColorID: configuration.uploadColorID,
            downloadColorID: configuration.downloadColorID
        )
        syncControls()
        onChange(configuration)
    }

    @objc private func updateGpuPollingInterval() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            isGpuEnabled: configuration.isGpuEnabled,
            gpuPollingIntervalInSeconds: gpuPollingStepper.doubleValue,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColorID: configuration.warningColorID,
            uploadColorID: configuration.uploadColorID,
            downloadColorID: configuration.downloadColorID
        )
        syncControls()
        onChange(configuration)
    }

    @objc private func updateWarningThreshold() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            isGpuEnabled: configuration.isGpuEnabled,
            gpuPollingIntervalInSeconds: configuration.gpuPollingIntervalInSeconds,
            warningThresholdPercent: thresholdStepper.integerValue,
            warningColorID: configuration.warningColorID,
            uploadColorID: configuration.uploadColorID,
            downloadColorID: configuration.downloadColorID
        )
        syncControls()
        onChange(configuration)
    }

    @objc private func updateWarningColor() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            isGpuEnabled: configuration.isGpuEnabled,
            gpuPollingIntervalInSeconds: configuration.gpuPollingIntervalInSeconds,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColorID: selectedColorID(in: warningColorMenu, fallback: configuration.warningColorID),
            uploadColorID: configuration.uploadColorID,
            downloadColorID: configuration.downloadColorID
        )
        onChange(configuration)
    }

    @objc private func updateUploadColor() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            isGpuEnabled: configuration.isGpuEnabled,
            gpuPollingIntervalInSeconds: configuration.gpuPollingIntervalInSeconds,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColorID: configuration.warningColorID,
            uploadColorID: selectedColorID(in: uploadColorMenu, fallback: configuration.uploadColorID),
            downloadColorID: configuration.downloadColorID
        )
        onChange(configuration)
    }

    @objc private func updateDownloadColor() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            isGpuEnabled: configuration.isGpuEnabled,
            gpuPollingIntervalInSeconds: configuration.gpuPollingIntervalInSeconds,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColorID: configuration.warningColorID,
            uploadColorID: configuration.uploadColorID,
            downloadColorID: selectedColorID(in: downloadColorMenu, fallback: configuration.downloadColorID)
        )
        onChange(configuration)
    }
}
