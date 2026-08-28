import HiveRIBs
import UIKit

@MainActor
protocol RootRouting: CombRouting {
    func routeToOnboarding()
    func routeToHive()
}

/// Owns the window tree: onboarding then the accordion hive.
@MainActor
final class RootInteractor: CombInteractor, SwarmOnboardingListener, HiveListener {
    weak var router: RootRouting?
    private let dependency: HiveDependency
    private var bootstrapTask: Task<Void, Never>?
    private var timeObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var bootstrapFailed = false

    init(dependency: HiveDependency) {
        self.dependency = dependency
    }

    override func didBecomeActive() {
        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.dependency.store.bootstrap()
#if targetEnvironment(simulator)
                if !self.dependency.prefs.demoSeeded {
                    let profile = try await self.dependency.store.activeMemberID()
                    try await self.dependency.store.seedDemoDay(
                        dayKey: HiveDayKey.make(Date()),
                        profileID: profile
                    )
                    self.dependency.prefs.demoSeeded = true
                }
#endif
            } catch {
                self.bootstrapFailed = true
            }
            guard !Task.isCancelled, self.isCombActive else { return }
            if self.dependency.prefs.onboarded {
                self.router?.routeToHive()
            } else {
                self.router?.routeToOnboarding()
            }
        }
        timeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.significantTimeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDayShift() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDayShift() }
        }
    }

    override func willResignActive() {
        bootstrapTask?.cancel()
        if let timeObserver {
            NotificationCenter.default.removeObserver(timeObserver)
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        timeObserver = nil
        foregroundObserver = nil
    }

    func onboardingDidFinish() {
        dependency.prefs.onboarded = true
        router?.routeToHive()
    }

    func hiveDidRerunOnboarding() {
        dependency.prefs.onboarded = false
        router?.routeToOnboarding()
    }

    private func handleDayShift() {
        NotificationCenter.default.post(name: .hiveDayDidChange, object: nil)
    }
}

extension Notification.Name {
    static let hiveDayDidChange = Notification.Name("mhv.day.change")
}

/// Root router attaches either the swarm onboarding RIB or the hive RIB.
@MainActor
final class RootRouter: CombRouter<RootInteractor, RootViewController>, RootRouting {
    private let dependency: HiveDependency
    private var onboardingRouter: SwarmOnboardingRouter?
    private var hiveRouter: HiveRouter?

    init(interactor: RootInteractor, view: RootViewController, dependency: HiveDependency) {
        self.dependency = dependency
        super.init(interactor: interactor, view: view)
        interactor.router = self
    }

    func routeToOnboarding() {
        detachHive()
        guard onboardingRouter == nil else { return }
        let router = SwarmOnboardingBuilder(dependency: dependency).build(listener: interactor)
        onboardingRouter = router
        attachComb(router)
        view.embed(router.view)
    }

    func routeToHive() {
        detachOnboarding()
        guard hiveRouter == nil else { return }
        let router = HiveBuilder(dependency: dependency).build(listener: interactor)
        hiveRouter = router
        attachComb(router)
        view.embed(router.view)
    }

    private func detachOnboarding() {
        if let onboardingRouter {
            view.unembed(onboardingRouter.view)
            detachComb(onboardingRouter)
            self.onboardingRouter = nil
        }
    }

    private func detachHive() {
        if let hiveRouter {
            view.unembed(hiveRouter.view)
            detachComb(hiveRouter)
            self.hiveRouter = nil
        }
    }
}

/// Constructs the root RIB.
@MainActor
final class RootBuilder {
    private let dependency: HiveDependency

    init(dependency: HiveDependency) {
        self.dependency = dependency
    }

    func build() -> RootRouter {
        let view = RootViewController()
        let interactor = RootInteractor(dependency: dependency)
        return RootRouter(interactor: interactor, view: view, dependency: dependency)
    }
}

@MainActor
final class RootViewController: UIViewController {
    private weak var embedded: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = HivePalette.background
    }

    func embed(_ child: UIViewController) {
        if let embedded {
            embedded.willMove(toParent: nil)
            embedded.view.removeFromSuperview()
            embedded.removeFromParent()
        }
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        child.didMove(toParent: self)
        embedded = child
    }

    func unembed(_ child: UIViewController) {
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        if embedded === child { embedded = nil }
    }
}
