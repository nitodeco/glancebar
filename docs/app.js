const settingsStorageKey = "glancebar-preview-configuration";
const releasesUrl = "https://github.com/nitodeco/glancebar/releases/latest";
const minimumPollingIntervalInSeconds = 1;
const maximumPollingIntervalInSeconds = 60;
const minimumThresholdPercent = 1;
const maximumThresholdPercent = 100;
const minimumColorAdjustmentPercent = -100;
const maximumColorAdjustmentPercent = 100;
const menubarBackgroundColor = [0.91, 0.925, 0.965];

const availableMetrics = [
  { id: "cpu", title: "CPU", shortLabel: "CPU" },
  { id: "gpu", title: "GPU", shortLabel: "GPU" },
  { id: "ram", title: "RAM", shortLabel: "RAM" },
  { id: "ssd", title: "SSD", shortLabel: "SSD" },
  { id: "network", title: "Network", shortLabel: "NET" },
];

const colorPresets = [
  { id: "red", title: "Red", color: [0.86, 0.04, 0.08] },
  { id: "orange", title: "Orange", color: [0.88, 0.28, 0.0] },
  { id: "yellow", title: "Yellow", color: [0.72, 0.54, 0.0] },
  { id: "purple", title: "Purple", color: [0.5, 0.12, 0.88] },
  { id: "blue", title: "Blue", color: [0.0, 0.28, 0.88] },
  { id: "teal", title: "Teal", color: [0.0, 0.56, 0.62] },
  { id: "green", title: "Green", color: [0.0, 0.58, 0.18] },
];

const textColorPresets = [
  { id: "white", title: "White", color: [1, 1, 1] },
  { id: "light-gray", title: "Light gray", color: [0.78, 0.8, 0.84] },
  { id: "dark-gray", title: "Dark gray", color: [0.12, 0.13, 0.15] },
  { id: "black", title: "Black", color: [0, 0, 0] },
];

const colorRoles = [
  { id: "labelTextColor", title: "Label text", usesTextPresets: true },
  { id: "baseTextColor", title: "Value text", usesTextPresets: true },
  { id: "warningColor", title: "Warning", usesTextPresets: false },
  { id: "criticalColor", title: "Critical", usesTextPresets: false },
  { id: "uploadColor", title: "Upload", usesTextPresets: false },
  { id: "downloadColor", title: "Download", usesTextPresets: false },
];

function makeDefaultConfiguration() {
  return {
    isAutoUpdateEnabled: true,
    isLaunchAtLoginEnabled: true,
    enabledMetricIDs: availableMetrics.map((metric) => metric.id),
    orderedMetricIDs: availableMetrics.map((metric) => metric.id),
    pollingIntervalsByMetricID: { cpu: 3, gpu: 9, ram: 3, ssd: 30, network: 10 },
    isLowPowerModePollingAdjustmentEnabled: true,
    warningThresholdPercent: 75,
    criticalThresholdPercent: 90,
    isAutoTextContrastEnabled: true,
    colorIDsByRoleID: {
      labelTextColor: "white",
      baseTextColor: "white",
      warningColor: "yellow",
      criticalColor: "red",
      uploadColor: "purple",
      downloadColor: "blue",
    },
    colorAdjustmentsByRoleID: {},
  };
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function normalizeConfiguration(candidateConfiguration) {
  const defaultConfiguration = makeDefaultConfiguration();
  const metricIDs = availableMetrics.map((metric) => metric.id);
  const requestedOrder = Array.isArray(candidateConfiguration.orderedMetricIDs) ? candidateConfiguration.orderedMetricIDs : [];
  const uniqueRequestedOrder = [...new Set(requestedOrder.filter((metricID) => metricIDs.includes(metricID)))];
  const criticalThresholdPercent = clamp(
    Number(candidateConfiguration.criticalThresholdPercent) || defaultConfiguration.criticalThresholdPercent,
    minimumThresholdPercent,
    maximumThresholdPercent,
  );

  return {
    ...defaultConfiguration,
    ...candidateConfiguration,
    enabledMetricIDs: Array.isArray(candidateConfiguration.enabledMetricIDs)
      ? candidateConfiguration.enabledMetricIDs.filter((metricID) => metricIDs.includes(metricID))
      : defaultConfiguration.enabledMetricIDs,
    orderedMetricIDs: [...uniqueRequestedOrder, ...metricIDs.filter((metricID) => !uniqueRequestedOrder.includes(metricID))],
    pollingIntervalsByMetricID: Object.fromEntries(
      metricIDs.map((metricID) => [
        metricID,
        clamp(
          Number(candidateConfiguration.pollingIntervalsByMetricID?.[metricID]) || defaultConfiguration.pollingIntervalsByMetricID[metricID],
          minimumPollingIntervalInSeconds,
          maximumPollingIntervalInSeconds,
        ),
      ]),
    ),
    criticalThresholdPercent,
    warningThresholdPercent: clamp(
      Number(candidateConfiguration.warningThresholdPercent) || defaultConfiguration.warningThresholdPercent,
      minimumThresholdPercent,
      Math.max(minimumThresholdPercent, criticalThresholdPercent - 1),
    ),
    colorIDsByRoleID: { ...defaultConfiguration.colorIDsByRoleID, ...candidateConfiguration.colorIDsByRoleID },
    colorAdjustmentsByRoleID: { ...candidateConfiguration.colorAdjustmentsByRoleID },
  };
}

function loadConfiguration() {
  try {
    const storedConfiguration = JSON.parse(localStorage.getItem(settingsStorageKey));
    return storedConfiguration ? normalizeConfiguration(storedConfiguration) : makeDefaultConfiguration();
  } catch {
    return makeDefaultConfiguration();
  }
}

function saveConfiguration() {
  try {
    localStorage.setItem(settingsStorageKey, JSON.stringify(configuration));
  } catch {}
}

let configuration = loadConfiguration();
let appStatus = "running";
const settingsSyncers = [];

function updateConfiguration(applyChange) {
  applyChange(configuration);
  configuration = normalizeConfiguration(configuration);
  saveConfiguration();
  syncSettings();
  renderStatusItem();
  restartPolling();
}

function getColorRole(roleID) {
  return colorRoles.find((colorRole) => colorRole.id === roleID);
}

function getColorPresetsForRole(colorRole) {
  return colorRole.usesTextPresets ? textColorPresets : colorPresets;
}

function getColorAdjustment(roleID) {
  return configuration.colorAdjustmentsByRoleID[roleID] ?? { huePercent: 0, saturationPercent: 0, lightnessPercent: 0 };
}

function convertRgbToHsl([red, green, blue]) {
  const maximumValue = Math.max(red, green, blue);
  const minimumValue = Math.min(red, green, blue);
  const lightness = (maximumValue + minimumValue) / 2;
  const delta = maximumValue - minimumValue;

  if (delta === 0) return { hue: 0, saturation: 0, lightness };

  const saturation = delta / (1 - Math.abs(2 * lightness - 1));
  let hue;

  if (maximumValue === red) {
    hue = wrapHue((green - blue) / delta / 6);
  } else if (maximumValue === green) {
    hue = ((blue - red) / delta + 2) / 6;
  } else {
    hue = ((red - green) / delta + 4) / 6;
  }

  return { hue, saturation, lightness };
}

function convertHslToRgb({ hue, saturation, lightness }) {
  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const hueSegment = hue * 6;
  const secondaryComponent = chroma * (1 - Math.abs((hueSegment % 2) - 1));
  const matchComponent = lightness - chroma / 2;
  const primeColorsBySegment = [
    [chroma, secondaryComponent, 0],
    [secondaryComponent, chroma, 0],
    [0, chroma, secondaryComponent],
    [0, secondaryComponent, chroma],
    [secondaryComponent, 0, chroma],
    [chroma, 0, secondaryComponent],
  ];
  const primeColor = primeColorsBySegment[Math.min(5, Math.floor(hueSegment))];

  return primeColor.map((component) => component + matchComponent);
}

function wrapHue(hue) {
  if (hue < 0) return hue + 1;
  if (hue > 1) return hue - 1;
  return hue;
}

function applyColorAdjustment(color, colorAdjustment) {
  const hslColor = convertRgbToHsl(color);

  return convertHslToRgb({
    hue: wrapHue(hslColor.hue + (colorAdjustment.huePercent / 100) * 0.08),
    saturation: clamp(hslColor.saturation + (colorAdjustment.saturationPercent / 100) * 0.35, 0, 1),
    lightness: clamp(hslColor.lightness + (colorAdjustment.lightnessPercent / 100) * 0.35, 0.04, 0.96),
  });
}

function getConfiguredColor(roleID) {
  const colorRole = getColorRole(roleID);
  const presets = getColorPresetsForRole(colorRole);
  const colorPreset = presets.find((preset) => preset.id === configuration.colorIDsByRoleID[roleID]) ?? presets[0];

  return applyColorAdjustment(colorPreset.color, getColorAdjustment(roleID));
}

function getRelativeLuminance(color) {
  const linearComponents = color.map((component) =>
    component <= 0.03928 ? component / 12.92 : ((component + 0.055) / 1.055) ** 2.4,
  );
  return 0.2126 * linearComponents[0] + 0.7152 * linearComponents[1] + 0.0722 * linearComponents[2];
}

function getContrastRatio(firstColor, secondColor) {
  const lighterLuminance = Math.max(getRelativeLuminance(firstColor), getRelativeLuminance(secondColor));
  const darkerLuminance = Math.min(getRelativeLuminance(firstColor), getRelativeLuminance(secondColor));
  return (lighterLuminance + 0.05) / (darkerLuminance + 0.05);
}

function ensureReadableColor(color, minimumContrastRatio) {
  const hslColor = convertRgbToHsl(color);
  let readableColor = color;

  while (getContrastRatio(readableColor, menubarBackgroundColor) < minimumContrastRatio && hslColor.lightness > 0.04) {
    hslColor.lightness = Math.max(0.04, hslColor.lightness - 0.03);
    readableColor = convertHslToRgb(hslColor);
  }

  return readableColor;
}

function getDisplayedColor(roleID) {
  const configuredColor = getConfiguredColor(roleID);
  if (!configuration.isAutoTextContrastEnabled) return configuredColor;

  const isTextRole = getColorRole(roleID).usesTextPresets;
  return ensureReadableColor(configuredColor, isTextRole ? 7 : 3.2);
}

function toCssColor(color) {
  const [red, green, blue] = color.map((component) => Math.round(clamp(component, 0, 1) * 255));
  return `rgb(${red} ${green} ${blue})`;
}

const metricValues = {
  cpu: 14,
  gpu: 6,
  ram: 64,
  ssd: 78,
  uploadBytesPerSecond: 420,
  downloadBytesPerSecond: 1240,
};

function sampleSkewedRange(minimum, maximum) {
  return Math.round(minimum * (maximum / minimum) ** (Math.random() ** 1.8));
}

function sampleMetric(metricID) {
  if (metricID === "cpu") {
    const isSpike = Math.random() < 0.1;
    metricValues.cpu = isSpike
      ? 78 + Math.random() * 20
      : clamp(metricValues.cpu + (14 - metricValues.cpu) * 0.5 + (Math.random() * 2 - 1) * 7, 2, 99);
  } else if (metricID === "gpu") {
    const isSpike = Math.random() < 0.06;
    metricValues.gpu = isSpike
      ? 55 + Math.random() * 30
      : clamp(metricValues.gpu + (6 - metricValues.gpu) * 0.6 + (Math.random() * 2 - 1) * 3, 0, 99);
  } else if (metricID === "ram") {
    metricValues.ram = clamp(metricValues.ram + (Math.random() * 2 - 1) * 1.5, 58, 72);
  } else if (metricID === "ssd") {
    metricValues.ssd = clamp(metricValues.ssd + (Math.random() < 0.2 ? 0.4 : 0), 0, 100);
  } else if (metricID === "network") {
    metricValues.uploadBytesPerSecond = sampleSkewedRange(80, 90000);
    metricValues.downloadBytesPerSecond = sampleSkewedRange(200, 4200000);
  }
}

const pollingTimers = [];

function restartPolling() {
  pollingTimers.splice(0).forEach((pollingTimer) => clearInterval(pollingTimer));
  if (appStatus !== "running") return;

  configuration.enabledMetricIDs.forEach((metricID) => {
    const pollingIntervalInSeconds = configuration.pollingIntervalsByMetricID[metricID];
    pollingTimers.push(
      setInterval(() => {
        sampleMetric(metricID);
        renderStatusItem();
      }, pollingIntervalInSeconds * 1000),
    );
  });
}

function formatDecimal(value) {
  return value.toFixed(1).replace(".0", "");
}

function formatThroughputParts(bytesPerSecond) {
  if (bytesPerSecond >= 1_000_000) {
    return { value: formatDecimal(bytesPerSecond / 1_000_000), unit: "MB" };
  }
  return { value: formatDecimal(bytesPerSecond / 1_000), unit: "KB" };
}

function getValueColor(percent) {
  if (percent > configuration.criticalThresholdPercent) return getDisplayedColor("criticalColor");
  if (percent > configuration.warningThresholdPercent) return getDisplayedColor("warningColor");
  return getDisplayedColor("baseTextColor");
}

function createElement(tagName, className, textContent) {
  const element = document.createElement(tagName);
  if (className) element.className = className;
  if (textContent !== undefined) element.textContent = textContent;
  return element;
}

const statusItemButton = document.querySelector("[data-status-item]");
const statusMetricsContainer = document.querySelector("[data-status-metrics]");
const statusMenu = document.querySelector("[data-status-menu]");

function makeNetworkRow(bytesPerSecond, roleID) {
  const throughputFormat = formatThroughputParts(bytesPerSecond);
  const row = createElement("span", "status-network-row");
  row.style.color = toCssColor(getDisplayedColor(roleID));
  row.append(
    createElement("span", "status-network-value", throughputFormat.value),
    createElement("span", "status-network-unit", throughputFormat.unit),
  );
  return row;
}

function makeStatusColumn(metricID) {
  if (metricID === "network") {
    const column = createElement("span", "status-column status-column-network");
    column.append(
      makeNetworkRow(metricValues.uploadBytesPerSecond, "uploadColor"),
      makeNetworkRow(metricValues.downloadBytesPerSecond, "downloadColor"),
    );
    return column;
  }

  const metric = availableMetrics.find((availableMetric) => availableMetric.id === metricID);
  const percent = Math.round(metricValues[metricID]);
  const column = createElement("span", "status-column");
  const label = createElement("span", "status-label", metric.shortLabel);
  const value = createElement("span", "status-value", `${percent}%`);
  label.style.color = toCssColor(getDisplayedColor("labelTextColor"));
  value.style.color = toCssColor(getValueColor(percent));
  column.append(label, value);
  return column;
}

function renderStatusItem() {
  statusItemButton.hidden = appStatus !== "running";
  const visibleMetricIDs = configuration.orderedMetricIDs.filter((metricID) => configuration.enabledMetricIDs.includes(metricID));
  statusMetricsContainer.replaceChildren(...visibleMetricIDs.map(makeStatusColumn));
}

function toggleMetric(metricID) {
  updateConfiguration((draftConfiguration) => {
    draftConfiguration.enabledMetricIDs = draftConfiguration.enabledMetricIDs.includes(metricID)
      ? draftConfiguration.enabledMetricIDs.filter((enabledMetricID) => enabledMetricID !== metricID)
      : [...draftConfiguration.enabledMetricIDs, metricID];
  });
}

function makeStatusMenuItem({ title, shortcut, isChecked, onSelect }) {
  const menuItem = createElement("button", "status-menu-item");
  menuItem.type = "button";
  menuItem.setAttribute("role", isChecked === undefined ? "menuitem" : "menuitemcheckbox");
  if (isChecked !== undefined) menuItem.setAttribute("aria-checked", String(isChecked));
  menuItem.append(createElement("span", "status-menu-check", isChecked ? "✓" : ""), createElement("span", "status-menu-title", title));
  if (shortcut) menuItem.append(createElement("span", "status-menu-shortcut", shortcut));
  menuItem.addEventListener("click", () => {
    closeStatusMenu();
    onSelect();
  });
  return menuItem;
}

function renderStatusMenu() {
  const menuEntries = [];

  if (!configuration.isAutoUpdateEnabled) {
    menuEntries.push({ title: "Check for Updates…", onSelect: () => window.open(releasesUrl, "_blank", "noopener") }, "separator");
  }

  availableMetrics.forEach((metric) => {
    menuEntries.push({
      title: metric.title,
      isChecked: configuration.enabledMetricIDs.includes(metric.id),
      onSelect: () => toggleMetric(metric.id),
    });
  });

  menuEntries.push(
    "separator",
    { title: "Settings", shortcut: "⌘,", onSelect: () => showWindow("settings") },
    { title: "Quit", shortcut: "⌘Q", onSelect: () => stopApp("quit") },
  );

  statusMenu.replaceChildren(
    ...menuEntries.map((menuEntry) =>
      menuEntry === "separator" ? createElement("div", "status-menu-separator") : makeStatusMenuItem(menuEntry),
    ),
  );
}

function openStatusMenu() {
  renderStatusMenu();
  statusMenu.hidden = false;
  statusItemButton.setAttribute("aria-expanded", "true");
  statusMenu.querySelector(".status-menu-item")?.focus();
}

function closeStatusMenu() {
  statusMenu.hidden = true;
  statusItemButton.setAttribute("aria-expanded", "false");
}

statusItemButton.addEventListener("click", () => {
  if (statusMenu.hidden) {
    openStatusMenu();
  } else {
    closeStatusMenu();
  }
});

document.addEventListener("pointerdown", (pointerEvent) => {
  if (!statusMenu.hidden && !pointerEvent.target.closest(".status-item-anchor")) closeStatusMenu();
});

document.addEventListener("keydown", (keyboardEvent) => {
  if (keyboardEvent.key === "Escape" && !statusMenu.hidden) {
    closeStatusMenu();
    statusItemButton.focus();
  }
});

const appStatusNotice = document.querySelector("[data-app-status-notice]");
const appStatusMessage = document.querySelector("[data-app-status-message]");
const relaunchButton = document.querySelector("[data-relaunch-app]");

function stopApp(nextAppStatus) {
  appStatus = nextAppStatus;
  closeWindow("settings");
  closeWindow("color-editor");

  if (nextAppStatus === "uninstalled") {
    configuration = makeDefaultConfiguration();
    try {
      localStorage.removeItem(settingsStorageKey);
    } catch {}
    syncSettings();
  }

  appStatusMessage.textContent = nextAppStatus === "uninstalled" ? "GlanceBar was uninstalled." : "GlanceBar is not running.";
  relaunchButton.textContent = nextAppStatus === "uninstalled" ? "Reinstall" : "Open GlanceBar";
  appStatusNotice.hidden = false;
  restartPolling();
  renderStatusItem();
}

relaunchButton.addEventListener("click", () => {
  appStatus = "running";
  appStatusNotice.hidden = true;
  restartPolling();
  renderStatusItem();
});

function makeSettingsRow(labelText, labelTarget) {
  const row = createElement("div", "settings-row");
  const label = createElement(labelTarget ? "label" : "span", "settings-label", labelText);
  if (labelTarget) label.htmlFor = labelTarget;
  row.append(label);
  return row;
}

let generatedControlCount = 0;

function makeControlID() {
  generatedControlCount += 1;
  return `settings-control-${generatedControlCount}`;
}

function makeCheckboxRow({ labelText, readValue, writeValue }) {
  const controlID = makeControlID();
  const row = makeSettingsRow(labelText);
  const checkboxLabel = createElement("label", "settings-checkbox");
  const checkbox = createElement("input");
  checkbox.type = "checkbox";
  checkbox.id = controlID;
  checkbox.setAttribute("aria-label", labelText);
  checkbox.addEventListener("change", () => updateConfiguration(() => writeValue(checkbox.checked)));
  checkboxLabel.append(checkbox, createElement("span", "", "Enabled"));
  row.append(checkboxLabel);
  settingsSyncers.push(() => {
    checkbox.checked = readValue();
  });
  return row;
}

function makeNumberRow({ labelText, readValue, writeValue, formatValue, readMinimum, readMaximum }) {
  const row = makeSettingsRow(labelText);
  const valueLabel = createElement("span", "settings-value");
  const stepper = createElement("span", "stepper");
  const incrementButton = createElement("button", "stepper-button stepper-increment");
  const decrementButton = createElement("button", "stepper-button stepper-decrement");
  incrementButton.type = "button";
  decrementButton.type = "button";
  incrementButton.setAttribute("aria-label", `Increase ${labelText}`);
  decrementButton.setAttribute("aria-label", `Decrease ${labelText}`);
  incrementButton.addEventListener("click", () =>
    updateConfiguration(() => writeValue(clamp(readValue() + 1, readMinimum(), readMaximum()))),
  );
  decrementButton.addEventListener("click", () =>
    updateConfiguration(() => writeValue(clamp(readValue() - 1, readMinimum(), readMaximum()))),
  );
  stepper.append(incrementButton, decrementButton);
  row.append(valueLabel, stepper);
  settingsSyncers.push(() => {
    valueLabel.textContent = formatValue(readValue());
    incrementButton.disabled = readValue() >= readMaximum();
    decrementButton.disabled = readValue() <= readMinimum();
  });
  return row;
}

function reorderMetric(metricID, dropIndex) {
  updateConfiguration((draftConfiguration) => {
    const orderedMetricIDs = [...draftConfiguration.orderedMetricIDs];
    const originalIndex = orderedMetricIDs.indexOf(metricID);
    orderedMetricIDs.splice(originalIndex, 1);
    const insertIndex = originalIndex < dropIndex ? Math.max(0, dropIndex - 1) : dropIndex;
    orderedMetricIDs.splice(Math.min(insertIndex, orderedMetricIDs.length), 0, metricID);
    draftConfiguration.orderedMetricIDs = orderedMetricIDs;
  });
}

function makeMetricList() {
  const row = createElement("div", "settings-row settings-row-list");
  const list = createElement("ul", "metric-list");
  const dropIndicator = createElement("li", "metric-drop-indicator");
  dropIndicator.setAttribute("aria-hidden", "true");
  list.setAttribute("aria-label", "Metrics shown in the menu bar, drag to reorder");
  let draggedMetricID = null;
  let dropIndex = null;

  function getDropIndex(clientY) {
    const metricRows = [...list.querySelectorAll(".metric-row")];
    const rowIndex = metricRows.findIndex((metricRow) => {
      const rowBounds = metricRow.getBoundingClientRect();
      return clientY < rowBounds.top + rowBounds.height / 2;
    });
    return rowIndex === -1 ? metricRows.length : rowIndex;
  }

  list.addEventListener("dragover", (dragEvent) => {
    if (!draggedMetricID) return;
    dragEvent.preventDefault();
    dropIndex = getDropIndex(dragEvent.clientY);
    const metricRows = list.querySelectorAll(".metric-row");
    const referenceRow = metricRows[Math.min(dropIndex, metricRows.length - 1)];
    const indicatorTop = dropIndex < metricRows.length ? referenceRow.offsetTop : referenceRow.offsetTop + referenceRow.offsetHeight;
    dropIndicator.style.top = `${indicatorTop - 1}px`;
    dropIndicator.classList.add("is-visible");
  });

  list.addEventListener("dragleave", (dragEvent) => {
    if (!list.contains(dragEvent.relatedTarget)) dropIndicator.classList.remove("is-visible");
  });

  list.addEventListener("drop", (dragEvent) => {
    dragEvent.preventDefault();
    if (draggedMetricID && dropIndex !== null) reorderMetric(draggedMetricID, dropIndex);
  });

  function renderMetricRows() {
    const metricRows = configuration.orderedMetricIDs.map((metricID) => {
      const metric = availableMetrics.find((availableMetric) => availableMetric.id === metricID);
      const metricRow = createElement("li", "metric-row");
      const checkbox = createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = configuration.enabledMetricIDs.includes(metricID);
      checkbox.setAttribute("aria-label", `Show ${metric.title}`);
      checkbox.addEventListener("change", () => toggleMetric(metricID));
      metricRow.draggable = true;
      metricRow.append(checkbox, createElement("span", "metric-name", metric.title));
      metricRow.addEventListener("dragstart", (dragEvent) => {
        draggedMetricID = metricID;
        dragEvent.dataTransfer.effectAllowed = "move";
        dragEvent.dataTransfer.setData("text/plain", metricID);
        metricRow.classList.add("is-dragging");
      });
      metricRow.addEventListener("dragend", () => {
        draggedMetricID = null;
        dropIndex = null;
        dropIndicator.classList.remove("is-visible");
        metricRow.classList.remove("is-dragging");
      });
      return metricRow;
    });
    list.replaceChildren(...metricRows, dropIndicator);
  }

  settingsSyncers.push(renderMetricRows);
  row.append(list);
  return row;
}

function makeColorRow(colorRole) {
  const controlID = makeControlID();
  const row = makeSettingsRow(colorRole.title, controlID);
  const swatch = createElement("span", "color-swatch");
  const select = createElement("select", "mac-select");
  const editButton = createElement("button", "mac-button", "Edit");
  select.id = controlID;
  editButton.type = "button";
  editButton.setAttribute("aria-label", `Edit ${colorRole.title} color`);
  getColorPresetsForRole(colorRole).forEach((colorPreset) => {
    const option = createElement("option", "", colorPreset.title);
    option.value = colorPreset.id;
    select.append(option);
  });
  select.addEventListener("change", () =>
    updateConfiguration((draftConfiguration) => {
      draftConfiguration.colorIDsByRoleID[colorRole.id] = select.value;
    }),
  );
  editButton.addEventListener("click", () => openColorEditor(colorRole.id));
  const selectWrapper = createElement("span", "color-select");
  selectWrapper.append(swatch, select);
  row.append(selectWrapper, editButton);
  settingsSyncers.push(() => {
    select.value = configuration.colorIDsByRoleID[colorRole.id];
    swatch.style.background = toCssColor(getConfiguredColor(colorRole.id));
  });
  return row;
}

function buildSettings() {
  const generalPanel = document.querySelector('[data-panel="general"]');
  const metricsPanel = document.querySelector('[data-panel="metrics"]');
  const colorsPanel = document.querySelector('[data-panel="colors"]');
  const uninstallButton = createElement("button", "mac-button settings-uninstall", "Uninstall");
  uninstallButton.type = "button";
  uninstallButton.addEventListener("click", () => stopApp("uninstalled"));

  generalPanel.append(
    makeCheckboxRow({
      labelText: "Auto-update",
      readValue: () => configuration.isAutoUpdateEnabled,
      writeValue: (isEnabled) => (configuration.isAutoUpdateEnabled = isEnabled),
    }),
    makeCheckboxRow({
      labelText: "Launch at login",
      readValue: () => configuration.isLaunchAtLoginEnabled,
      writeValue: (isEnabled) => (configuration.isLaunchAtLoginEnabled = isEnabled),
    }),
    makeNumberRow({
      labelText: "Warning above",
      readValue: () => configuration.warningThresholdPercent,
      writeValue: (thresholdPercent) => (configuration.warningThresholdPercent = thresholdPercent),
      formatValue: (thresholdPercent) => `${thresholdPercent}%`,
      readMinimum: () => minimumThresholdPercent,
      readMaximum: () => Math.max(minimumThresholdPercent, configuration.criticalThresholdPercent - 1),
    }),
    makeNumberRow({
      labelText: "Critical above",
      readValue: () => configuration.criticalThresholdPercent,
      writeValue: (thresholdPercent) => (configuration.criticalThresholdPercent = thresholdPercent),
      formatValue: (thresholdPercent) => `${thresholdPercent}%`,
      readMinimum: () => minimumThresholdPercent,
      readMaximum: () => maximumThresholdPercent,
    }),
    makeMetricList(),
    uninstallButton,
  );

  metricsPanel.append(
    ...availableMetrics.map((metric) =>
      makeNumberRow({
        labelText: metric.title,
        readValue: () => configuration.pollingIntervalsByMetricID[metric.id],
        writeValue: (intervalInSeconds) => (configuration.pollingIntervalsByMetricID[metric.id] = intervalInSeconds),
        formatValue: (intervalInSeconds) => `${intervalInSeconds}s`,
        readMinimum: () => minimumPollingIntervalInSeconds,
        readMaximum: () => maximumPollingIntervalInSeconds,
      }),
    ),
    makeCheckboxRow({
      labelText: "Low Power Mode ×5",
      readValue: () => configuration.isLowPowerModePollingAdjustmentEnabled,
      writeValue: (isEnabled) => (configuration.isLowPowerModePollingAdjustmentEnabled = isEnabled),
    }),
  );

  colorsPanel.append(
    makeCheckboxRow({
      labelText: "Auto contrast",
      readValue: () => configuration.isAutoTextContrastEnabled,
      writeValue: (isEnabled) => (configuration.isAutoTextContrastEnabled = isEnabled),
    }),
    ...colorRoles.map(makeColorRow),
  );
}

function syncSettings() {
  settingsSyncers.forEach((syncSetting) => syncSetting());
}

const tabs = [...document.querySelectorAll("[data-tab]")];

function selectTab(selectedTab) {
  tabs.forEach((tab) => {
    const isSelected = tab === selectedTab;
    tab.setAttribute("aria-selected", String(isSelected));
    tab.tabIndex = isSelected ? 0 : -1;
    document.querySelector(`[data-panel="${tab.dataset.tab}"]`).hidden = !isSelected;
  });
}

tabs.forEach((tab, tabIndex) => {
  tab.addEventListener("click", () => selectTab(tab));
  tab.addEventListener("keydown", (keyboardEvent) => {
    const directionByKey = { ArrowRight: 1, ArrowLeft: -1 };
    const direction = directionByKey[keyboardEvent.key];
    if (!direction) return;
    const nextTab = tabs[(tabIndex + direction + tabs.length) % tabs.length];
    selectTab(nextTab);
    nextTab.focus();
  });
});

let editedColorRoleID = colorRoles[0].id;
const colorEditorTitle = document.querySelector("[data-color-editor-title]");
const colorEditorContent = document.querySelector("[data-color-editor-content]");

function buildColorEditor() {
  const preview = createElement("div", "color-editor-preview");
  const sliderRows = [
    { title: "Hue", adjustmentKey: "huePercent" },
    { title: "Saturation", adjustmentKey: "saturationPercent" },
    { title: "Lightness", adjustmentKey: "lightnessPercent" },
  ].map(({ title, adjustmentKey }) => {
    const controlID = makeControlID();
    const sliderRow = createElement("div", "color-editor-row");
    const label = createElement("label", "color-editor-label", title);
    const slider = createElement("input");
    const valueLabel = createElement("span", "color-editor-value");
    label.htmlFor = controlID;
    slider.id = controlID;
    slider.type = "range";
    slider.min = String(minimumColorAdjustmentPercent);
    slider.max = String(maximumColorAdjustmentPercent);
    slider.addEventListener("input", () =>
      updateConfiguration((draftConfiguration) => {
        draftConfiguration.colorAdjustmentsByRoleID[editedColorRoleID] = {
          ...getColorAdjustment(editedColorRoleID),
          [adjustmentKey]: Number(slider.value),
        };
      }),
    );
    sliderRow.append(label, slider, valueLabel);
    settingsSyncers.push(() => {
      const adjustmentValue = getColorAdjustment(editedColorRoleID)[adjustmentKey];
      slider.value = String(adjustmentValue);
      valueLabel.textContent = adjustmentValue > 0 ? `+${adjustmentValue}` : String(adjustmentValue);
    });
    return sliderRow;
  });
  const resetButton = createElement("button", "mac-button", "Reset");
  const doneButton = createElement("button", "mac-button mac-button-default", "Done");
  resetButton.type = "button";
  doneButton.type = "button";
  resetButton.addEventListener("click", () =>
    updateConfiguration((draftConfiguration) => {
      delete draftConfiguration.colorAdjustmentsByRoleID[editedColorRoleID];
    }),
  );
  doneButton.addEventListener("click", () => closeWindow("color-editor"));
  const buttonRow = createElement("div", "color-editor-buttons");
  buttonRow.append(resetButton, doneButton);
  colorEditorContent.append(preview, ...sliderRows, buttonRow);
  settingsSyncers.push(() => {
    colorEditorTitle.textContent = `Edit ${getColorRole(editedColorRoleID).title} Color`;
    preview.style.background = toCssColor(getConfiguredColor(editedColorRoleID));
  });
}

function openColorEditor(roleID) {
  editedColorRoleID = roleID;
  syncSettings();
  showWindow("color-editor");
}

const menubar = document.querySelector(".menubar");
const desktop = document.querySelector("[data-desktop]");
const windowElements = [...document.querySelectorAll("[data-window]")];
const windowMargin = 24;
const compactWindowMargin = 12;
const compactLayoutMaximumWidth = 600;
const windowGap = 24;
const cascadeOffset = 44;
const footerClearance = 44;
const minimumVisibleWindowWidth = 80;
const titlebarHeight = 28;
const staticLayoutQuery = matchMedia("(max-width: 640px)");
const userPositionedWindows = new Set();
const measuredWindowSizes = new Map();
const windowStack = [...windowElements];

function getWindowElement(windowName) {
  return document.querySelector(`[data-window="${windowName}"]`);
}

function isDialogWindow(windowElement) {
  return windowElement.classList.contains("window-dialog");
}

function getWindowSize(windowElement) {
  if (!windowElement.hidden) {
    measuredWindowSizes.set(windowElement, { width: windowElement.offsetWidth, height: windowElement.offsetHeight });
  }
  return measuredWindowSizes.get(windowElement) ?? { width: 0, height: 0 };
}

function getWindowArea(windowElement) {
  if (isDialogWindow(windowElement)) {
    const menubarHeight = menubar.offsetHeight;
    return {
      left: 0,
      top: menubarHeight,
      width: document.documentElement.clientWidth,
      height: window.innerHeight - menubarHeight,
    };
  }
  return { left: 0, top: 0, width: desktop.clientWidth, height: desktop.clientHeight };
}

function getWindowPosition(windowElement) {
  return {
    left: Number.parseFloat(windowElement.style.left) || 0,
    top: Number.parseFloat(windowElement.style.top) || 0,
  };
}

function clampWindowPosition(windowElement, position) {
  const windowArea = getWindowArea(windowElement);
  const windowSize = getWindowSize(windowElement);
  return {
    left: clamp(
      position.left,
      windowArea.left - windowSize.width + minimumVisibleWindowWidth,
      windowArea.left + windowArea.width - minimumVisibleWindowWidth,
    ),
    top: clamp(position.top, windowArea.top, windowArea.top + windowArea.height - titlebarHeight),
  };
}

function setWindowPosition(windowElement, position) {
  windowElement.style.left = `${Math.round(position.left)}px`;
  windowElement.style.top = `${Math.round(position.top)}px`;
}

function clearWindowPosition(windowElement) {
  windowElement.style.left = "";
  windowElement.style.top = "";
}

function calculateDocumentWindowPositions(featuresSize, heroSize) {
  const desktopWidth = desktop.clientWidth;
  const margin = desktopWidth < compactLayoutMaximumWidth ? compactWindowMargin : windowMargin;
  const visibleDesktopHeight = window.innerHeight - menubar.offsetHeight;
  const sideBySideWidth = heroSize.width + windowGap + featuresSize.width;

  if (sideBySideWidth + margin * 2 <= desktopWidth) {
    const tallestHeight = Math.max(featuresSize.height, heroSize.height);
    const groupLeft = (desktopWidth - sideBySideWidth) / 2;
    const groupTop = Math.max(margin, (visibleDesktopHeight - footerClearance - tallestHeight) / 2);
    return {
      hero: { left: groupLeft, top: groupTop },
      features: { left: groupLeft + heroSize.width + windowGap, top: groupTop },
    };
  }

  if (desktopWidth >= compactLayoutMaximumWidth) {
    return {
      hero: { left: margin, top: margin },
      features: { left: desktopWidth - margin - featuresSize.width, top: margin + cascadeOffset },
    };
  }

  return {
    hero: { left: margin, top: margin },
    features: { left: desktopWidth - margin - featuresSize.width, top: margin + heroSize.height + windowGap },
  };
}

function layoutDocumentWindows() {
  const featuresWindow = getWindowElement("features");
  const heroWindow = getWindowElement("hero");
  desktop.classList.add("is-laid-out");

  if (staticLayoutQuery.matches) {
    desktop.style.minHeight = "";
    clearWindowPosition(featuresWindow);
    clearWindowPosition(heroWindow);
    return;
  }

  const featuresSize = getWindowSize(featuresWindow);
  const heroSize = getWindowSize(heroWindow);
  const positionsByWindowName = calculateDocumentWindowPositions(featuresSize, heroSize);
  const layoutBottom = Math.max(
    positionsByWindowName.features.top + featuresSize.height,
    positionsByWindowName.hero.top + heroSize.height,
  );

  const visibleDesktopHeight = window.innerHeight - menubar.offsetHeight;
  desktop.style.minHeight = `${Math.ceil(Math.max(visibleDesktopHeight, layoutBottom + footerClearance))}px`;

  [featuresWindow, heroWindow].forEach((windowElement) => {
    if (userPositionedWindows.has(windowElement)) {
      setWindowPosition(windowElement, clampWindowPosition(windowElement, getWindowPosition(windowElement)));
      return;
    }
    setWindowPosition(windowElement, positionsByWindowName[windowElement.dataset.window]);
  });
}

function centerDialog(windowElement) {
  const windowArea = getWindowArea(windowElement);
  const windowSize = getWindowSize(windowElement);
  setWindowPosition(
    windowElement,
    clampWindowPosition(windowElement, {
      left: windowArea.left + (windowArea.width - windowSize.width) / 2,
      top: windowArea.top + Math.max(compactWindowMargin, (windowArea.height - windowSize.height) / 3),
    }),
  );
}

function placeDialog(windowElement) {
  if (staticLayoutQuery.matches) {
    clearWindowPosition(windowElement);
    return;
  }
  if (userPositionedWindows.has(windowElement) && windowElement.style.left) {
    setWindowPosition(windowElement, clampWindowPosition(windowElement, getWindowPosition(windowElement)));
    return;
  }
  centerDialog(windowElement);
}

function bringToFront(windowElement) {
  windowStack.splice(windowStack.indexOf(windowElement), 1);
  windowStack.push(windowElement);
  windowStack.forEach((stackedWindowElement, stackIndex) => {
    stackedWindowElement.style.zIndex = String(stackIndex + 1);
  });
  windowElements.forEach((otherWindowElement) => otherWindowElement.classList.toggle("is-active", otherWindowElement === windowElement));
}

function showWindow(windowName) {
  const windowElement = getWindowElement(windowName);
  windowElement.hidden = false;

  if (isDialogWindow(windowElement)) {
    placeDialog(windowElement);
  } else {
    layoutDocumentWindows();
    windowElement.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  bringToFront(windowElement);
}

function closeWindow(windowName) {
  getWindowElement(windowName).hidden = true;
  const nextActiveWindowElement = windowStack.findLast((stackedWindowElement) => !stackedWindowElement.hidden);
  if (nextActiveWindowElement) bringToFront(nextActiveWindowElement);
}

const nonDraggableTargetSelector = "button, a, input, select, textarea, label, [draggable='true'], [role='tab']";

function canStartWindowDrag(pointerDownEvent) {
  if (staticLayoutQuery.matches || pointerDownEvent.button !== 0) return false;
  if (pointerDownEvent.target.closest(nonDraggableTargetSelector)) return false;
  return Boolean(pointerDownEvent.target.closest("[data-window-titlebar]"));
}

function enableWindowDragging(windowElement) {
  windowElement.addEventListener("pointerdown", (pointerDownEvent) => {
    bringToFront(windowElement);
    if (!canStartWindowDrag(pointerDownEvent)) return;
    pointerDownEvent.preventDefault();

    const startPosition = getWindowPosition(windowElement);
    windowElement.setPointerCapture(pointerDownEvent.pointerId);
    document.body.classList.add("is-dragging-window");

    function moveWindow(pointerMoveEvent) {
      userPositionedWindows.add(windowElement);
      setWindowPosition(
        windowElement,
        clampWindowPosition(windowElement, {
          left: startPosition.left + pointerMoveEvent.clientX - pointerDownEvent.clientX,
          top: startPosition.top + pointerMoveEvent.clientY - pointerDownEvent.clientY,
        }),
      );
    }

    function stopDragging() {
      document.body.classList.remove("is-dragging-window");
      windowElement.removeEventListener("pointermove", moveWindow);
      windowElement.removeEventListener("pointerup", stopDragging);
      windowElement.removeEventListener("pointercancel", stopDragging);
    }

    windowElement.addEventListener("pointermove", moveWindow);
    windowElement.addEventListener("pointerup", stopDragging);
    windowElement.addEventListener("pointercancel", stopDragging);
  });
}

windowElements.forEach(enableWindowDragging);

function handleViewportResize() {
  fitMenubar();
  layoutDocumentWindows();
  windowElements.filter((windowElement) => isDialogWindow(windowElement) && !windowElement.hidden).forEach(placeDialog);
}

window.addEventListener("resize", handleViewportResize);
staticLayoutQuery.addEventListener("change", handleViewportResize);

document.querySelectorAll("[data-open-window]").forEach((menuButton) => {
  menuButton.addEventListener("click", () => showWindow(menuButton.dataset.openWindow));
});

document.querySelectorAll("[data-close-window]").forEach((closeButton) => {
  closeButton.addEventListener("click", () => closeWindow(closeButton.dataset.closeWindow));
});

const clockLabel = document.querySelector("[data-clock]");
const clockFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  month: "short",
  day: "numeric",
  hour: "2-digit",
  minute: "2-digit",
  hourCycle: "h23",
});

function renderClock() {
  clockLabel.textContent = clockFormatter.format(new Date()).replaceAll(",", "");
}

const menubarMenus = document.querySelector(".menubar-menus");
const menubarStatus = document.querySelector(".menubar-status");
const collapsibleMenubarItems = [
  ...[...document.querySelectorAll(".menubar-menu")].reverse(),
  ...[...document.querySelectorAll(".system-icon")].reverse(),
  clockLabel,
];

function doesMenubarOverflow() {
  const menubarStyle = getComputedStyle(menubar);
  const availableWidth =
    menubar.clientWidth -
    Number.parseFloat(menubarStyle.paddingLeft) -
    Number.parseFloat(menubarStyle.paddingRight) -
    Number.parseFloat(menubarStyle.columnGap);
  return menubarMenus.scrollWidth + menubarStatus.scrollWidth > availableWidth;
}

function fitMenubar() {
  collapsibleMenubarItems.forEach((menubarItem) => menubarItem.classList.remove("is-collapsed"));
  for (const menubarItem of collapsibleMenubarItems) {
    if (!doesMenubarOverflow()) return;
    menubarItem.classList.add("is-collapsed");
  }
}

new ResizeObserver(fitMenubar).observe(document.querySelector("[data-status-metrics]"));

function showLatestVersion() {
  fetch("https://api.github.com/repos/nitodeco/glancebar/releases/latest")
    .then((response) => (response.ok ? response.json() : null))
    .then((release) => {
      const versionLabel = document.querySelector("[data-latest-version]");
      if (!release?.tag_name || !versionLabel) return;
      versionLabel.textContent = release.tag_name;
      versionLabel.hidden = false;
    })
    .catch(() => {});
}

buildSettings();
buildColorEditor();
syncSettings();
renderStatusItem();
restartPolling();
renderClock();
setInterval(renderClock, 10000);
fitMenubar();
layoutDocumentWindows();
bringToFront(getWindowElement("features"));
bringToFront(getWindowElement("hero"));
document.fonts.ready.then(layoutDocumentWindows);
showLatestVersion();
