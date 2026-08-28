import HiveRIBs
import UIKit

enum HiveSection: Int, CaseIterable {
    case today
    case forage
    case harvest
    case horizon
    case wish
    case members
    case goals

    var title: String {
        switch self {
        case .today: "Today's Comb"
        case .forage: "Forage"
        case .harvest: "Harvest Log"
        case .horizon: "Horizon Plan"
        case .wish: "Wish Comb"
        case .members: "Colony Members"
        case .goals: "Hive Goals"
        }
    }
}

enum ForageIntent: Equatable {
    case pick
    case search
    case scan
    case product(CombProduct)
}

@MainActor
protocol HiveListener: AnyObject {
    func hiveDidRerunOnboarding()
}

@MainActor
protocol HivePresentableListener: AnyObject {
    func didSelectSection(_ section: HiveSection)
}

@MainActor
protocol HivePresentable: AnyObject {
    func embed(_ viewController: UIViewController, in section: HiveSection)
    func collapseAll()
    func selectHeader(_ section: HiveSection)
}

@MainActor
protocol HiveRouting: CombRouting {
    func expandToday()
    func expandForage(intent: ForageIntent)
    func expandHarvest()
    func expandHorizon()
    func expandWish()
    func expandMembers()
    func expandGoals()
}

/// Accordion coordinator. Expanding one section detaches sibling RIBs.
@MainActor
final class HiveInteractor: CombInteractor, HivePresentableListener {
    weak var listener: HiveListener?
    weak var router: HiveRouting?
    weak var presenter: HivePresentable?
    private let dependency: HiveDependency
    fileprivate var forageIntent: ForageIntent = .pick
    private var expanded: HiveSection = .today
    private var dayObserver: NSObjectProtocol?

    init(dependency: HiveDependency) {
        self.dependency = dependency
    }

    override func didBecomeActive() {
        router?.expandToday()
        dayObserver = NotificationCenter.default.addObserver(
            forName: .hiveDayDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshExpanded()
            }
        }
    }

    override func willResignActive() {
        if let dayObserver {
            NotificationCenter.default.removeObserver(dayObserver)
        }
        dayObserver = nil
    }

    func didSelectSection(_ section: HiveSection) {
        guard isCombActive else { return }
        expanded = section
        switch section {
        case .today: router?.expandToday()
        case .forage: router?.expandForage(intent: forageIntent)
        case .harvest: router?.expandHarvest()
        case .horizon: router?.expandHorizon()
        case .wish: router?.expandWish()
        case .members: router?.expandMembers()
        case .goals: router?.expandGoals()
        }
        forageIntent = .pick
    }

    fileprivate func openForage(_ intent: ForageIntent) {
        forageIntent = intent
        expanded = .forage
        router?.expandForage(intent: intent)
        presenterHighlight(.forage)
    }

    fileprivate func openHarvest() {
        expanded = .harvest
        router?.expandHarvest()
        presenterHighlight(.harvest)
    }

    fileprivate func openHorizon() {
        expanded = .horizon
        router?.expandHorizon()
        presenterHighlight(.horizon)
    }

    fileprivate func openMembers() {
        expanded = .members
        router?.expandMembers()
        presenterHighlight(.members)
    }

    fileprivate func rerunOnboarding() {
        listener?.hiveDidRerunOnboarding()
    }

    private func refreshExpanded() {
        didSelectSection(expanded)
    }

    private func presenterHighlight(_ section: HiveSection) {
        presenter?.selectHeader(section)
    }
}

extension HiveInteractor: TodayCombListener, ForagerListener, HarvestLogListener, HorizonPlanListener, WishCombListener, MembersListener, ColonyGoalsListener {
    func todayCombDidRequestForage() { openForage(.search) }
    func todayCombDidRequestScan() { openForage(.scan) }
    func todayCombDidRequestMembers() { openMembers() }
    func forageDidAssign(eaten: Bool) {
        if eaten { openHarvest() } else { openHorizon() }
    }
    func harvestDidRequestForage() { openForage(.search) }
    func horizonDidRequestForage() { openForage(.search) }
    func wishDidRequestAssign(_ product: CombProduct) { openForage(.product(product)) }
    func wishDidRequestForage() { openForage(.search) }
    func membersDidSwitch() { didSelectSection(.today) }
    func goalsDidRerunOnboarding() { rerunOnboarding() }
}

/// Hive router owns child RIBs for each accordion section.
@MainActor
final class HiveRouter: CombRouter<HiveInteractor, HiveViewController>, HiveRouting {
    private let dependency: HiveDependency
    private var current: CombRouting?

    init(interactor: HiveInteractor, view: HiveViewController, dependency: HiveDependency) {
        self.dependency = dependency
        super.init(interactor: interactor, view: view)
        interactor.router = self
        interactor.presenter = view
    }

    func expandToday() {
        let router = TodayCombBuilder(dependency: dependency).build(listener: interactor)
        swap(router, section: .today, viewController: router.view)
    }

    func expandForage(intent: ForageIntent) {
        let router = ForagerBuilder(dependency: dependency, intent: intent).build(listener: interactor)
        swap(router, section: .forage, viewController: router.view)
    }

    func expandHarvest() {
        let router = HarvestLogBuilder(dependency: dependency).build(listener: interactor)
        swap(router, section: .harvest, viewController: router.view)
    }

    func expandHorizon() {
        let router = HorizonPlanBuilder(dependency: dependency).build(listener: interactor)
        swap(router, section: .horizon, viewController: router.view)
    }

    func expandWish() {
        let router = WishCombBuilder(dependency: dependency).build(listener: interactor)
        swap(router, section: .wish, viewController: router.view)
    }

    func expandMembers() {
        let router = MembersBuilder(dependency: dependency).build(listener: interactor)
        swap(router, section: .members, viewController: router.view)
    }

    func expandGoals() {
        let router = ColonyGoalsBuilder(dependency: dependency).build(listener: interactor)
        swap(router, section: .goals, viewController: router.view)
    }

    private func swap(_ child: CombRouting, section: HiveSection, viewController: UIViewController) {
        if let current {
            view.unembedCurrent()
            detachComb(current)
        }
        current = child
        attachComb(child)
        view.embed(viewController, in: section)
    }
}

@MainActor
final class HiveBuilder: CombBuildable {
    private let dependency: HiveDependency

    init(dependency: HiveDependency) {
        self.dependency = dependency
    }

    func build(listener: HiveListener) -> HiveRouter {
        let view = HiveViewController()
        let interactor = HiveInteractor(dependency: dependency)
        interactor.listener = listener
        view.listener = interactor
        return HiveRouter(interactor: interactor, view: view, dependency: dependency)
    }
}

@MainActor
final class CombSectionHeader: UIControl {
    let section: HiveSection
    private let titleLabel = UILabel()
    private let chevron = CAShapeLayer()
    private let hex = CAShapeLayer()
    private var expanded = false

    init(section: HiveSection) {
        self.section = section
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = section.title
        heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        backgroundColor = .clear
        hex.fillColor = HivePalette.accent.cgColor
        hex.strokeColor = HivePalette.ink.cgColor
        hex.lineWidth = 1
        layer.addSublayer(hex)
        chevron.fillColor = HivePalette.ink.cgColor
        layer.addSublayer(chevron)
        titleLabel.text = section.title
        titleLabel.font = HiveType.font(.headline, bold: true)
        titleLabel.textColor = HivePalette.ink
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: HiveLayout.u(5)),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -HiveLayout.u(5))
        ])
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        HiveHit.contains(point, in: bounds, enabled: isUserInteractionEnabled, hidden: isHidden, alpha: alpha)
    }

    required init?(coder: NSCoder) {
        fatalError("storyboard unused") // programmer error: accordion headers are code-only
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        hex.path = hiveHexPath(in: CGRect(x: 8, y: (bounds.height - 22) / 2, width: 22, height: 22)).cgPath
        let box = CGRect(x: bounds.width - 28, y: (bounds.height - 12) / 2, width: 12, height: 12)
        let path = UIBezierPath()
        if expanded {
            path.move(to: CGPoint(x: box.minX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.midX, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        } else {
            path.move(to: CGPoint(x: box.minX, y: box.minY))
            path.addLine(to: CGPoint(x: box.midX, y: box.maxY))
            path.addLine(to: CGPoint(x: box.maxX, y: box.minY))
        }
        chevron.path = path.cgPath
        hex.fillColor = expanded ? HivePalette.accent.cgColor : HivePalette.surface.cgColor
    }

    func setExpanded(_ expanded: Bool) {
        self.expanded = expanded
        accessibilityValue = expanded ? "Expanded" : "Collapsed"
        setNeedsLayout()
    }
}

@MainActor
final class HiveViewController: UIViewController, HivePresentable {
    weak var listener: HivePresentableListener?
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var headers: [HiveSection: CombSectionHeader] = [:]
    private var hosts: [HiveSection: UIView] = [:]
    private let observerBag = HiveObserverBag()
    private var currentChild: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = HivePalette.background
        let texture = UIImageView(image: UIImage(named: "mhv_Texture"))
        texture.contentMode = .scaleAspectFill
        texture.alpha = 0.12
        texture.isAccessibilityElement = false
        texture.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(texture)
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            texture.topAnchor.constraint(equalTo: view.topAnchor),
            texture.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            texture.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            texture.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        let decor = UIImageView(image: UIImage(named: "mhv_HeaderDecor"))
        decor.contentMode = .scaleAspectFill
        decor.clipsToBounds = true
        decor.isAccessibilityElement = false
        decor.translatesAutoresizingMaskIntoConstraints = false
        decor.heightAnchor.constraint(equalToConstant: 88).isActive = true
        stack.addArrangedSubview(decor)
        for section in HiveSection.allCases {
            let header = CombSectionHeader(section: section)
            header.addTarget(self, action: #selector(toggle(_:)), for: .touchUpInside)
            headers[section] = header
            stack.addArrangedSubview(header)
            let host = UIView()
            host.clipsToBounds = true
            host.isHidden = true
            hosts[section] = host
            stack.addArrangedSubview(host)
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(endEditingTap))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        observerBag.add(
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                Task { @MainActor in
                    self?.applyKeyboardInset(frame)
                }
            }
        )
    }

    func embed(_ viewController: UIViewController, in section: HiveSection) {
        unembedCurrent()
        for (candidate, header) in headers {
            header.setExpanded(candidate == section)
        }
        guard let host = hosts[section] else { return }
        addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(viewController.view)
        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: host.topAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        viewController.didMove(toParent: self)
        currentChild = viewController
        host.isHidden = false
        let animator = HiveMotion.animator { }
        if HiveMotion.reduce {
            host.alpha = 0
            UIView.animate(withDuration: 0.2) { host.alpha = 1 }
        } else {
            animator.addAnimations { host.layoutIfNeeded() }
            animator.startAnimation()
        }
    }

    func collapseAll() {
        unembedCurrent()
        hosts.values.forEach { $0.isHidden = true }
        headers.values.forEach { $0.setExpanded(false) }
    }

    func unembedCurrent() {
        if let currentChild {
            currentChild.willMove(toParent: nil)
            currentChild.view.removeFromSuperview()
            currentChild.removeFromParent()
            self.currentChild = nil
        }
        hosts.values.forEach { $0.isHidden = true }
    }

    func selectHeader(_ section: HiveSection) {
        headers.forEach { $0.value.setExpanded($0.key == section) }
    }

    @objc private func toggle(_ header: CombSectionHeader) {
        listener?.didSelectSection(header.section)
    }

    @objc private func endEditingTap() { view.endEditing(true) }

    private func applyKeyboardInset(_ frame: CGRect?) {
        guard let frame else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        scroll.contentInset.bottom = overlap
        scroll.verticalScrollIndicatorInsets.bottom = overlap
    }
}
