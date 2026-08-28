import HiveRIBs
import UIKit

@MainActor
protocol ForagerListener: AnyObject {
    func forageDidAssign(eaten: Bool)
}

enum ForagerSearchState: Equatable {
    case idle
    case loading
    case results
    case empty
    case transport
}

enum ForagerScanState: Equatable {
    case ready
    case simulator
    case denied
    case restricted
    case missing
}

enum ForagerPane: Equatable {
    case pick
    case search
    case scan
    case detail
    case assign
}

struct ForagerViewModel {
    var pane: ForagerPane
    var searchState: ForagerSearchState
    var scanState: ForagerScanState
    var query: String
    var results: [CombProduct]
    var usedShelfFallback: Bool
    var product: CombProduct?
    var gramsText: String
    var wishSaved: Bool
    var missingEnergy: Bool
    var barcodeMessage: String?
    var slot: ForageSlot
    var eaten: Bool
    var futureDay: Int
    var commitEnabled: Bool
    var commitInFlight: Bool
}

@MainActor
protocol ForagerPresentableListener: AnyObject {
    func didChooseSearch()
    func didChooseScan()
    func didChangeQuery(_ text: String)
    func didSelectProduct(_ product: CombProduct)
    func didSubmitBarcode(_ raw: String)
    func didChangeGrams(_ text: String)
    func didRequestWish()
    func didRequestAssign()
    func didPickSlot(_ slot: ForageSlot)
    func didPickEaten(_ eaten: Bool)
    func didPickFutureDay(_ dayKey: Int)
    func didConfirmAssign()
    func didRetrySearch()
    func didOpenSettings()
}

/// Forager interactor: search, scan resolve, portion maths, assign. No UI types.
@MainActor
final class ForagerInteractor: CombInteractor, ForagerPresentableListener {
    weak var listener: ForagerListener?
    weak var presenter: ForagerPresentable?
    private let store: CombHiveStore
    private let nectar: NectarClient
    private let intent: ForageIntent
    private var searchTask: Task<Void, Never>?
    private var resolveTask: Task<Void, Never>?
    private var spinnerTask: Task<Void, Never>?
    private var pane: ForagerPane = .pick
    private var searchState: ForagerSearchState = .idle
    private var query = ""
    private var results: [CombProduct] = []
    private var usedShelfFallback = false
    private var product: CombProduct?
    private var grams: Double = 100
    private var wishSaved = false
    private var barcodeMessage: String?
    private var slot: ForageSlot = .firstForage
    private var eaten = true
    private var futureDay = HiveDayKey.adding(days: 1, to: HiveDayKey.make(Date()))
    private var commitInFlight = false
    private var profileID: Int64 = 0

    init(store: CombHiveStore, nectar: NectarClient, intent: ForageIntent) {
        self.store = store
        self.nectar = nectar
        self.intent = intent
    }

    override func didBecomeActive() {
        switch intent {
        case .pick: pane = .pick
        case .search: pane = .search
        case .scan: pane = .scan
        case .product(let product):
            self.product = product
            pane = .detail
            Task { await self.primeWish(product) }
        }
        Task { [weak self] in
            self?.profileID = (try? await self?.store.activeMemberID()) ?? 0
        }
        publish()
    }

    override func willResignActive() {
        searchTask?.cancel()
        resolveTask?.cancel()
        spinnerTask?.cancel()
    }

    func didChooseSearch() { pane = .search; publish() }
    func didChooseScan() { pane = .scan; publish() }

    func didChangeQuery(_ text: String) {
        query = text
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchState = .idle
            results = []
            publish()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.runSearch(trimmed)
        }
    }

    func didRetrySearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task { await runSearch(trimmed) }
    }

    func didSelectProduct(_ product: CombProduct) {
        self.product = product
        pane = .detail
        grams = 100
        barcodeMessage = nil
        Task { await primeWish(product) }
        publish()
    }

    func didSubmitBarcode(_ raw: String) {
        guard isCombActive else { return }
        resolveTask?.cancel()
        resolveTask = Task { [weak self] in
            await self?.resolve(raw)
        }
    }

    func didChangeGrams(_ text: String) {
        if let parsed = HiveFormat.parseDecimal(text), CombPortion.gramsAreValid(parsed) {
            grams = parsed
        } else if text.isEmpty {
            grams = 0
        }
        publish()
    }

    func didRequestWish() {
        guard isCombActive, let product, !wishSaved else { return }
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.store.upsertWish(profileID: self.profileID, product: product)
            self.wishSaved = true
            HiveHaptics.commit()
            self.publish()
        }
    }

    func didRequestAssign() {
        guard CombPortion.gramsAreValid(grams), product != nil else { return }
        pane = .assign
        publish()
    }

    func didPickSlot(_ slot: ForageSlot) {
        self.slot = ForageSlot.resolving(slot, isFuture: !eaten)
        publish()
    }

    func didPickEaten(_ eaten: Bool) {
        self.eaten = eaten
        slot = ForageSlot.resolving(slot, isFuture: !eaten)
        publish()
    }

    func didPickFutureDay(_ dayKey: Int) {
        futureDay = dayKey
        eaten = false
        slot = ForageSlot.resolving(slot, isFuture: true)
        publish()
    }

    func didConfirmAssign() {
        guard isCombActive, let product, CombPortion.gramsAreValid(grams), !commitInFlight else { return }
        commitInFlight = true
        publish()
        Task { [weak self] in
            guard let self else { return }
            do {
                let day = self.eaten ? HiveDayKey.make(Date()) : self.futureDay
                _ = try await self.store.insertEntry(
                    profileID: self.profileID,
                    product: product,
                    grams: self.grams,
                    slot: self.slot,
                    dayKey: day,
                    isEaten: self.eaten
                )
                HiveHaptics.commit()
                self.commitInFlight = false
                self.listener?.forageDidAssign(eaten: self.eaten)
            } catch {
                self.commitInFlight = false
                self.barcodeMessage = "The hive could not store that comb."
                self.publish()
            }
        }
    }

    func didOpenSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func runSearch(_ terms: String) async {
        startSpinner()
        do {
            let remote = try await nectar.search(terms: terms)
            guard !Task.isCancelled else { return }
            let shelf = CombShelf.matches(terms)
            let merged = CombShelf.merge(remote: remote, shelf: shelf)
            finishSpinner()
            if merged.isEmpty {
                results = CombShelf.comb
                usedShelfFallback = true
                searchState = results.isEmpty ? .empty : .results
            } else {
                results = merged
                usedShelfFallback = remote.isEmpty && !shelf.isEmpty
                searchState = .results
            }
            publish()
        } catch is CancellationError {
            return
        } catch NectarError.cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            finishSpinner()
            let shelf = CombShelf.matches(terms)
            results = shelf.isEmpty ? CombShelf.comb : shelf
            usedShelfFallback = true
            searchState = results.isEmpty ? .transport : .results
            publish()
        }
    }

    private func resolve(_ raw: String) async {
        let codes = CombBarcode.normalisedCandidates(from: raw)
        guard !codes.isEmpty else {
            barcodeMessage = HiveVoice.notFound
            publish()
            return
        }
        startSpinner()
        var last: NectarError = .notFound
        for code in codes {
            if let cached = try? await store.product(barcode: code), cached.refreshedAt > 0 || CombShelf.product(barcode: code) != nil {
                finishSpinner()
                didSelectProduct(cached)
                return
            }
            do {
                let fetched = try await nectar.product(code: code)
                try? await store.upsertProduct(fetched)
                finishSpinner()
                didSelectProduct(fetched)
                return
            } catch NectarError.notFound {
                last = .notFound
            } catch NectarError.cancelled {
                return
            } catch {
                last = .transport
                if let cached = try? await store.product(barcode: code) {
                    finishSpinner()
                    didSelectProduct(cached)
                    return
                }
            }
        }
        finishSpinner()
        if let shelf = codes.compactMap(CombShelf.product(barcode:)).first {
            didSelectProduct(shelf)
            return
        }
        barcodeMessage = last == .transport ? HiveVoice.offline : HiveVoice.notFound
        pane = .scan
        publish()
    }

    private func primeWish(_ product: CombProduct) async {
        wishSaved = (try? await store.hasWish(profileID: profileID, barcode: product.barcode)) ?? false
        publish()
    }

    private func startSpinner() {
        spinnerTask?.cancel()
        spinnerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.searchState = .loading
            self?.publish()
        }
    }

    private func finishSpinner() {
        spinnerTask?.cancel()
    }

    private func publish() {
        let scanState: ForagerScanState
        if !CombVisionCatcher.hasCaptureDevice {
            scanState = .simulator
        } else {
            switch CombVisionCatcher.authorization {
            case .denied: scanState = .denied
            case .restricted: scanState = .restricted
            default: scanState = .ready
            }
        }
        presenter?.render(
            ForagerViewModel(
                pane: pane,
                searchState: searchState,
                scanState: scanState,
                query: query,
                results: results,
                usedShelfFallback: usedShelfFallback,
                product: product,
                gramsText: grams > 0 ? HiveFormat.grams(grams) : "",
                wishSaved: wishSaved,
                missingEnergy: product?.kcal100 == nil,
                barcodeMessage: barcodeMessage,
                slot: slot,
                eaten: eaten,
                futureDay: futureDay,
                commitEnabled: CombPortion.gramsAreValid(grams) && product != nil && !commitInFlight,
                commitInFlight: commitInFlight
            )
        )
    }
}

@MainActor
protocol ForagerPresentable: AnyObject {
    func render(_ model: ForagerViewModel)
}

/// Builds the forage RIB: search, scan, detail and assign stay inline.
@MainActor
final class ForagerBuilder: CombBuildable {
    private let dependency: HiveDependency
    private let intent: ForageIntent

    init(dependency: HiveDependency, intent: ForageIntent) {
        self.dependency = dependency
        self.intent = intent
    }

    func build(listener: ForagerListener) -> ForagerRouter {
        let view = ForagerViewController()
        let interactor = ForagerInteractor(store: dependency.store, nectar: dependency.nectar, intent: intent)
        interactor.listener = listener
        interactor.presenter = view
        view.listener = interactor
        view.images = dependency.images
        return ForagerRouter(interactor: interactor, view: view)
    }
}

@MainActor
final class ForagerRouter: CombRouter<ForagerInteractor, ForagerViewController> {}
