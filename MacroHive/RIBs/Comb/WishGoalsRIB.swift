import HiveRIBs
import UIKit

@MainActor
protocol WishCombListener: AnyObject {
    func wishDidRequestAssign(_ product: CombProduct)
    func wishDidRequestForage()
}

@MainActor
protocol WishCombPresentableListener: AnyObject {
    func didPromote(_ product: CombProduct)
    func didDelete(barcode: String)
    func didRequestForage()
}

/// Wish comb: barcode-unique; duplicate add updates the existing row.
@MainActor
final class WishCombInteractor: CombInteractor, WishCombPresentableListener {
    weak var listener: WishCombListener?
    weak var presenter: WishCombPresentable?
    private let store: CombHiveStore
    private var loadTask: Task<Void, Never>?
    private var profileID: Int64 = 0

    init(store: CombHiveStore) { self.store = store }

    override func didBecomeActive() { refresh() }
    override func willResignActive() { loadTask?.cancel() }

    func didPromote(_ product: CombProduct) {
        guard isCombActive else { return }
        listener?.wishDidRequestAssign(product)
    }

    func didDelete(barcode: String) {
        guard isCombActive else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            try? await self.store.deleteWish(profileID: self.profileID, barcode: barcode)
            self.refresh()
        }
    }

    func didRequestForage() { listener?.wishDidRequestForage() }

    private func refresh() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.profileID = try await self.store.activeMemberID()
                let rows = try await self.store.wishes(profileID: self.profileID)
                self.presenter?.render(rows)
            } catch {
                self.presenter?.render([])
            }
        }
    }
}

@MainActor
protocol WishCombPresentable: AnyObject {
    func render(_ items: [WishNectar])
}

@MainActor
final class WishCombBuilder: CombBuildable {
    private let dependency: HiveDependency
    init(dependency: HiveDependency) { self.dependency = dependency }
    func build(listener: WishCombListener) -> WishCombRouter {
        let view = WishCombViewController()
        let interactor = WishCombInteractor(store: dependency.store)
        interactor.listener = listener
        interactor.presenter = view
        view.listener = interactor
        return WishCombRouter(interactor: interactor, view: view)
    }
}

@MainActor
final class WishCombRouter: CombRouter<WishCombInteractor, WishCombViewController> {}

@MainActor
final class WishCombViewController: UIViewController, WishCombPresentable {
    weak var listener: WishCombPresentableListener?
    private let list = UIStackView()
    private let empty = CombEmptyView()
    private var items: [WishNectar] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        list.axis = .vertical
        list.spacing = HiveLayout.u(1)
        empty.render(image: "mhv_EmptyWish", title: "Wish comb is empty", body: "Save products you intend to buy.", action: "Forage a product")
        empty.onAction = { [weak self] in self?.listener?.didRequestForage() }
        let stack = UIStackView(arrangedSubviews: [list, empty])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: HiveLayout.u(1)),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HiveLayout.u(2)),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -HiveLayout.u(2)),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -HiveLayout.u(2))
        ])
    }

    func render(_ items: [WishNectar]) {
        self.items = items
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        empty.isHidden = !items.isEmpty
        list.isHidden = items.isEmpty
        var rows: [UIView] = []
        for item in items {
            let thumb = UIImageView(image: CombThumb.bundled(for: item.product))
            thumb.contentMode = .scaleAspectFill
            thumb.clipsToBounds = true
            thumb.isAccessibilityElement = false
            thumb.widthAnchor.constraint(equalToConstant: 48).isActive = true
            thumb.heightAnchor.constraint(equalToConstant: 48).isActive = true
            let name = UILabel()
            name.text = item.product.name
            name.font = HiveType.font(.body)
            name.textColor = HivePalette.ink
            name.lineBreakMode = .byTruncatingTail
            name.adjustsFontForContentSizeCategory = true
            let kcal = UILabel()
            kcal.text = item.product.kcal100.map { "\(HiveFormat.kcal($0)) kcal/100 g" } ?? "unknown energy"
            kcal.font = HiveType.font(.caption, tabular: true)
            kcal.textColor = HivePalette.muted
            kcal.adjustsFontForContentSizeCategory = true
            let text = UIStackView(arrangedSubviews: [name, kcal])
            text.axis = .vertical
            let assign = HivePayloadButton(type: .system)
            assign.setTitle("Assign", for: .normal)
            assign.payload = item.barcode
            assign.accessibilityLabel = "Assign \(item.product.name)"
            assign.titleLabel?.font = HiveType.font(.caption, bold: true)
            assign.setTitleColor(HivePalette.ink, for: .normal)
            assign.backgroundColor = HivePalette.accent
            assign.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            assign.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
            assign.addTarget(self, action: #selector(promote(_:)), for: .touchUpInside)
            let remove = HivePayloadButton(type: .system)
            remove.setTitle("Remove", for: .normal)
            remove.payload = item.barcode
            remove.accessibilityLabel = "Remove \(item.product.name) from wish comb"
            remove.titleLabel?.font = HiveType.font(.caption)
            remove.setTitleColor(HivePalette.ink, for: .normal)
            remove.contentEdgeInsets = UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
            remove.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
            remove.addTarget(self, action: #selector(removeItem(_:)), for: .touchUpInside)
            let row = UIStackView(arrangedSubviews: [thumb, text, assign, remove])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = HiveLayout.u(1)
            list.addArrangedSubview(row)
            rows.append(row)
        }
        HiveStagger.appear(rows)
    }

    @objc private func promote(_ sender: HivePayloadButton) {
        guard let item = items.first(where: { $0.barcode == sender.payload }) else { return }
        listener?.didPromote(item.product)
    }

    @objc private func removeItem(_ sender: HivePayloadButton) {
        guard let item = items.first(where: { $0.barcode == sender.payload }) else { return }
        let alert = UIAlertController(title: "Remove from wish comb?", message: item.product.name, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.listener?.didDelete(barcode: item.barcode)
        })
        present(alert, animated: !HiveMotion.reduce)
    }
}

@MainActor
protocol ColonyGoalsListener: AnyObject {
    func goalsDidRerunOnboarding()
}

@MainActor
protocol ColonyGoalsPresentableListener: AnyObject {
    func didSave(kcal: Double, protein: Double?, carbs: Double?, fat: Double?)
    func didRerunOnboarding()
    func didReset()
    func didOpenContact()
}

/// Goals interactor: target edits, onboarding re-run, full reset.
@MainActor
final class ColonyGoalsInteractor: CombInteractor, ColonyGoalsPresentableListener {
    weak var listener: ColonyGoalsListener?
    weak var presenter: ColonyGoalsPresentable?
    private let store: CombHiveStore
    private var loadTask: Task<Void, Never>?
    private var profileID: Int64 = 0

    init(store: CombHiveStore) { self.store = store }

    override func didBecomeActive() { refresh() }
    override func willResignActive() { loadTask?.cancel() }

    func didSave(kcal: Double, protein: Double?, carbs: Double?, fat: Double?) {
        guard isCombActive else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.store.saveTargets(
                    HiveTargets(profileID: self.profileID, kcal: max(kcal, 1), protein: protein, carbs: carbs, fat: fat)
                )
                HiveHaptics.commit()
                self.presenter?.showSaved()
            } catch {
                self.presenter?.showError("Targets could not be stored.")
            }
        }
    }

    func didRerunOnboarding() {
        guard isCombActive else { return }
        listener?.goalsDidRerunOnboarding()
    }

    func didReset() {
        guard isCombActive else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.store.resetAllData()
                HiveHaptics.commit()
                self.refresh()
            } catch {
                self.presenter?.showError("Reset failed.")
            }
        }
    }

    func didOpenContact() {
        if let host = presenter as? UIViewController {
            WebContentHost.presentContact(from: host)
        }
    }

    private func refresh() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.profileID = try await self.store.activeMemberID()
                let targets = try await self.store.targets(profileID: self.profileID)
                self.presenter?.render(targets)
            } catch {
                self.presenter?.showError("Targets could not be read.")
            }
        }
    }
}

@MainActor
protocol ColonyGoalsPresentable: AnyObject {
    func render(_ targets: HiveTargets)
    func showSaved()
    func showError(_ message: String)
}

@MainActor
final class ColonyGoalsBuilder: CombBuildable {
    private let dependency: HiveDependency
    init(dependency: HiveDependency) { self.dependency = dependency }
    func build(listener: ColonyGoalsListener) -> ColonyGoalsRouter {
        let view = ColonyGoalsViewController()
        let interactor = ColonyGoalsInteractor(store: dependency.store)
        interactor.listener = listener
        interactor.presenter = view
        view.listener = interactor
        return ColonyGoalsRouter(interactor: interactor, view: view)
    }
}

@MainActor
final class ColonyGoalsRouter: CombRouter<ColonyGoalsInteractor, ColonyGoalsViewController> {}

@MainActor
final class ColonyGoalsViewController: UIViewController, ColonyGoalsPresentable, UITextFieldDelegate {
    weak var listener: ColonyGoalsPresentableListener?
    private let kcalField = HiveTextField()
    private let proteinField = HiveTextField()
    private let carbsField = HiveTextField()
    private let fatField = HiveTextField()
    private let status = UILabel()
    private let save = HiveHitButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        func labeled(_ title: String, _ field: HiveTextField) -> UIStackView {
            let label = UILabel()
            label.text = title
            label.font = HiveType.font(.caption)
            label.textColor = HivePalette.muted
            label.adjustsFontForContentSizeCategory = true
            field.keyboardType = .decimalPad
            field.delegate = self
            field.accessibilityLabel = title
            let stack = UIStackView(arrangedSubviews: [label, field])
            stack.axis = .vertical
            stack.spacing = HiveLayout.u(1)
            return stack
        }
        save.setTitle("Save targets", for: .normal)
        save.titleLabel?.font = HiveType.font(.headline, bold: true)
        save.setTitleColor(HivePalette.ink, for: .normal)
        save.backgroundColor = HivePalette.accent
        save.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        save.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        save.accessibilityLabel = "Save targets"
        save.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        let onboard = actionButton("Re-run onboarding")
        onboard.addTarget(self, action: #selector(onboardTapped), for: .touchUpInside)
        let reset = actionButton("Reset all hive data")
        reset.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        let contact = actionButton("Contact MacroHive")
        contact.addTarget(self, action: #selector(contactTapped), for: .touchUpInside)
        status.font = HiveType.font(.caption)
        status.textColor = HivePalette.muted
        status.numberOfLines = 0
        status.adjustsFontForContentSizeCategory = true
        let credit = UILabel()
        credit.text = HiveVoice.notMedical
        credit.font = HiveType.font(.caption)
        credit.textColor = HivePalette.muted
        credit.numberOfLines = 0
        credit.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [
            labeled("Energy, kcal", kcalField),
            labeled("Protein, g", proteinField),
            labeled("Carbs, g", carbsField),
            labeled("Fat, g", fatField),
            save, status, onboard, reset, contact, credit
        ])
        stack.axis = .vertical
        stack.spacing = HiveLayout.u(2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: HiveLayout.u(1)),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HiveLayout.u(2)),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -HiveLayout.u(2)),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -HiveLayout.u(2))
        ])
    }

    func render(_ targets: HiveTargets) {
        kcalField.text = HiveFormat.kcal(targets.kcal)
        proteinField.text = targets.protein.map(HiveFormat.macro) ?? ""
        carbsField.text = targets.carbs.map(HiveFormat.macro) ?? ""
        fatField.text = targets.fat.map(HiveFormat.macro) ?? ""
    }

    func showSaved() { status.text = "Targets written to the comb." }
    func showError(_ message: String) { status.text = message }

    private func actionButton(_ title: String) -> UIButton {
        let button = HiveHitButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = HiveType.font(.body)
        button.setTitleColor(HivePalette.ink, for: .normal)
        button.backgroundColor = HivePalette.surface
        button.layer.borderWidth = 1
        button.layer.borderColor = HivePalette.muted.cgColor
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        button.accessibilityLabel = title
        return button
    }

    @objc private func saveTapped() {
        let kcal = HiveFormat.parseDecimal(kcalField.text ?? "") ?? 0
        guard kcal > 0 else {
            status.text = "Energy must be greater than zero."
            return
        }
        listener?.didSave(
            kcal: kcal,
            protein: HiveFormat.parseDecimal(proteinField.text ?? ""),
            carbs: HiveFormat.parseDecimal(carbsField.text ?? ""),
            fat: HiveFormat.parseDecimal(fatField.text ?? "")
        )
    }

    @objc private func onboardTapped() { listener?.didRerunOnboarding() }

    @objc private func resetTapped() {
        let alert = UIAlertController(
            title: "Reset all hive data?",
            message: "Members, logs, wishes and targets are cleared. The local shelf remains.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            self?.listener?.didReset()
        })
        present(alert, animated: !HiveMotion.reduce)
    }

    @objc private func contactTapped() { listener?.didOpenContact() }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty { return true }
        let separator = Locale.current.decimalSeparator ?? "."
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: separator))
        return string.rangeOfCharacter(from: allowed.inverted) == nil
    }
}
