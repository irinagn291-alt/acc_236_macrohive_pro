import AVFoundation
import UIKit

@MainActor
final class ForagerViewController: UIViewController, ForagerPresentable, UITextFieldDelegate {
    weak var listener: ForagerPresentableListener?
    var images: CombImageNectar?

    private let pick = UIStackView()
    private let searchPane = UIStackView()
    private let scanPane = UIStackView()
    private let detailPane = UIStackView()
    private let assignPane = UIStackView()
    private let queryField = HiveTextField()
    private let results = UIStackView()
    private let searchStatus = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let emptySearch = CombEmptyView()
    private let previewHost = UIView()
    private let overlay = UIImageView(image: UIImage(named: "mhv_ScanOverlay"))
    private let scanStatus = UILabel()
    private let manualField = HiveTextField()
    private let samples = UIStackView()
    private let settingsButton = HiveHitButton(type: .system)
    private let backdrop = UIImageView(image: UIImage(named: "mhv_CardBackdrop"))
    private let thumb = UIImageView()
    private let nameLabel = UILabel()
    private let brandLabel = UILabel()
    private let energyLabel = UILabel()
    private let proteinLabel = UILabel()
    private let carbsLabel = UILabel()
    private let fatLabel = UILabel()
    private let gramsField = HiveTextField()
    private let liveTotals = UILabel()
    private let missingBanner = UILabel()
    private let wishButton = HiveHitButton(type: .system)
    private let assignButton = HiveHitButton(type: .system)
    private let success = UIImageView(image: UIImage(named: "mhv_SuccessMark"))
    private let slotStack = UIStackView()
    private let eatenSwitch = UISwitch()
    private let datePicker = UIDatePicker()
    private let confirm = HiveHitButton(type: .system)
    private let catcher = CombVisionCatcher()
    private let observerBag = HiveObserverBag()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var products: [CombProduct] = []
    private var current: CombProduct?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        spinner.hidesWhenStopped = true
        spinner.color = HivePalette.ink
        searchStatus.font = HiveType.font(.caption)
        searchStatus.textColor = HivePalette.muted
        searchStatus.numberOfLines = 0
        searchStatus.adjustsFontForContentSizeCategory = true
        queryField.placeholder = "Search nectar by name"
        queryField.accessibilityLabel = "Search products"
        queryField.addTarget(self, action: #selector(queryChanged), for: .editingChanged)
        queryField.delegate = self
        emptySearch.render(image: "mhv_EmptySearch", title: HiveVoice.searchEmpty, body: "The local shelf is still open.", action: "Browse hive shelf")
        emptySearch.onAction = { [weak self] in self?.listener?.didRetrySearch() }
        results.axis = .vertical
        results.spacing = HiveLayout.u(1)
        searchPane.axis = .vertical
        searchPane.spacing = HiveLayout.u(1)
        searchPane.addArrangedSubview(queryField)
        searchPane.addArrangedSubview(searchStatus)
        searchPane.addArrangedSubview(spinner)
        searchPane.addArrangedSubview(results)
        searchPane.addArrangedSubview(emptySearch)

        let searchPick = bigButton("Search the combs")
        searchPick.addTarget(self, action: #selector(chooseSearch), for: .touchUpInside)
        let scanPick = bigButton("Scan a comb")
        scanPick.addTarget(self, action: #selector(chooseScan), for: .touchUpInside)
        pick.axis = .vertical
        pick.spacing = HiveLayout.u(1)
        pick.addArrangedSubview(searchPick)
        pick.addArrangedSubview(scanPick)

        previewHost.backgroundColor = HivePalette.surface
        previewHost.translatesAutoresizingMaskIntoConstraints = false
        previewHost.heightAnchor.constraint(equalToConstant: 220).isActive = true
        overlay.contentMode = .scaleAspectFit
        overlay.isAccessibilityElement = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        previewHost.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: previewHost.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: previewHost.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: previewHost.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: previewHost.bottomAnchor)
        ])
        scanStatus.font = HiveType.font(.body)
        scanStatus.textColor = HivePalette.ink
        scanStatus.numberOfLines = 0
        scanStatus.adjustsFontForContentSizeCategory = true
        manualField.placeholder = "Type a barcode"
        manualField.keyboardType = .numberPad
        manualField.accessibilityLabel = "Barcode"
        manualField.delegate = self
        let go = bigButton("Look up barcode")
        go.addTarget(self, action: #selector(submitManual), for: .touchUpInside)
        settingsButton.setTitle("Open Settings", for: .normal)
        settingsButton.titleLabel?.font = HiveType.font(.headline, bold: true)
        settingsButton.setTitleColor(HivePalette.ink, for: .normal)
        settingsButton.backgroundColor = HivePalette.accent
        settingsButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        settingsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        settingsButton.accessibilityLabel = "Open Settings"
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        samples.axis = .vertical
        samples.spacing = HiveLayout.u(1)
        scanPane.axis = .vertical
        scanPane.spacing = HiveLayout.u(1)
        scanPane.addArrangedSubview(previewHost)
        scanPane.addArrangedSubview(scanStatus)
        scanPane.addArrangedSubview(settingsButton)
        scanPane.addArrangedSubview(manualField)
        scanPane.addArrangedSubview(go)
        scanPane.addArrangedSubview(samples)

        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        backdrop.isAccessibilityElement = false
        backdrop.heightAnchor.constraint(equalToConstant: 96).isActive = true
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.isAccessibilityElement = false
        thumb.widthAnchor.constraint(equalToConstant: 72).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 72).isActive = true
        nameLabel.font = HiveType.font(.title, bold: true)
        nameLabel.textColor = HivePalette.ink
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.adjustsFontForContentSizeCategory = true
        brandLabel.font = HiveType.font(.caption)
        brandLabel.textColor = HivePalette.muted
        brandLabel.adjustsFontForContentSizeCategory = true
        for label in [energyLabel, proteinLabel, carbsLabel, fatLabel, liveTotals, missingBanner] {
            label.font = HiveType.font(.body, tabular: label === liveTotals || label === energyLabel)
            label.textColor = HivePalette.ink
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
        }
        missingBanner.textColor = HivePalette.muted
        gramsField.keyboardType = .decimalPad
        gramsField.placeholder = "Grams"
        gramsField.accessibilityLabel = "Grams"
        gramsField.addTarget(self, action: #selector(gramsChanged), for: .editingChanged)
        gramsField.delegate = self
        wishButton.addTarget(self, action: #selector(wishTapped), for: .touchUpInside)
        assignButton.addTarget(self, action: #selector(assignTapped), for: .touchUpInside)
        wishButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        assignButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        success.isHidden = true
        success.isAccessibilityElement = false
        success.heightAnchor.constraint(equalToConstant: 64).isActive = true
        detailPane.axis = .vertical
        detailPane.spacing = HiveLayout.u(1)
        let header = UIStackView(arrangedSubviews: [thumb, nameLabel])
        header.axis = .horizontal
        header.spacing = HiveLayout.u(1)
        header.alignment = .center
        detailPane.addArrangedSubview(backdrop)
        detailPane.addArrangedSubview(header)
        detailPane.addArrangedSubview(brandLabel)
        detailPane.addArrangedSubview(missingBanner)
        detailPane.addArrangedSubview(energyLabel)
        detailPane.addArrangedSubview(proteinLabel)
        detailPane.addArrangedSubview(carbsLabel)
        detailPane.addArrangedSubview(fatLabel)
        detailPane.addArrangedSubview(gramsField)
        detailPane.addArrangedSubview(liveTotals)
        detailPane.addArrangedSubview(wishButton)
        detailPane.addArrangedSubview(assignButton)
        detailPane.addArrangedSubview(success)

        slotStack.axis = .vertical
        slotStack.spacing = HiveLayout.u(1)
        eatenSwitch.onTintColor = HivePalette.accent
        eatenSwitch.addTarget(self, action: #selector(eatenChanged), for: .valueChanged)
        eatenSwitch.accessibilityLabel = "Logged as eaten today"
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.minimumDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        datePicker.maximumDate = Calendar.current.date(byAdding: .day, value: HiveDefaults.planHorizonDays, to: Date())
        datePicker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
        datePicker.accessibilityLabel = "Future forage day"
        confirm.setTitle("Write to the comb", for: .normal)
        confirm.titleLabel?.font = HiveType.font(.headline, bold: true)
        confirm.setTitleColor(HivePalette.ink, for: .normal)
        confirm.backgroundColor = HivePalette.accent
        confirm.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        confirm.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        confirm.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        let eatenRow = UIStackView(arrangedSubviews: [label("Eaten today"), eatenSwitch])
        eatenRow.axis = .horizontal
        eatenRow.alignment = .center
        assignPane.axis = .vertical
        assignPane.spacing = HiveLayout.u(1)
        assignPane.addArrangedSubview(slotStack)
        assignPane.addArrangedSubview(eatenRow)
        assignPane.addArrangedSubview(datePicker)
        assignPane.addArrangedSubview(confirm)

        let root = UIStackView(arrangedSubviews: [pick, searchPane, scanPane, detailPane, assignPane])
        root.axis = .vertical
        root.spacing = HiveLayout.u(2)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: HiveLayout.u(1)),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HiveLayout.u(2)),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -HiveLayout.u(2)),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -HiveLayout.u(2))
        ])

        catcher.onPreview = { [weak self] layer in
            self?.attachPreview(layer)
        }
        catcher.onCode = { [weak self] payload in
            self?.listener?.didSubmitBarcode(payload)
        }
        catcher.prepare()
        observerBag.add(
            NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.catcher.stop() }
            }
        )
        buildSamples()
        styleButtons()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        catcher.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewHost.bounds
    }

    func render(_ model: ForagerViewModel) {
        pick.isHidden = model.pane != .pick
        searchPane.isHidden = model.pane != .search
        scanPane.isHidden = model.pane != .scan
        detailPane.isHidden = model.pane != .detail
        assignPane.isHidden = model.pane != .assign
        if model.pane == .scan {
            configureScan(model.scanState, message: model.barcodeMessage)
        } else {
            catcher.stop()
        }
        if queryField.text != model.query, model.pane == .search {
            queryField.text = model.query
        }
        searchStatus.text = model.usedShelfFallback ? "Showing the local hive shelf." : HiveVoice.searchIdle
        emptySearch.isHidden = model.searchState != .empty && model.searchState != .transport
        if model.searchState == .transport {
            emptySearch.render(image: "mhv_EmptySearch", title: HiveVoice.searchError, body: "Retry, or browse the shelf.", action: "Retry search")
        } else if model.searchState == .empty {
            emptySearch.render(image: "mhv_EmptySearch", title: HiveVoice.searchEmpty, body: "The local shelf is still open.", action: "Browse hive shelf")
        }
        if model.searchState == .loading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        if model.pane == .search {
            renderResults(model.results)
        }
        if let product = model.product {
            current = product
            renderDetail(model, product: product)
        }
        if model.pane == .assign {
            renderAssign(model)
        }
        if model.commitInFlight == false, model.pane != .assign {
            success.isHidden = true
        }
    }

    private func renderResults(_ products: [CombProduct]) {
        self.products = products
        results.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var rows: [UIView] = []
        for product in products {
            let imageView = UIImageView(image: CombThumb.bundled(for: product))
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isAccessibilityElement = false
            imageView.widthAnchor.constraint(equalToConstant: 48).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 48).isActive = true
            loadRemote(product, into: imageView)
            let name = UILabel()
            name.text = product.name
            name.font = HiveType.font(.body)
            name.textColor = HivePalette.ink
            name.lineBreakMode = .byTruncatingTail
            name.adjustsFontForContentSizeCategory = true
            let meta = UILabel()
            let kcal = product.kcal100.map { "\(HiveFormat.kcal($0)) kcal/100 g" } ?? "unknown energy"
            meta.text = [product.brand, kcal].compactMap { $0 }.joined(separator: " · ")
            meta.font = HiveType.font(.caption, tabular: true)
            meta.textColor = HivePalette.muted
            meta.lineBreakMode = .byTruncatingTail
            meta.adjustsFontForContentSizeCategory = true
            let text = UIStackView(arrangedSubviews: [name, meta])
            text.axis = .vertical
            let row = HivePayloadControl()
            row.payload = product.barcode
            row.accessibilityLabel = product.name
            row.accessibilityValue = meta.text
            row.accessibilityTraits = .button
            row.addTarget(self, action: #selector(selectResult(_:)), for: .touchUpInside)
            let inner = UIStackView(arrangedSubviews: [imageView, text])
            inner.axis = .horizontal
            inner.spacing = HiveLayout.u(1)
            inner.alignment = .center
            inner.isUserInteractionEnabled = false
            inner.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(inner)
            NSLayoutConstraint.activate([
                inner.topAnchor.constraint(equalTo: row.topAnchor, constant: HiveLayout.u(1)),
                inner.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                inner.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                inner.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -HiveLayout.u(1)),
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap)
            ])
            results.addArrangedSubview(row)
            rows.append(row)
        }
        HiveStagger.appear(rows)
    }

    private func renderDetail(_ model: ForagerViewModel, product: CombProduct) {
        nameLabel.text = product.name
        brandLabel.text = product.brand
        thumb.image = CombThumb.bundled(for: product)
        loadRemote(product, into: thumb)
        energyLabel.text = "Energy / 100 g: \(HiveFormat.macro(product.kcal100)) kcal"
        proteinLabel.text = "Protein / 100 g: \(HiveFormat.macro(product.protein100)) g"
        carbsLabel.text = "Carbs / 100 g: \(HiveFormat.macro(product.carbs100)) g"
        fatLabel.text = "Fat / 100 g: \(HiveFormat.macro(product.fat100)) g"
        missingBanner.isHidden = !model.missingEnergy
        missingBanner.text = HiveVoice.missingEnergy
        if gramsField.text != model.gramsText {
            gramsField.text = model.gramsText
        }
        let grams = HiveFormat.parseDecimal(model.gramsText) ?? 0
        let kcal = CombPortion.scaled(per100: product.kcal100, grams: grams)
        let protein = CombPortion.scaled(per100: product.protein100, grams: grams)
        let carbs = CombPortion.scaled(per100: product.carbs100, grams: grams)
        let fat = CombPortion.scaled(per100: product.fat100, grams: grams)
        liveTotals.text = "This portion: \(HiveFormat.macro(kcal)) kcal · P \(HiveFormat.compactMacro(protein)) · C \(HiveFormat.compactMacro(carbs)) · F \(HiveFormat.compactMacro(fat))"
        wishButton.setTitle(model.wishSaved ? "Already in the wish comb" : "Save to wish comb", for: .normal)
        wishButton.isEnabled = !model.wishSaved
        wishButton.alpha = model.wishSaved ? 0.5 : 1
        wishButton.accessibilityLabel = wishButton.currentTitle
        assignButton.setTitle("Assign forage", for: .normal)
        assignButton.isEnabled = model.commitEnabled
        assignButton.accessibilityLabel = "Assign forage"
        style(wishButton, filled: false)
        style(assignButton, filled: true)
    }

    private func renderAssign(_ model: ForagerViewModel) {
        slotStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for slot in ForageSlot.allCases {
            let button = HiveHitButton(type: .system)
            button.setTitle(slot.title, for: .normal)
            button.setImage(UIImage(named: slot.assetName), for: .normal)
            button.tintColor = HivePalette.ink
            button.titleLabel?.font = HiveType.font(.headline)
            button.setTitleColor(HivePalette.ink, for: .normal)
            button.backgroundColor = slot == model.slot ? HivePalette.accent : HivePalette.surface
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
            button.accessibilityLabel = slot.title
            button.tag = slot.rawValue
            let future = !model.eaten
            button.isEnabled = !(future && slot == .nectarDrop)
            button.alpha = button.isEnabled ? 1 : 0.4
            button.addTarget(self, action: #selector(pickSlot(_:)), for: .touchUpInside)
            slotStack.addArrangedSubview(button)
        }
        eatenSwitch.isOn = model.eaten
        datePicker.isHidden = model.eaten
        confirm.isEnabled = model.commitEnabled
        confirm.alpha = model.commitEnabled ? 1 : 0.5
        confirm.setTitle(model.commitInFlight ? "Writing…" : "Write to the comb", for: .normal)
    }

    private func configureScan(_ state: ForagerScanState, message: String?) {
        settingsButton.isHidden = true
        previewHost.isHidden = true
        samples.isHidden = true
        switch state {
        case .ready:
            previewHost.isHidden = false
            scanStatus.text = message ?? "Hold a barcode or QR inside the comb."
            requestCameraIfNeeded()
            catcher.start()
        case .simulator, .missing:
            samples.isHidden = false
            scanStatus.text = message ?? HiveVoice.cameraMissing
        case .denied:
            settingsButton.isHidden = false
            scanStatus.text = HiveVoice.cameraDenied
        case .restricted:
            settingsButton.isHidden = false
            scanStatus.text = "Camera is restricted on this device. Use a typed barcode instead."
        }
    }

    private func requestCameraIfNeeded() {
        switch CombVisionCatcher.authorization {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.catcher.start()
                    } else {
                        self?.listener?.didChooseScan()
                    }
                }
            }
        case .authorized:
            catcher.start()
        default:
            break
        }
    }

    private func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer?.removeFromSuperlayer()
        previewLayer = layer
        layer.frame = previewHost.bounds
        previewHost.layer.insertSublayer(layer, at: 0)
    }

    private func buildSamples() {
        samples.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for product in CombShelf.comb {
            let button = HiveHitButton(type: .system)
            button.setTitle("\(product.name) · \(product.barcode)", for: .normal)
            button.titleLabel?.font = HiveType.font(.caption)
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.setTitleColor(HivePalette.ink, for: .normal)
            button.backgroundColor = HivePalette.surface
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
            button.accessibilityLabel = "Sample barcode \(product.name)"
            button.accessibilityIdentifier = product.barcode
            button.addAction(UIAction { [weak self] _ in
                self?.listener?.didSubmitBarcode(product.barcode)
            }, for: .touchUpInside)
            samples.addArrangedSubview(button)
        }
    }

    private func loadRemote(_ product: CombProduct, into imageView: UIImageView) {
        guard let images, let url = product.imageURL else { return }
        Task {
            if let data = await images.data(for: url), let image = UIImage(data: data) {
                imageView.image = image
            }
        }
    }

    private func bigButton(_ title: String) -> UIButton {
        let button = HiveHitButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = title
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        style(button, filled: true)
        return button
    }

    private func styleButtons() {
        wishButton.setTitleColor(HivePalette.ink, for: .normal)
        assignButton.setTitleColor(HivePalette.ink, for: .normal)
        wishButton.titleLabel?.font = HiveType.font(.headline)
        assignButton.titleLabel?.font = HiveType.font(.headline, bold: true)
    }

    private func style(_ button: UIButton, filled: Bool) {
        button.titleLabel?.font = HiveType.font(.headline, bold: filled)
        button.setTitleColor(HivePalette.ink, for: .normal)
        button.backgroundColor = filled ? HivePalette.accent : HivePalette.surface
        button.layer.borderWidth = filled ? 0 : 1
        button.layer.borderColor = HivePalette.muted.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = HiveType.font(.body)
        label.textColor = HivePalette.ink
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    @objc private func chooseSearch() { listener?.didChooseSearch() }
    @objc private func chooseScan() { listener?.didChooseScan() }
    @objc private func queryChanged() { listener?.didChangeQuery(queryField.text ?? "") }
    @objc private func submitManual() { listener?.didSubmitBarcode(manualField.text ?? "") }
    @objc private func openSettings() { listener?.didOpenSettings() }
    @objc private func gramsChanged() { listener?.didChangeGrams(gramsField.text ?? "") }
    @objc private func wishTapped() { listener?.didRequestWish() }
    @objc private func assignTapped() { listener?.didRequestAssign() }
    @objc private func eatenChanged() { listener?.didPickEaten(eatenSwitch.isOn) }
    @objc private func confirmTapped() {
        success.isHidden = false
        listener?.didConfirmAssign()
    }
    @objc private func pickSlot(_ sender: UIButton) {
        if let slot = ForageSlot(rawValue: sender.tag) {
            listener?.didPickSlot(slot)
        }
    }
    @objc private func dateChanged() {
        listener?.didPickFutureDay(HiveDayKey.make(datePicker.date))
    }
    @objc private func selectResult(_ sender: HivePayloadControl) {
        guard let product = products.first(where: { $0.barcode == sender.payload }) else { return }
        listener?.didSelectProduct(product)
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField === queryField { return true }
        if string.isEmpty { return true }
        if textField === manualField {
            return string.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
        }
        let separator = Locale.current.decimalSeparator ?? "."
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: separator))
        if string.rangeOfCharacter(from: allowed.inverted) != nil { return false }
        let current = textField.text ?? ""
        if string.contains(separator), current.contains(separator) { return false }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
