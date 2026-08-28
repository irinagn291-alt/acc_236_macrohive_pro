import Foundation

/// Lifecycle for a RIB node. Parents activate children on attach and
/// deactivate them on detach.
@MainActor
public protocol CombLifecycle: AnyObject {
    var isCombActive: Bool { get }
    func activateComb()
    func deactivateComb()
}

/// Business logic node. Listeners propagate events upward; the router is
/// owned by the parent and weakly referenced here.
@MainActor
public protocol CombInteractable: CombLifecycle {
    var combRouter: CombRouting? { get set }
}

/// Routing node that owns child RIB lifecycles.
@MainActor
public protocol CombRouting: AnyObject {
    var combInteractable: CombInteractable { get }
    var combChildren: [CombRouting] { get }
    func attachComb(_ child: CombRouting)
    func detachComb(_ child: CombRouting)
    func loadComb()
    func unloadComb()
}

/// Constructs a RIB subtree. The listener is the parent interactor.
@MainActor
public protocol CombBuildable {
    associatedtype Routing: CombRouting
    associatedtype Listener
    func build(listener: Listener) -> Routing
}

/// Interactor base. Activate/deactivate is the only lifecycle seam.
@MainActor
open class CombInteractor: CombInteractable {
    public weak var combRouter: CombRouting?
    public private(set) var isCombActive = false

    public init() {}

    public func activateComb() {
        guard !isCombActive else { return }
        isCombActive = true
        didBecomeActive()
    }

    public func deactivateComb() {
        guard isCombActive else { return }
        willResignActive()
        isCombActive = false
    }

    open func didBecomeActive() {}
    open func willResignActive() {}
}

/// Router base. Parent routers attach and detach children explicitly.
@MainActor
open class CombRouter<InteractorType: CombInteractable, ViewType: AnyObject>: CombRouting {
    public let interactor: InteractorType
    public let view: ViewType
    public private(set) var combChildren: [CombRouting] = []

    public var combInteractable: CombInteractable { interactor }

    public init(interactor: InteractorType, view: ViewType) {
        self.interactor = interactor
        self.view = view
        interactor.combRouter = self
    }

    public func attachComb(_ child: CombRouting) {
        guard !combChildren.contains(where: { $0 === child }) else { return }
        combChildren.append(child)
        child.loadComb()
    }

    public func detachComb(_ child: CombRouting) {
        guard let index = combChildren.firstIndex(where: { $0 === child }) else { return }
        child.unloadComb()
        combChildren.remove(at: index)
    }

    public func loadComb() {
        interactor.activateComb()
        didLoad()
    }

    public func unloadComb() {
        willUnload()
        for child in combChildren.reversed() {
            child.unloadComb()
        }
        combChildren.removeAll()
        interactor.deactivateComb()
    }

    open func didLoad() {}
    open func willUnload() {}
}
