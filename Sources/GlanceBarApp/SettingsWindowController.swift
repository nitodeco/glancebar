import AppKit

private let settingsWindowWidth: CGFloat = 280
private let settingsWindowHeight: CGFloat = 232
private let settingsPadding: CGFloat = 16
private let settingsRowSpacing: CGFloat = 10
private let settingsValueWidth: CGFloat = 44
private let colorWellWidth: CGFloat = 54
private let colorWellHeight: CGFloat = 24

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
    private let thresholdValueLabel = NSTextField(labelWithString: "")
    private let pollingStepper = NSStepper()
    private let thresholdStepper = NSStepper()
    private let warningColorWell = NSColorWell()
    private let uploadColorWell = NSColorWell()
    private let downloadColorWell = NSColorWell()

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
        stackView.addArrangedSubview(makeNumberRow(label: "Red above", valueLabel: thresholdValueLabel, stepper: thresholdStepper))
        stackView.addArrangedSubview(makeColorRow(label: "Over threshold", colorWell: warningColorWell))
        stackView.addArrangedSubview(makeColorRow(label: "Upload", colorWell: uploadColorWell))
        stackView.addArrangedSubview(makeColorRow(label: "Download", colorWell: downloadColorWell))

        pollingStepper.target = self
        pollingStepper.action = #selector(updatePollingInterval)
        thresholdStepper.target = self
        thresholdStepper.action = #selector(updateWarningThreshold)
        warningColorWell.target = self
        warningColorWell.action = #selector(updateWarningColor)
        uploadColorWell.target = self
        uploadColorWell.action = #selector(updateUploadColor)
        downloadColorWell.target = self
        downloadColorWell.action = #selector(updateDownloadColor)
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

    private func makeColorRow(label: String, colorWell: NSColorWell) -> NSStackView {
        let row = makeRowStackView()
        let titleLabel = makeTitleLabel(text: label)
        colorWell.controlSize = .small
        colorWell.widthAnchor.constraint(equalToConstant: colorWellWidth).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: colorWellHeight).isActive = true

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(colorWell)

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

    private func syncControls() {
        pollingStepper.minValue = minimumPollingIntervalInSeconds
        pollingStepper.maxValue = maximumPollingIntervalInSeconds
        pollingStepper.increment = 1
        pollingStepper.doubleValue = configuration.pollingIntervalInSeconds
        pollingValueLabel.stringValue = "\(Int(configuration.pollingIntervalInSeconds))s"

        thresholdStepper.minValue = Double(minimumWarningThresholdPercent)
        thresholdStepper.maxValue = Double(maximumWarningThresholdPercent)
        thresholdStepper.increment = 1
        thresholdStepper.integerValue = configuration.warningThresholdPercent
        thresholdValueLabel.stringValue = "\(configuration.warningThresholdPercent)%"

        warningColorWell.color = configuration.warningColor
        uploadColorWell.color = configuration.uploadColor
        downloadColorWell.color = configuration.downloadColor
    }

    @objc private func updatePollingInterval() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: pollingStepper.doubleValue,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColor: configuration.warningColor,
            uploadColor: configuration.uploadColor,
            downloadColor: configuration.downloadColor
        )
        syncControls()
        onChange(configuration)
    }

    @objc private func updateWarningThreshold() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            warningThresholdPercent: thresholdStepper.integerValue,
            warningColor: configuration.warningColor,
            uploadColor: configuration.uploadColor,
            downloadColor: configuration.downloadColor
        )
        syncControls()
        onChange(configuration)
    }

    @objc private func updateWarningColor() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColor: warningColorWell.color,
            uploadColor: configuration.uploadColor,
            downloadColor: configuration.downloadColor
        )
        onChange(configuration)
    }

    @objc private func updateUploadColor() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColor: configuration.warningColor,
            uploadColor: uploadColorWell.color,
            downloadColor: configuration.downloadColor
        )
        onChange(configuration)
    }

    @objc private func updateDownloadColor() {
        configuration = AppConfiguration(
            pollingIntervalInSeconds: configuration.pollingIntervalInSeconds,
            warningThresholdPercent: configuration.warningThresholdPercent,
            warningColor: configuration.warningColor,
            uploadColor: configuration.uploadColor,
            downloadColor: downloadColorWell.color
        )
        onChange(configuration)
    }
}
