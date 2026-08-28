import HiveRIBs
import UIKit

@MainActor
protocol TodayCombListener: AnyObject {
    func todayCombDidRequestForage()
    func todayCombDidRequestScan()
    func todayCombDidRequestMembers()
}

@MainActor
protocol TodayCombPresentableListener: AnyObject {
    func didTapForage()
    func didTapScan()
    func didTapMembers()
    func didSelectMember(_ id: Int64)
}

struct TodayCombViewModel {
    var memberName: String
    var members: [HiveMember]
    var activeID: Int64
    var energyText: String
    var energyFraction: CGFloat
    var energyOver: Bool
    var protein: (String, CGFloat, Bool)
    var carbs: (String, CGFloat, Bool)
    var fat: (String, CGFloat, Bool)
    var slots: [(ForageSlot, String, String)]
    var swarm: [HoneycombGridLayer.Cell]
    var isEmpty: Bool
}

@MainActor
protocol TodayCombPresentable: AnyObject {
    func render(_ model: TodayCombViewModel)
}

/// Today comb interactor: computes day totals, never stores them.
@MainActor
final class TodayCombInteractor: CombInteractor, TodayCombPresentableListener {
    weak var listener: TodayCombListener?
    weak var presenter: TodayCombPresentable?
    private let store: CombHiveStore
    private var loadTask: Task<Void, Never>?

    init(store: CombHiveStore) {
        self.store = store
    }

    override func didBecomeActive() {
        refresh()
    }

    override func willResignActive() {
        loadTask?.cancel()
    }

    func didTapForage() { guard isCombActive else { return }; listener?.todayCombDidRequestForage() }
    func didTapScan() { guard isCombActive else { return }; listener?.todayCombDidRequestScan() }
    func didTapMembers() { guard isCombActive else { return }; listener?.todayCombDidRequestMembers() }

    func didSelectMember(_ id: Int64) {
        guard isCombActive else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            try? await self.store.setActiveMemberID(id)
            self.refresh()
        }
    }

    private func refresh() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let day = HiveDayKey.make(Date())
                let active = try await self.store.activeMemberID()
                let members = try await self.store.members()
                let targets = try await self.store.targets(profileID: active)
                let eaten = try await self.store.entries(profileID: active, dayKey: day, eaten: true)
                let sum = HiveTotals.sum(entries: eaten)
                let swarm = try await self.store.swarmAdherence(dayKey: day)
                let memberName = members.first(where: { $0.id == active })?.name ?? HiveDefaults.queenName
                func macro(_ eaten: Double?, _ target: Double?, label: String) -> (String, CGFloat, Bool) {
                    let eatenText = HiveFormat.compactMacro(eaten)
                    let targetText = HiveFormat.compactMacro(target)
                    let fraction: CGFloat
                    if let eaten, let target, target > 0 {
                        fraction = CGFloat(eaten / target)
                    } else {
                        fraction = 0
                    }
                    return ("\(label) \(eatenText) / \(targetText)", fraction, fraction > 1)
                }
                var slots: [(ForageSlot, String, String)] = []
                for slot in ForageSlot.allCases {
                    let items = eaten.filter { $0.slot == slot }
                    let kcal = items.reduce(0.0) { $0 + (CombPortion.scaled(per100: $1.product.kcal100, grams: $1.grams) ?? 0) }
                    let names = items.map(\.product.name).joined(separator: ", ")
                    slots.append((slot, names.isEmpty ? "Empty comb" : names, HiveFormat.kcal(kcal)))
                }
                let model = TodayCombViewModel(
                    memberName: memberName,
                    members: members,
                    activeID: active,
                    energyText: "\(HiveFormat.kcal(sum.kcal)) / \(HiveFormat.kcal(targets.kcal))",
                    energyFraction: CGFloat(HiveTotals.energyFraction(eaten: sum.kcal, target: targets.kcal)),
                    energyOver: sum.kcal > targets.kcal,
                    protein: macro(sum.protein, targets.protein, label: "P"),
                    carbs: macro(sum.carbs, targets.carbs, label: "C"),
                    fat: macro(sum.fat, targets.fat, label: "F"),
                    slots: slots,
                    swarm: swarm.map {
                        HoneycombGridLayer.Cell(
                            title: $0.member.name,
                            valueText: HiveFormat.percent($0.energyFraction),
                            fraction: CGFloat($0.energyFraction)
                        )
                    },
                    isEmpty: eaten.isEmpty
                )
                self.presenter?.render(model)
            } catch {
                self.presenter?.render(
                    TodayCombViewModel(
                        memberName: HiveDefaults.queenName,
                        members: [],
                        activeID: 0,
                        energyText: "—",
                        energyFraction: 0,
                        energyOver: false,
                        protein: ("P unknown", 0, false),
                        carbs: ("C unknown", 0, false),
                        fat: ("F unknown", 0, false),
                        slots: ForageSlot.allCases.map { ($0, "Empty comb", "0") },
                        swarm: [],
                        isEmpty: true
                    )
                )
            }
        }
    }
}

@MainActor
final class TodayCombBuilder: CombBuildable {
    private let dependency: HiveDependency
    init(dependency: HiveDependency) { self.dependency = dependency }

    func build(listener: TodayCombListener) -> TodayCombRouter {
        let view = TodayCombViewController()
        let interactor = TodayCombInteractor(store: dependency.store)
        interactor.listener = listener
        interactor.presenter = view
        view.listener = interactor
        return TodayCombRouter(interactor: interactor, view: view)
    }
}

@MainActor
final class TodayCombRouter: CombRouter<TodayCombInteractor, TodayCombViewController> {}

@MainActor
final class TodayCombViewController: UIViewController, TodayCombPresentable {
    weak var listener: TodayCombPresentableListener?
    private let memberStack = UIStackView()
    private let progress = ProgressCombView()
    private let protein = CombCell()
    private let carbs = CombCell()
    private let fat = CombCell()
    private let swarm = HoneycombGridView()
    private let slots = UIStackView()
    private let empty = CombEmptyView()
    private let forage = UIButton(type: .system)
    private let scan = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        memberStack.axis = .horizontal
        memberStack.spacing = HiveLayout.u(1)
        memberStack.alignment = .fill
        let macros = UIStackView(arrangedSubviews: [protein, carbs, fat])
        macros.axis = .horizontal
        macros.distribution = .fillEqually
        macros.spacing = HiveLayout.u(1)
        slots.axis = .vertical
        slots.spacing = HiveLayout.u(1)
        forage.setTitle("Search the combs", for: .normal)
        scan.setTitle("Scan a comb", for: .normal)
        for button in [forage, scan] {
            button.titleLabel?.font = HiveType.font(.headline, bold: true)
            button.setTitleColor(HivePalette.ink, for: .normal)
            button.backgroundColor = HivePalette.accent
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        }
        forage.accessibilityLabel = "Search the combs"
        scan.accessibilityLabel = "Scan a comb"
        forage.addTarget(self, action: #selector(tapForage), for: .touchUpInside)
        scan.addTarget(self, action: #selector(tapScan), for: .touchUpInside)
        forage.setBackgroundImage(UIImage(named: "mhv_ControlFace"), for: .normal)
        let actions = UIStackView(arrangedSubviews: [forage, scan])
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = HiveLayout.u(1)
        empty.render(image: "mhv_EmptyLog", title: "The comb is empty", body: "Forage a product for this hive member.", action: "Start foraging")
        empty.onAction = { [weak self] in self?.listener?.didTapForage() }
        swarm.accessibilityLabel = "Family adherence honeycomb"
        let swarmTap = UITapGestureRecognizer(target: self, action: #selector(tapMembers))
        swarm.addGestureRecognizer(swarmTap)
        swarm.isUserInteractionEnabled = true
        let stack = UIStackView(arrangedSubviews: [memberStack, progress, macros, swarm, slots, empty, actions])
        stack.axis = .vertical
        stack.spacing = HiveLayout.u(2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: HiveLayout.u(1)),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HiveLayout.u(2)),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -HiveLayout.u(2)),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -HiveLayout.u(2)),
            progress.heightAnchor.constraint(equalToConstant: 180),
            protein.heightAnchor.constraint(equalToConstant: 112),
            carbs.heightAnchor.constraint(equalToConstant: 112),
            fat.heightAnchor.constraint(equalToConstant: 112),
            swarm.heightAnchor.constraint(equalToConstant: 140)
        ])
        protein.accessibilityLabel = "Protein"
        carbs.accessibilityLabel = "Carbohydrates"
        fat.accessibilityLabel = "Fat"
    }

    func render(_ model: TodayCombViewModel) {
        memberStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for member in model.members {
            let chip = UIButton(type: .system)
            chip.setTitle(member.name, for: .normal)
            chip.titleLabel?.font = HiveType.font(.callout, bold: member.id == model.activeID)
            chip.setTitleColor(HivePalette.ink, for: .normal)
            chip.backgroundColor = member.id == model.activeID ? HivePalette.accent : HivePalette.surface
            chip.layer.borderWidth = 1
            chip.layer.borderColor = HivePalette.ink.cgColor
            chip.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
            chip.tag = Int(truncatingIfNeeded: member.id)
            chip.accessibilityLabel = "Hive member \(member.name)"
            chip.accessibilityValue = member.id == model.activeID ? "Active" : "Inactive"
            chip.addTarget(self, action: #selector(tapMember(_:)), for: .touchUpInside)
            memberStack.addArrangedSubview(chip)
        }
        progress.progressLayer.setProgress(
            model.energyFraction,
            valueText: model.energyText,
            animated: !HiveMotion.reduce
        )
        progress.accessibilityValue = model.energyText + (model.energyOver ? ", over target" : "")
        protein.render(caption: "Protein", value: model.protein.0, fraction: model.protein.1, exceeded: model.protein.2)
        carbs.render(caption: "Carbs", value: model.carbs.0, fraction: model.carbs.1, exceeded: model.carbs.2)
        fat.render(caption: "Fat", value: model.fat.0, fraction: model.fat.1, exceeded: model.fat.2)
        swarm.gridLayer.cells = model.swarm
        swarm.accessibilityValue = model.swarm.map { "\($0.title) \($0.valueText)" }.joined(separator: ", ")
        slots.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (slot, names, kcal) in model.slots {
            slots.addArrangedSubview(slotRow(slot: slot, names: names, kcal: kcal))
        }
        empty.isHidden = !model.isEmpty
        slots.isHidden = model.isEmpty
    }

    private func slotRow(slot: ForageSlot, names: String, kcal: String) -> UIView {
        let icon = UIImageView(image: UIImage(named: slot.assetName))
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let title = UILabel()
        title.text = slot.title
        title.font = HiveType.font(.headline, bold: true)
        title.textColor = HivePalette.ink
        title.adjustsFontForContentSizeCategory = true
        let body = UILabel()
        body.text = names
        body.font = HiveType.font(.caption)
        body.textColor = HivePalette.muted
        body.lineBreakMode = .byTruncatingTail
        body.adjustsFontForContentSizeCategory = true
        let value = UILabel()
        value.text = kcal
        value.font = HiveType.font(.headline, bold: true, tabular: true)
        value.textColor = HivePalette.ink
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        value.adjustsFontForContentSizeCategory = true
        let text = UIStackView(arrangedSubviews: [title, body])
        text.axis = .vertical
        let row = UIStackView(arrangedSubviews: [icon, text, value])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HiveLayout.u(1)
        row.accessibilityLabel = "\(slot.title), \(names), \(kcal) kilocalories"
        row.isAccessibilityElement = true
        return row
    }

    @objc private func tapForage() { listener?.didTapForage() }
    @objc private func tapScan() { listener?.didTapScan() }
    @objc private func tapMembers() { listener?.didTapMembers() }
    @objc private func tapMember(_ sender: UIButton) {
        listener?.didSelectMember(Int64(sender.tag))
    }
}
