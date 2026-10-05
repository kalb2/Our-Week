import Foundation

/// Payload the share extension leaves in the app group for the main app.
/// The extension writes the same keys; keep them in sync with `OurWeekShare/ShareViewController.swift`.
enum ShareImportStore {
    static let appGroupID = "group.com.kalebjensen.OurWeek"
    static let didArrive = Notification.Name("OurWeek.shareImportReady")

    static let kindKey = "share.kind"
    static let valueKey = "share.value"
    static let imageFilename = "share-image.jpg"

    enum Kind: String {
        case url
        case text
        case image
    }

    struct Payload {
        let kind: Kind
        let text: String
        let imageData: Data?
    }

    static var hasPending: Bool {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return false }
        return defaults.string(forKey: kindKey) != nil
    }

    /// Reads and clears one pending share. Image bytes are loaded from the group container.
    static func consume() -> Payload? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let rawKind = defaults.string(forKey: kindKey),
              let kind = Kind(rawValue: rawKind) else {
            return nil
        }
        let text = defaults.string(forKey: valueKey) ?? ""
        defaults.removeObject(forKey: kindKey)
        defaults.removeObject(forKey: valueKey)

        var imageData: Data?
        if kind == .image,
           let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            let file = container.appendingPathComponent(imageFilename)
            imageData = try? Data(contentsOf: file)
            try? FileManager.default.removeItem(at: file)
        }

        guard kind != .image || imageData != nil else { return nil }
        guard kind == .image || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Payload(kind: kind, text: text, imageData: imageData)
    }
}

extension Notification.Name {
    static let ourWeekOpenHome = Notification.Name("OurWeek.openHome")
}
