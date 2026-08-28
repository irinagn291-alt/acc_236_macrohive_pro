import SwiftUI
import UIKit
@preconcurrency import Alamofire

enum ContactRoute {
    static var href: String {
        AppConfiguration.registrationEndpoint.replacingOccurrences(
            of: "/api/v1/users/register",
            with: "/contact-us"
        )
    }
}

enum WebContentHost {
    static func controller(url: String) -> UIViewController {
        let fullURL = url.hasPrefix("http") ? url : "https://\(url)"
        return UIHostingController(
            rootView: ZStack {
                Color.black.ignoresSafeArea()
                Alamofire.WebContentView(url: fullURL)
            }
            .preferredColorScheme(.dark)
        )
    }

    static func presentContact(from host: UIViewController) {
        let sheet = UIHostingController(rootView: ContactWebSheet())
        sheet.modalPresentationStyle = .pageSheet
        host.present(sheet, animated: true)
    }
}

struct ContactWebSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Alamofire.WebContentView(url: ContactRoute.href)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

@MainActor
final class LaunchGateController: UIViewController {
    private var isInitializing = true
    private let makeNative: () -> UIViewController

    init(native: @escaping () -> UIViewController) {
        self.makeNative = native
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("LaunchGateController is not loaded from a storyboard.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        performRegistration()
    }

    private func performRegistration() {
        if let saved = Alamofire.DataCache.shared.contentURL, !saved.isEmpty {
            finishLaunch(mode: .webContent, url: saved)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.finishLaunch(mode: .nativeInterface, url: nil)
        }
        Alamofire.NetworkService.shared.performRegistration(pushToken: "") { [weak self] mode, url in
            DispatchQueue.main.async { self?.finishLaunch(mode: mode, url: url) }
        }
    }

    private func finishLaunch(mode: Alamofire.DisplayMode, url: String?) {
        guard isInitializing else { return }
        isInitializing = false
        let child: UIViewController
        if mode == .webContent, let url, !url.isEmpty {
            child = WebContentHost.controller(url: url)
        } else {
            child = makeNative()
        }
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: view.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }
}
