import HiveRIBs
import UIKit

@MainActor
protocol HarvestLogListener: AnyObject {
    func harvestDidRequestForage()
}

@MainActor
protocol HarvestLogPresentableListener: AnyObject {
    func didChangeDay(_ delta: Int)
    func didDelete(id: Int64)
    func didRequestForage()
}

/// Harvest log interactor. Deletes are confirmed in the view, then durable here.
@MainActor
final class HarvestLogInteractor: CombInteractor, HarvestLogPresentableListener {
    weak var listener: HarvestLogListener?
    weak var presenter: HarvestLogPresentable?
    private let store: CombHiveStore
    private var dayKey = HiveDayKey.make(Date())
    private var loadTask: Task<Void, Never>?
    private var profileID: Int64 = 0

    init(store: CombHiveStore) {
        self.store = store
    }

    override func didBecomeActive() {
        dayKey = HiveDayKey.make(Date())
        refresh()
    }

    override func willResignActive() { loadTask?.cancel() }

    func didChangeDay(_ delta: Int) {
        dayKey = HiveDayKey.adding(days: delta, to: dayKey)
        refresh()
    }

    func didDelete(id: Int64) {
        guard isCombActive else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            try? await self.store.deleteEntry(id: id, profileID: self.profileID)
            self.refresh()
        }
    }

    func didRequestForage() { listener?.harvestDidRequestForage() }

    private func refresh() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.profileID = try await self.store.activeMemberID()
                let rows = try await self.store.entries(profileID: self.profileID, dayKey: self.dayKey, eaten: true)
                self.presenter?.render(dayKey: self.dayKey, entries: rows)
            } catch {
                self.presenter?.render(dayKey: self.dayKey, entries: [])
            }
        }
    }
}

@MainActor
protocol HarvestLogPresentable: AnyObject {
    func render(dayKey: Int, entries: [NectarEntry])
}

@MainActor
final class HarvestLogBuilder: CombBuildable {
    private let dependency: HiveDependency
    init(dependency: HiveDependency) { self.dependency = dependency }
    func build(listener: HarvestLogListener) -> HarvestLogRouter {
        let view = HarvestLogViewController()
        let interactor = HarvestLogInteractor(store: dependency.store)
        interactor.listener = listener
        interactor.presenter = view
        view.listener = interactor
        return HarvestLogRouter(interactor: interactor, view: view)
    }
}

@MainActor
final class HarvestLogRouter: CombRouter<HarvestLogInteractor, HarvestLogViewController> {}

@MainActor
final class HarvestLogViewController: UIViewController, HarvestLogPresentable {
    weak var listener: HarvestLogPresentableListener?
    private let dayLabel = UILabel()
    private let list = UIStackView()
    private let empty = CombEmptyView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        dayLabel.font = HiveType.font(.headline, bold: true, tabular: true)
        dayLabel.textColor = HivePalette.ink
        dayLabel.textAlignment = .center
        dayLabel.adjustsFontForContentSizeCategory = true
        let prev = navButton("Previous day", symbol: "chevron.left")
        prev.addTarget(self, action: #selector(prevDay), for: .touchUpInside)
        let next = navButton("Next day", symbol: "chevron.right")
        next.addTarget(self, action: #selector(nextDay), for: .touchUpInside)
        let header = UIStackView(arrangedSubviews: [prev, dayLabel, next])
        header.axis = .horizontal
        header.alignment = .center
        list.axis = .vertical
        list.spacing = HiveLayout.u(1)
        empty.render(image: "mhv_EmptyLog", title: "No harvest yet", body: "Eaten combs for this day land here.", action: "Forage now")
        empty.onAction = { [weak self] in self?.listener?.didRequestForage() }
        let stack = UIStackView(arrangedSubviews: [header, list, empty])
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

    func render(dayKey: Int, entries: [NectarEntry]) {
        dayLabel.text = String(dayKey)
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        empty.isHidden = !entries.isEmpty
        list.isHidden = entries.isEmpty
        for slot in ForageSlot.allCases {
            let group = entries.filter { $0.slot == slot }
            guard !group.isEmpty else { continue }
            let header = UILabel()
            header.text = slot.title
            header.font = HiveType.font(.headline, bold: true)
            header.textColor = HivePalette.ink
            header.adjustsFontForContentSizeCategory = true
            list.addArrangedSubview(header)
            let subtotal = group.reduce(0.0) { $0 + (CombPortion.scaled(per100: $1.product.kcal100, grams: $1.grams) ?? 0) }
            let sub = UILabel()
            sub.text = "Subtotal \(HiveFormat.kcal(subtotal)) kcal"
            sub.font = HiveType.font(.caption, tabular: true)
            sub.textColor = HivePalette.muted
            sub.adjustsFontForContentSizeCategory = true
            list.addArrangedSubview(sub)
            var rendered: [UIView] = []
            for entry in group {
                let view = row(entry)
                list.addArrangedSubview(view)
                rendered.append(view)
                let age = Date().timeIntervalSince1970 - TimeInterval(entry.createdAt)
                if age >= 0, age < 6 {
                    HiveStagger.highlight(view)
                }
            }
            HiveStagger.appear(rendered)
        }
    }

    private func row(_ entry: NectarEntry) -> UIView {
        let name = UILabel()
        name.text = entry.product.name
        name.font = HiveType.font(.body)
        name.textColor = HivePalette.ink
        name.lineBreakMode = .byTruncatingTail
        name.adjustsFontForContentSizeCategory = true
        let detail = UILabel()
        let kcal = CombPortion.scaled(per100: entry.product.kcal100, grams: entry.grams)
        detail.text = "\(HiveFormat.grams(entry.grams)) g · \(kcal.map(HiveFormat.kcal) ?? "unknown") kcal"
        detail.font = HiveType.font(.caption, tabular: true)
        detail.textColor = HivePalette.muted
        detail.adjustsFontForContentSizeCategory = true
        let text = UIStackView(arrangedSubviews: [name, detail])
        text.axis = .vertical
        let delete = HivePayloadButton(type: .system)
        delete.setTitle("Remove", for: .normal)
        delete.titleLabel?.font = HiveType.font(.caption, bold: true)
        delete.setTitleColor(HivePalette.ink, for: .normal)
        delete.accessibilityLabel = "Remove \(entry.product.name)"
        delete.payload = String(entry.id)
        delete.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        delete.addTarget(self, action: #selector(confirmDelete(_:)), for: .touchUpInside)
        let row = UIStackView(arrangedSubviews: [text, delete])
        row.axis = .horizontal
        row.alignment = .center
        row.backgroundColor = HivePalette.surface
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: HiveLayout.u(1),
            left: HiveLayout.u(1),
            bottom: HiveLayout.u(1),
            right: HiveLayout.u(1)
        )
        return row
    }

    private func navButton(_ label: String, symbol: String) -> UIButton {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: symbol)
        button.setImage(image, for: .normal)
        button.tintColor = HivePalette.ink
        button.accessibilityLabel = label
        button.widthAnchor.constraint(equalToConstant: HiveLayout.tap).isActive = true
        button.heightAnchor.constraint(equalToConstant: HiveLayout.tap).isActive = true
        return button
    }

    @objc private func prevDay() { listener?.didChangeDay(-1) }
    @objc private func nextDay() { listener?.didChangeDay(1) }

    @objc private func confirmDelete(_ sender: HivePayloadButton) {
        guard let id = Int64(sender.payload) else { return }
        let alert = UIAlertController(
            title: "Remove this comb?",
            message: "The harvest row is deleted immediately.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.listener?.didDelete(id: id)
        })
        present(alert, animated: !HiveMotion.reduce)
    }
}

@MainActor
protocol HorizonPlanListener: AnyObject {
    func horizonDidRequestForage()
}

@MainActor
protocol HorizonPlanPresentableListener: AnyObject {
    func didConvert(id: Int64)
    func didRequestForage()
}

/// Horizon plan: 14-day window of uneaten entries.
@MainActor
final class HorizonPlanInteractor: CombInteractor, HorizonPlanPresentableListener {
    weak var listener: HorizonPlanListener?
    weak var presenter: HorizonPlanPresentable?
    private let store: CombHiveStore
    private var loadTask: Task<Void, Never>?
    private var profileID: Int64 = 0

    init(store: CombHiveStore) { self.store = store }

    override func didBecomeActive() { refresh() }
    override func willResignActive() { loadTask?.cancel() }

    func didConvert(id: Int64) {
        guard isCombActive else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            let today = HiveDayKey.make(Date())
            try? await self.store.markEaten(id: id, profileID: self.profileID, dayKey: today)
            HiveHaptics.commit()
            self.refresh()
        }
    }

    func didRequestForage() { listener?.horizonDidRequestForage() }

    private func refresh() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.profileID = try await self.store.activeMemberID()
                let today = HiveDayKey.make(Date())
                let end = HiveDayKey.adding(days: HiveDefaults.planHorizonDays, to: today)
                let rows = try await self.store.plannedEntries(profileID: self.profileID, fromDay: today, toDay: end)
                self.presenter?.render(rows)
            } catch {
                self.presenter?.render([])
            }
        }
    }
}

@MainActor
protocol HorizonPlanPresentable: AnyObject {
    func render(_ entries: [NectarEntry])
}

@MainActor
final class HorizonPlanBuilder: CombBuildable {
    private let dependency: HiveDependency
    init(dependency: HiveDependency) { self.dependency = dependency }
    func build(listener: HorizonPlanListener) -> HorizonPlanRouter {
        let view = HorizonPlanViewController()
        let interactor = HorizonPlanInteractor(store: dependency.store)
        interactor.listener = listener
        interactor.presenter = view
        view.listener = interactor
        return HorizonPlanRouter(interactor: interactor, view: view)
    }
}

@MainActor
final class HorizonPlanRouter: CombRouter<HorizonPlanInteractor, HorizonPlanViewController> {}

@MainActor
final class HorizonPlanViewController: UIViewController, HorizonPlanPresentable {
    weak var listener: HorizonPlanPresentableListener?
    private let list = UIStackView()
    private let empty = CombEmptyView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        list.axis = .vertical
        list.spacing = HiveLayout.u(1)
        empty.render(
            image: "mhv_EmptyPlan",
            title: "Horizon is clear",
            body: "Plan up to 14 days ahead. Nectar Drop stays eaten-only.",
            action: "Plan a comb"
        )
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

    func render(_ entries: [NectarEntry]) {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        empty.isHidden = !entries.isEmpty
        list.isHidden = entries.isEmpty
        var lastDay: Int?
        for entry in entries {
            if lastDay != entry.dayKey {
                let header = UILabel()
                header.text = String(entry.dayKey)
                header.font = HiveType.font(.headline, bold: true, tabular: true)
                header.textColor = HivePalette.ink
                header.adjustsFontForContentSizeCategory = true
                list.addArrangedSubview(header)
                lastDay = entry.dayKey
            }
            let name = UILabel()
            name.text = "\(entry.slot.title) · \(entry.product.name)"
            name.font = HiveType.font(.body)
            name.textColor = HivePalette.ink
            name.lineBreakMode = .byTruncatingTail
            name.adjustsFontForContentSizeCategory = true
            let eat = HivePayloadButton(type: .system)
            eat.setTitle("Mark eaten", for: .normal)
            eat.titleLabel?.font = HiveType.font(.caption, bold: true)
            eat.setTitleColor(HivePalette.ink, for: .normal)
            eat.backgroundColor = HivePalette.accent
            eat.payload = String(entry.id)
            eat.accessibilityLabel = "Mark \(entry.product.name) eaten"
            eat.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
            eat.addTarget(self, action: #selector(convert(_:)), for: .touchUpInside)
            let row = UIStackView(arrangedSubviews: [name, eat])
            row.axis = .horizontal
            row.spacing = HiveLayout.u(1)
            list.addArrangedSubview(row)
        }
        HiveStagger.appear(list.arrangedSubviews)
    }

    @objc private func convert(_ sender: HivePayloadButton) {
        guard let id = Int64(sender.payload) else { return }
        listener?.didConvert(id: id)
    }
}
