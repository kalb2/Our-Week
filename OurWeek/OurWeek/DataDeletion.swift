//
//  DataDeletion.swift
//  OurWeek
//
//  "Delete all my data" (••• → Account). Removes everything Our Week keeps for
//  this person, leaves or removes a shared household, and returns the app to a
//  first-run state.
//

import CloudKit
import CoreData
import EventKit
import SwiftUI
import UserNotifications
import WidgetKit

extension Notification.Name {
    /// Posted after "Delete all my data" finishes. The app rebuilds its views.
    static let ourWeekDataDeleted = Notification.Name("OurWeek.dataDeleted")
}

/// How this person takes part in household sharing, read before deleting.
struct HouseholdSharingRole: Equatable {
    /// This person owns a household that is shared (or has invites out).
    var ownsSharedHousehold = false
    /// This person joined someone else's household.
    var joinedHousehold = false
    /// The owner of the joined household, when iCloud gives a name.
    var joinedOwnerName: String?

    @MainActor
    static func current(persistence: PersistenceController = .shared) -> HouseholdSharingRole {
        var role = HouseholdSharingRole()
        guard let ck = persistence.cloudKitContainer else { return role }
        if let store = persistence.privatePersistentStore,
           let shares = try? ck.fetchShares(in: store), !shares.isEmpty {
            role.ownsSharedHousehold = true
        }
        if let store = persistence.sharedPersistentStore,
           let shares = try? ck.fetchShares(in: store), let first = shares.first {
            role.joinedHousehold = true
            role.joinedOwnerName = first.owner.userIdentity.nameComponents?.formatted()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
        }
        return role
    }
}

enum DataDeletionError: LocalizedError {
    case household(Error)

    var errorDescription: String? {
        switch self {
        case .household:
            return "Couldn't update the shared household in iCloud. Check your connection and try again. Nothing else was deleted."
        }
    }
}

@MainActor
enum DataDeletion {
    /// Deletes everything Our Week keeps for this person. Throws only when the
    /// household step fails, before anything else is deleted.
    static func deleteEverything(persistence: PersistenceController = .shared) async throws {
        let defaults = UserDefaults.standard

        // Read what the EventKit steps need before UserDefaults and Core Data go.
        let calendarCopies = appleCalendarCopyIDs(persistence: persistence)
        let remindersListID = defaults.string(forKey: RemindersSync.listIDKey)
        let pushedReminderIDs = Set(defaults.stringArray(forKey: "appleRemindersPushedIDs") ?? [])

        // Stop in-flight work that could write old data back.
        WeekGrocerySync.resetAfterDataDeletion()
        HomeWidgetStore.resetAfterDataDeletion()
        TonightWidgetStore.resetAfterDataDeletion()
        GoalReminderScheduler.cancelForDataDeletion()
        PrepAheadScheduler.cancelForDataDeletion()

        // 1. Household sharing. A member leaves; an owner stops sharing and deletes it.
        do {
            try await leaveOrRemoveSharedHouseholds(persistence: persistence)
        } catch {
            throw DataDeletionError.household(error)
        }

        // 2. Apple Reminders and Apple Calendar items Our Week created.
        await deleteOurWeekReminders(listID: remindersListID, pushedIDs: pushedReminderIDs)
        deleteAppleCalendarCopies(calendarCopies)

        // 3. Everything in the private Core Data / CloudKit store.
        deletePrivateStoreRecords(persistence: persistence)
        await purgePrivateCloudKitZone(persistence: persistence)

        // 4. Notifications.
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        // 5. Keychain.
        try? KeychainManager.deleteGeminiAPIKey()

        // 6. In-memory caches, then files and UserDefaults.
        RateLimiter.shared.resetAllLimits()
        AIResponseCache.shared.clearCache()
        GoalsCenter.shared.resetAfterDataDeletion()
        deleteFiles()
        if let bundleID = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleID)
        }
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
        if let group = UserDefaults(suiteName: ShareImportStore.appGroupID) {
            for key in group.dictionaryRepresentation().keys {
                group.removeObject(forKey: key)
            }
            group.removePersistentDomain(forName: ShareImportStore.appGroupID)
        }

        // 7. Widgets show their empty state.
        WidgetCenter.shared.reloadAllTimelines()

        NotificationCenter.default.post(name: .ourWeekDataDeleted, object: nil)
    }

    // MARK: - Household

    private static func leaveOrRemoveSharedHouseholds(persistence: PersistenceController) async throws {
        guard let ck = persistence.cloudKitContainer else { return }
        // Member: purging a zone in the shared store removes this person from the
        // share and drops the local copy. The owner's data stays with the owner.
        if let shared = persistence.sharedPersistentStore {
            let zones = Set(try ck.fetchShares(in: shared).map(\.recordID.zoneID))
            for zone in zones {
                try await purge(zone, in: shared, container: ck)
            }
        }
        // Owner: purging the shared zone in the private store deletes the CKShare
        // (sharing stops for every member) and the household's records.
        if let privateStore = persistence.privatePersistentStore {
            let zones = Set(try ck.fetchShares(in: privateStore).map(\.recordID.zoneID))
            for zone in zones {
                try await purge(zone, in: privateStore, container: ck)
            }
        }
    }

    private static func purge(
        _ zoneID: CKRecordZone.ID,
        in store: NSPersistentStore,
        container: NSPersistentCloudKitContainer
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.purgeObjectsAndRecordsInZone(with: zoneID, in: store) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Core Data

    private static func deletePrivateStoreRecords(persistence: PersistenceController) {
        let context = persistence.container.viewContext
        let stores: [NSPersistentStore]
        if persistence.isInMemory {
            stores = persistence.container.persistentStoreCoordinator.persistentStores
        } else if let privateStore = persistence.privatePersistentStore {
            stores = [privateStore]
        } else {
            return
        }
        for entity in persistence.container.managedObjectModel.entities {
            guard let name = entity.name else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.affectedStores = stores
            request.includesPropertyValues = false
            if let objects = try? context.fetch(request) {
                objects.forEach(context.delete)
            }
        }
        if context.hasChanges {
            try? context.save()
        }
        try? context.setQueryGenerationFrom(.current)
        context.refreshAllObjects()
    }

    /// Also clears the default CloudKit zone, which catches records not yet on this device.
    private static func purgePrivateCloudKitZone(persistence: PersistenceController) async {
        guard let ck = persistence.cloudKitContainer,
              let privateStore = persistence.privatePersistentStore else { return }
        let account = try? await CKContainer(identifier: PersistenceController.cloudKitContainerID).accountStatus()
        guard account == .available else { return }
        let zone = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        try? await purge(zone, in: privateStore, container: ck)
    }

    // MARK: - EventKit

    private static func appleCalendarCopyIDs(persistence: PersistenceController) -> [String] {
        let request: NSFetchRequest<CalendarEvent> = CalendarEvent.fetchRequest()
        request.predicate = NSPredicate(format: "appleEventID != nil")
        let events = (try? persistence.container.viewContext.fetch(request)) ?? []
        return events.compactMap(\.appleEventID).filter { !$0.isEmpty }
    }

    private static func deleteAppleCalendarCopies(_ ids: [String]) {
        guard !ids.isEmpty, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let store = EKEventStore()
        var removed = false
        for id in Set(ids) {
            if let event = store.event(withIdentifier: id) {
                try? store.remove(event, span: .thisEvent, commit: false)
                removed = true
            }
        }
        if removed { try? store.commit() }
    }

    private static func deleteOurWeekReminders(listID: String?, pushedIDs: Set<String>) async {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        let store = EKEventStore()
        let calendars = store.calendars(for: .reminder)
        let list = calendars.first(where: { $0.calendarIdentifier == listID })
            ?? calendars.first(where: { $0.title.compare("Our Week", options: .caseInsensitive) == .orderedSame })
        var targets: [EKReminder] = []
        if let list {
            let predicate = store.predicateForReminders(in: [list])
            let found: [EKReminder] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { reminders in
                    continuation.resume(returning: reminders ?? [])
                }
            }
            targets = found.filter { reminder in
                reminder.url?.scheme?.lowercased() == "ourweek" || pushedIDs.contains(reminder.calendarItemIdentifier)
            }
        }
        for id in pushedIDs where !targets.contains(where: { $0.calendarItemIdentifier == id }) {
            if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
                targets.append(reminder)
            }
        }
        guard !targets.isEmpty else { return }
        for reminder in targets {
            try? store.remove(reminder, commit: false)
        }
        try? store.commit()
    }

    // MARK: - Files

    private static func deleteFiles() {
        let fm = FileManager.default
        // goals.json and anything else under Application Support/OurWeek.
        // The Core Data stores beside it stay open and were emptied above.
        if let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fm.removeItem(at: support.appendingPathComponent("OurWeek", isDirectory: true))
        }
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            removeContents(of: caches)
        }
        removeContents(of: fm.temporaryDirectory)
        // Widget snapshots, recipe photo thumbnails, share-extension hand-offs.
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: ShareImportStore.appGroupID) {
            let items = (try? fm.contentsOfDirectory(at: group, includingPropertiesForKeys: nil)) ?? []
            for item in items where item.lastPathComponent != "Library" && !isSystemFile(item) {
                try? fm.removeItem(at: item)
            }
            removeContents(of: group.appendingPathComponent("Library/Caches", isDirectory: true))
        }
    }

    private static func removeContents(of folder: URL) {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for item in items where !isSystemFile(item) {
            try? fm.removeItem(at: item)
        }
    }

    /// Container metadata iOS keeps beside the app's files. Never ours to delete.
    private static func isSystemFile(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".com.apple.")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Account row

/// The last row in ••• → Account.
struct DeleteAllDataRow: View {
    @State private var showConfirm = false

    var body: some View {
        Button {
            showConfirm = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .regular))
                Text("Delete all my data")
                    .font(.system(size: 18, weight: .regular, design: .serif))
                Spacer()
            }
            .foregroundStyle(DeleteAllDataSheet.destructive)
            .padding(20)
            .homeQuietCard()
        }
        .sheet(isPresented: $showConfirm) {
            DeleteAllDataSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Confirmation sheet

struct DeleteAllDataSheet: View {
    static let destructive = Color(red: 0.72, green: 0.20, blue: 0.16)

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var isDeleting = false
    @State private var errorText: String?
    @State private var role = HouseholdSharingRole()
    @FocusState private var fieldFocused: Bool

    private var confirmed: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines) == "DELETE"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Delete all my data")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.cardWhite)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    }
                    .accessibilityLabel("Close")
                    .disabled(isDeleting)
                }

                Text("This permanently deletes everything Our Week keeps for you, on this iPhone and in your iCloud. It can't be undone.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HomeQuiet.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    item("Meals and the weekly plan")
                    item("Recipes, including their photos, ratings and cooking history")
                    item("Shopping lists, items and pantry staples")
                    item("Events and to-dos")
                    item("Goals and their history")
                    item("Settings, your profile name and photo")
                    item("Goal reminders and prep-ahead notifications")
                    item("To-dos Our Week added to your Reminders list")
                    item("Events Our Week copied to Apple Calendar")
                    item("Your Gemini API key")
                    item("What the Home Screen widgets show")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .homeQuietCard()

                Text("Events you added to Apple Calendar yourself stay in Apple Calendar.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
                    .fixedSize(horizontal: false, vertical: true)

                if role.ownsSharedHousehold {
                    note(
                        title: "This also removes your household for its members",
                        body: "You share your household. Deleting stops sharing and deletes the household, so everyone you invited loses its meals, recipes, lists and events."
                    )
                }
                if role.joinedHousehold {
                    note(
                        title: "You'll leave the shared household",
                        body: "You'll be removed from \(role.joinedOwnerName.map { "\($0)'s" } ?? "the") household. Its data stays with \(role.joinedOwnerName ?? "its owner") and isn't deleted."
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Type DELETE to confirm")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                    TextField("DELETE", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 17, weight: .regular))
                        .focused($fieldFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.cardWhite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(HomeQuiet.buttonStroke, lineWidth: 1)
                        )
                        .disabled(isDeleting)
                        .accessibilityLabel("Type DELETE to confirm")
                }

                if let errorText {
                    Text(errorText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.terra600)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isDeleting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Deleting…")
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                } else if confirmed {
                    Button(action: deleteNow) {
                        Text(role.ownsSharedHousehold ? "Delete my data and the household" : "Delete all my data")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Self.destructive)
                            .clipShape(Capsule())
                    }
                    .transition(.opacity)
                }
            }
            .padding(24)
            .animation(.easeOut(duration: 0.2), value: confirmed)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.bgBase.ignoresSafeArea())
        .interactiveDismissDisabled(isDeleting)
        .onAppear { role = HouseholdSharingRole.current() }
    }

    private func item(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(Color.terra500)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(HomeQuiet.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func note(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(Self.destructive)
            Text(body)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(HomeQuiet.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.terra50)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func deleteNow() {
        guard confirmed, !isDeleting else { return }
        fieldFocused = false
        errorText = nil
        isDeleting = true
        Task { @MainActor in
            do {
                try await DataDeletion.deleteEverything()
            } catch {
                errorText = error.localizedDescription
                isDeleting = false
            }
        }
    }
}

// MARK: - Done message

struct DataDeletedBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.terra500)
            Text("Your data was deleted")
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.cardWhite)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(HomeQuiet.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }
}
