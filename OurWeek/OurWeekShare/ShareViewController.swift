import UIKit
import UniformTypeIdentifiers

/// Share sheet entry. Writes a URL, some text, or one image into the app group, then opens Our Week.
/// Keys match `ShareImportStore` in the app target.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let appGroupID = "group.com.kalebjensen.OurWeek"
    private let kindKey = "share.kind"
    private let valueKey = "share.value"
    private let imageFilename = "share-image.jpg"

    private let statusLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private var didStart = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 1, green: 0.976, blue: 0.965, alpha: 1)

        statusLabel.text = "Opening Our Week"
        statusLabel.font = .systemFont(ofSize: 20, weight: .regular)
        statusLabel.textColor = .black
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        openButton.setTitle("Open Our Week", for: .normal)
        openButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        openButton.setTitleColor(.white, for: .normal)
        openButton.backgroundColor = UIColor(red: 0.878, green: 0.478, blue: 0.373, alpha: 1)
        openButton.layer.cornerRadius = 26
        openButton.layer.borderWidth = 0
        openButton.isHidden = true
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.addTarget(self, action: #selector(openHost), for: .touchUpInside)

        view.addSubview(statusLabel)
        view.addSubview(openButton)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            openButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            openButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 220),
            openButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        Task { await ingest() }
    }

    @objc private func openHost() {
        openApp()
    }

    private func ingest() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            if let url = await loadURL(provider), isWebURL(url) {
                if write(kind: "url", value: url.absoluteString) {
                    openApp()
                }
                return
            }
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            if let data = await loadImageData(provider), writeImage(data) {
                openApp()
                return
            }
        }

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            if let text = await loadText(provider),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               write(kind: "text", value: text) {
                openApp()
                return
            }
        }

        fail("Nothing to add")
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: URL.self) { object, _ in
                continuation.resume(returning: object as? URL)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: String.self) { object, _ in
                continuation.resume(returning: object as? String)
            }
        }
    }

    private func loadImageData(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                let image = object as? UIImage
                continuation.resume(returning: image?.jpegData(compressionQuality: 0.8))
            }
        }
    }

    private func write(kind: String, value: String) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil else {
            fail("Couldn't reach Our Week")
            return false
        }
        defaults.set(kind, forKey: kindKey)
        defaults.set(value, forKey: valueKey)
        return true
    }

    private func writeImage(_ data: Data) -> Bool {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fail("Couldn't reach Our Week")
            return false
        }
        let file = container.appendingPathComponent(imageFilename)
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            fail("Couldn't reach Our Week")
            return false
        }
        return write(kind: "image", value: imageFilename)
    }

    /// `extensionContext.open` asks the host (Safari) to open the URL. Walking the
    /// responder chain reaches the extension's application object, which launches the containing app.
    private func openApp() {
        guard let url = URL(string: "ourweek://import") else { return }
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
                return
            }
            responder = current.next
        }

        extensionContext?.open(url) { [weak self] success in
            Task { @MainActor in
                if success {
                    self?.extensionContext?.completeRequest(returningItems: nil)
                } else {
                    self?.statusLabel.text = "Open Our Week to finish"
                    self?.openButton.isHidden = false
                }
            }
        }
    }

    private func fail(_ message: String) {
        statusLabel.text = message
        openButton.isHidden = false
    }
}
