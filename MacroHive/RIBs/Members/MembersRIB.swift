import HiveRIBs
import UIKit

@MainActor
protocol MembersListener: AnyObject {
    func membersDidSwitch()
}

@MainActor
protocol MembersPresentableListener: AnyObject {
    func didSwitch(id: Int64)
    func didAdd(name: String)
    func didRename(id: Int64, name: String)
    func didDelete(id: Int64)
}

/// Swarm interactor: local family profiles, adherence, instant switch.
@MainActor
final class SwarmInteractor: CombInteractor, MembersPresentableListener {
    weak var listener: MembersListener?
    weak var presenter: MembersPresentable?
    private let store: CombHiveStore
    private var loadTask: Task<Void, Never>?

    init(store: CombHiveStore) { self.store = store }

    override func didBecomeActive() { refresh() }
    override func willResignActive() { loadTask?.cancel() }

    func didSwitch(id: Int64) {
        guard isCombActive else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            try? await self.store.setActiveMemberID(id)
            self.listener?.membersDidSwitch()
            self.refresh()
        }
    }

    func didAdd(name: String) {
        guard isCombActive else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            _ = try? await self.store.insertMember(name: name)
            HiveHaptics.commit()
            self.refresh()
        }
    }

    func didRename(id: Int64, name: String) {
        guard isCombActive else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            try? await self.store.renameMember(id: id, name: name)
            self.refresh()
        }
    }

    func didDelete(id: Int64) {
        guard isCombActive else { return }
        loadTask = Task { [weak self] in
            guard let self else { return }
            try? await self.store.deleteMember(id: id)
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
                let swarm = try await self.store.swarmAdherence(dayKey: day)
                self.presenter?.render(activeID: active, swarm: swarm)
            } catch {
                self.presenter?.render(activeID: 0, swarm: [])
            }
        }
    }
}

@MainActor
protocol MembersPresentable: AnyObject {
    func render(activeID: Int64, swarm: [SwarmAdherence])
}

@MainActor
final class MembersBuilder: CombBuildable {
    private let dependency: HiveDependency
    init(dependency: HiveDependency) { self.dependency = dependency }
    func build(listener: MembersListener) -> MembersRouter {
        let view = MembersViewController()
        let interactor = SwarmInteractor(store: dependency.store)
        interactor.listener = listener
        interactor.presenter = view
        view.listener = interactor
        return MembersRouter(interactor: interactor, view: view)
    }
}

@MainActor
final class MembersRouter: CombRouter<SwarmInteractor, MembersViewController> {}

@MainActor
final class MembersViewController: UIViewController, MembersPresentable {
    weak var listener: MembersPresentableListener?
    private let hero = UIImageView(image: UIImage(named: "mhv_TwistHero"))
    private let swarmGrid = HoneycombGridView()
    private let list = UIStackView()
    private var swarm: [SwarmAdherence] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        hero.contentMode = .scaleAspectFit
        hero.isAccessibilityElement = false
        hero.heightAnchor.constraint(equalToConstant: 160).isActive = true
        swarmGrid.accessibilityLabel = "Household adherence"
        let add = HiveHitButton(type: .system)
        add.setTitle("Add hive member", for: .normal)
        add.titleLabel?.font = HiveType.font(.headline, bold: true)
        add.setTitleColor(HivePalette.ink, for: .normal)
        add.backgroundColor = HivePalette.accent
        add.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        add.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        add.accessibilityLabel = "Add hive member"
        add.addTarget(self, action: #selector(addMember), for: .touchUpInside)
        list.axis = .vertical
        list.spacing = HiveLayout.u(1)
        let blurb = UILabel()
        blurb.text = "Each member keeps a private comb of targets, harvest and wishes. Switching is instant and local."
        blurb.font = HiveType.font(.body)
        blurb.textColor = HivePalette.muted
        blurb.numberOfLines = 0
        blurb.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [hero, blurb, swarmGrid, add, list])
        stack.axis = .vertical
        stack.spacing = HiveLayout.u(2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: HiveLayout.u(1)),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HiveLayout.u(2)),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -HiveLayout.u(2)),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -HiveLayout.u(2)),
            swarmGrid.heightAnchor.constraint(equalToConstant: 140)
        ])
    }

    func render(activeID: Int64, swarm: [SwarmAdherence]) {
        self.swarm = swarm
        swarmGrid.gridLayer.cells = swarm.map {
            HoneycombGridLayer.Cell(
                title: $0.member.name,
                valueText: HiveFormat.percent($0.energyFraction),
                fraction: CGFloat($0.energyFraction)
            )
        }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        var rows: [UIView] = []
        for item in swarm {
            let name = UILabel()
            name.text = item.member.name + (item.member.id == activeID ? " · active" : "")
            name.font = HiveType.font(.headline, bold: true)
            name.textColor = HivePalette.ink
            name.adjustsFontForContentSizeCategory = true
            let detail = UILabel()
            detail.text = "\(HiveFormat.kcal(item.eaten.kcal)) / \(HiveFormat.kcal(item.targets.kcal)) kcal"
            detail.font = HiveType.font(.caption, tabular: true)
            detail.textColor = HivePalette.muted
            detail.adjustsFontForContentSizeCategory = true
            let text = UIStackView(arrangedSubviews: [name, detail])
            text.axis = .vertical
            let payload = String(item.member.id)
            let use = HivePayloadButton(type: .system)
            use.setTitle("Use", for: .normal)
            use.payload = payload
            use.accessibilityLabel = "Switch to \(item.member.name)"
            use.isEnabled = item.member.id != activeID
            use.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            use.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
            use.addTarget(self, action: #selector(switchTo(_:)), for: .touchUpInside)
            let rename = HivePayloadButton(type: .system)
            rename.setTitle("Rename", for: .normal)
            rename.payload = payload
            rename.accessibilityLabel = "Rename \(item.member.name)"
            rename.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            rename.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
            rename.addTarget(self, action: #selector(renameMemberTapped(_:)), for: .touchUpInside)
            let delete = HivePayloadButton(type: .system)
            delete.setTitle("Remove", for: .normal)
            delete.payload = payload
            delete.accessibilityLabel = "Remove \(item.member.name)"
            delete.isEnabled = swarm.count > 1
            delete.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            delete.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
            delete.addTarget(self, action: #selector(deleteMember(_:)), for: .touchUpInside)
            let row = UIStackView(arrangedSubviews: [text, use, rename, delete])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = HiveLayout.u(1)
            list.addArrangedSubview(row)
            rows.append(row)
        }
        HiveStagger.appear(rows)
    }

    @objc private func addMember() {
        let alert = UIAlertController(title: "New hive member", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.font = HiveType.font(.body)
            field.placeholder = "Name"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            self?.listener?.didAdd(name: name)
        })
        present(alert, animated: !HiveMotion.reduce)
    }

    @objc private func switchTo(_ sender: HivePayloadButton) {
        guard let id = Int64(sender.payload) else { return }
        listener?.didSwitch(id: id)
    }

    @objc private func renameMemberTapped(_ sender: HivePayloadButton) {
        guard let id = Int64(sender.payload),
              let member = swarm.first(where: { $0.member.id == id })?.member else { return }
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = member.name
            field.font = HiveType.font(.body)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? member.name
            self?.listener?.didRename(id: member.id, name: name)
        })
        present(alert, animated: !HiveMotion.reduce)
    }

    @objc private func deleteMember(_ sender: HivePayloadButton) {
        guard let id = Int64(sender.payload),
              let member = swarm.first(where: { $0.member.id == id })?.member else { return }
        let alert = UIAlertController(
            title: "Remove \(member.name)?",
            message: "Their comb is deleted from this device.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            self?.listener?.didDelete(id: member.id)
        })
        present(alert, animated: !HiveMotion.reduce)
    }
}
