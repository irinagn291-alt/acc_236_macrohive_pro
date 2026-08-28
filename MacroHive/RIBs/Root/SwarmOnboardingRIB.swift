import HiveRIBs
import UIKit

@MainActor
protocol SwarmOnboardingListener: AnyObject {
    func onboardingDidFinish()
}

@MainActor
protocol SwarmOnboardingPresentableListener: AnyObject {
    func didSkip()
    func didFinish(kcal: Double, protein: Double?, carbs: Double?, fat: Double?)
}

/// Onboarding interactor: writes first targets and the completion flag seam.
@MainActor
final class SwarmOnboardingInteractor: CombInteractor, SwarmOnboardingPresentableListener {
    weak var listener: SwarmOnboardingListener?
    weak var presenter: SwarmOnboardingPresentable?
    private let store: CombHiveStore
    private var writeTask: Task<Void, Never>?

    init(store: CombHiveStore) {
        self.store = store
    }

    override func willResignActive() {
        writeTask?.cancel()
    }

    func didSkip() {
        commit(
            kcal: HiveDefaults.kcal,
            protein: HiveDefaults.protein,
            carbs: HiveDefaults.carbs,
            fat: HiveDefaults.fat
        )
    }

    func didFinish(kcal: Double, protein: Double?, carbs: Double?, fat: Double?) {
        let energy = kcal > 0 ? kcal : HiveDefaults.kcal
        commit(kcal: energy, protein: protein, carbs: carbs, fat: fat)
    }

    private func commit(kcal: Double, protein: Double?, carbs: Double?, fat: Double?) {
        guard isCombActive else { return }
        writeTask?.cancel()
        presenter?.setCommitEnabled(false)
        writeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let profile = try await self.store.activeMemberID()
                try await self.store.saveTargets(
                    HiveTargets(profileID: profile, kcal: kcal, protein: protein, carbs: carbs, fat: fat)
                )
                HiveHaptics.commit()
                self.listener?.onboardingDidFinish()
            } catch {
                self.presenter?.setCommitEnabled(true)
                self.presenter?.showError("The hive could not store targets. Try again.")
            }
        }
    }
}

@MainActor
protocol SwarmOnboardingPresentable: AnyObject {
    func setCommitEnabled(_ enabled: Bool)
    func showError(_ message: String)
}

/// Builds the four-page swarm onboarding RIB.
@MainActor
final class SwarmOnboardingBuilder: CombBuildable {
    private let dependency: HiveDependency

    init(dependency: HiveDependency) {
        self.dependency = dependency
    }

    func build(listener: SwarmOnboardingListener) -> SwarmOnboardingRouter {
        let view = SwarmOnboardingViewController()
        let interactor = SwarmOnboardingInteractor(store: dependency.store)
        interactor.listener = listener
        interactor.presenter = view
        view.listener = interactor
        return SwarmOnboardingRouter(interactor: interactor, view: view)
    }
}

@MainActor
final class SwarmOnboardingRouter: CombRouter<SwarmOnboardingInteractor, SwarmOnboardingViewController> {}

@MainActor
final class SwarmOnboardingViewController: UIViewController, SwarmOnboardingPresentable {
    weak var listener: SwarmOnboardingPresentableListener?

    private let scroll = UIScrollView()
    private let pageControl = UIPageControl()
    private let skipButton = HiveHitButton(type: .system)
    private let nextButton = HiveHitButton(type: .system)
    private let kcalField = HiveTextField()
    private let proteinField = HiveTextField()
    private let carbsField = HiveTextField()
    private let fatField = HiveTextField()
    private let errorLabel = UILabel()
    private var pages: [UIView] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = HivePalette.background
        scroll.isPagingEnabled = true
        scroll.delegate = self
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = 4
        pageControl.currentPageIndicatorTintColor = HivePalette.accent
        pageControl.pageIndicatorTintColor = HivePalette.muted
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.addTarget(self, action: #selector(pageChanged), for: .valueChanged)
        skipButton.setTitle("Skip", for: .normal)
        skipButton.titleLabel?.font = HiveType.font(.headline)
        skipButton.setTitleColor(HivePalette.ink, for: .normal)
        skipButton.accessibilityLabel = "Skip onboarding"
        skipButton.addTarget(self, action: #selector(skip), for: .touchUpInside)
        nextButton.setTitle("Continue", for: .normal)
        nextButton.titleLabel?.font = HiveType.font(.headline, bold: true)
        nextButton.setTitleColor(HivePalette.ink, for: .normal)
        nextButton.backgroundColor = HivePalette.accent
        nextButton.addTarget(self, action: #selector(advance), for: .touchUpInside)
        nextButton.accessibilityLabel = "Continue"
        errorLabel.font = HiveType.font(.caption)
        errorLabel.textColor = HivePalette.ink
        errorLabel.numberOfLines = 0
        errorLabel.adjustsFontForContentSizeCategory = true
        let buttons = UIStackView(arrangedSubviews: [skipButton, nextButton])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = HiveLayout.u(1)
        buttons.translatesAutoresizingMaskIntoConstraints = false
        skipButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        nextButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        skipButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        nextButton.heightAnchor.constraint(greaterThanOrEqualToConstant: HiveLayout.tap).isActive = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.addSubview(pageControl)
        view.addSubview(errorLabel)
        view.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -HiveLayout.u(1)),
            pageControl.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageControl.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageControl.bottomAnchor.constraint(equalTo: errorLabel.topAnchor, constant: -HiveLayout.u(1)),
            errorLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            errorLabel.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -HiveLayout.u(1)),
            buttons.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -HiveLayout.u(1))
        ])
        pages = [page(image: "mhv_Onboarding1", title: "One hive, many eaters", body: "Log energy and macros for every member of the household. No accounts. The comb stays on this device."),
                 page(image: "mhv_Onboarding2", title: "Forage by name or code", body: "Search Open Food Facts or scan a barcode inside the accordion. The camera never leaves the hive screen."),
                 page(image: "mhv_Onboarding3", title: "A comb for each eater", body: "Family profiles each keep their own targets, log and wish comb. Switch instantly from Today."),
                 targetsPage()]
        let stack = UIStackView(arrangedSubviews: pages)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, multiplier: 4)
        ])
        kcalField.text = HiveFormat.kcal(HiveDefaults.kcal)
        proteinField.text = HiveFormat.macro(HiveDefaults.protein)
        carbsField.text = HiveFormat.macro(HiveDefaults.carbs)
        fatField.text = HiveFormat.macro(HiveDefaults.fat)
        [kcalField, proteinField, carbsField, fatField].forEach {
            $0.keyboardType = .decimalPad
            $0.delegate = self
        }
        let dismiss = UITapGestureRecognizer(target: self, action: #selector(endEditingTap))
        dismiss.cancelsTouchesInView = false
        view.addGestureRecognizer(dismiss)
    }

    func setCommitEnabled(_ enabled: Bool) {
        nextButton.isEnabled = enabled
        skipButton.isEnabled = enabled
    }

    func showError(_ message: String) {
        errorLabel.text = message
    }

    private func page(image: String, title: String, body: String) -> UIView {
        let page = UIView()
        let imageView = UIImageView(image: UIImage(named: image))
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = HiveType.font(.title, bold: true)
        titleLabel.textColor = HivePalette.ink
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.font = HiveType.font(.body)
        bodyLabel.textColor = HivePalette.muted
        bodyLabel.numberOfLines = 0
        bodyLabel.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [imageView, titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = HiveLayout.u(2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: HiveLayout.u(2)),
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: HiveLayout.u(3)),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -HiveLayout.u(3)),
            imageView.heightAnchor.constraint(equalTo: page.heightAnchor, multiplier: 0.45)
        ])
        return page
    }

    private func targetsPage() -> UIView {
        let page = UIView()
        func labeled(_ title: String, field: UITextField) -> UIStackView {
            let label = UILabel()
            label.text = title
            label.font = HiveType.font(.caption)
            label.textColor = HivePalette.muted
            label.adjustsFontForContentSizeCategory = true
            field.accessibilityLabel = title
            let stack = UIStackView(arrangedSubviews: [label, field])
            stack.axis = .vertical
            stack.spacing = HiveLayout.u(1)
            return stack
        }
        let title = UILabel()
        title.text = "Set the Queen's first targets"
        title.font = HiveType.font(.title, bold: true)
        title.textColor = HivePalette.ink
        title.numberOfLines = 0
        title.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [
            title,
            labeled("Energy, kcal", field: kcalField),
            labeled("Protein, g (optional)", field: proteinField),
            labeled("Carbs, g (optional)", field: carbsField),
            labeled("Fat, g (optional)", field: fatField)
        ])
        stack.axis = .vertical
        stack.spacing = HiveLayout.u(2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: HiveLayout.u(3)),
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: HiveLayout.u(3)),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -HiveLayout.u(3))
        ])
        return page
    }

    @objc private func skip() { listener?.didSkip() }

    @objc private func advance() {
        if pageControl.currentPage < 3 {
            pageControl.currentPage += 1
            scrollToPage()
            nextButton.setTitle(pageControl.currentPage == 3 ? "Write targets" : "Continue", for: .normal)
            return
        }
        let kcal = HiveFormat.parseDecimal(kcalField.text ?? "") ?? HiveDefaults.kcal
        let protein = HiveFormat.parseDecimal(proteinField.text ?? "")
        let carbs = HiveFormat.parseDecimal(carbsField.text ?? "")
        let fat = HiveFormat.parseDecimal(fatField.text ?? "")
        listener?.didFinish(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }

    @objc private func pageChanged() { scrollToPage() }

    @objc private func endEditingTap() { view.endEditing(true) }

    private func scrollToPage() {
        let x = CGFloat(pageControl.currentPage) * scroll.bounds.width
        scroll.setContentOffset(CGPoint(x: x, y: 0), animated: !HiveMotion.reduce)
        nextButton.setTitle(pageControl.currentPage == 3 ? "Write targets" : "Continue", for: .normal)
    }
}

extension SwarmOnboardingViewController: UIScrollViewDelegate, UITextFieldDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        pageControl.currentPage = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        nextButton.setTitle(pageControl.currentPage == 3 ? "Write targets" : "Continue", for: .normal)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string.isEmpty { return true }
        let separator = Locale.current.decimalSeparator ?? "."
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: separator))
        if string.rangeOfCharacter(from: allowed.inverted) != nil { return false }
        let current = textField.text ?? ""
        if string.contains(separator), current.contains(separator) { return false }
        return true
    }
}
