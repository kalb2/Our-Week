//
//  Persistence.swift
//  OurWeek
//
//  Created by Kaleb Jensen on 2/12/26.
//

import CoreData
import CloudKit

struct PersistenceController {
    static let shared = PersistenceController()

    // CloudKit container identifier (matches entitlements)
    static let cloudKitContainerID = "iCloud.com.kalebjensen.OurWeek"

    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // Seed a sample Household
        let household = Household(context: viewContext)
        household.id = UUID()
        household.name = "Our Home"
        household.ownerName = "Alex"
        household.createdAt = Date()

        // Seed sample events
        let event = CalendarEvent(context: viewContext)
        event.id = UUID()
        event.title = "Work Meeting"
        event.date = Date()
        event.isAllDay = false
        event.household = household

        // Seed sample meal plan
        let meal = MealPlan(context: viewContext)
        meal.id = UUID()
        meal.title = "Pasta Night"
        meal.date = Date()
        meal.mealType = "dinner"
        meal.household = household

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    // Track whether we're running in-memory (previews/tests) to skip CloudKit operations
    let isInMemory: Bool

    // MARK: - Store References

    /// The persistent store that mirrors the user's private CloudKit database
    var privatePersistentStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            guard let url = store.url else { return false }
            return url.lastPathComponent == "private.sqlite"
        }
    }

    /// The persistent store that mirrors the shared CloudKit database
    var sharedPersistentStore: NSPersistentStore? {
        container.persistentStoreCoordinator.persistentStores.first { store in
            guard let url = store.url else { return false }
            return url.lastPathComponent == "shared.sqlite"
        }
    }

    /// Convenience accessor to cast to CloudKit container (only valid when NOT inMemory)
    var cloudKitContainer: NSPersistentCloudKitContainer? {
        container as? NSPersistentCloudKitContainer
    }

    // MARK: - Initialization

    init(inMemory: Bool = false) {
        self.isInMemory = inMemory

        if inMemory {
            // For previews / testing — use a plain NSPersistentContainer (no CloudKit)
            let plainContainer = NSPersistentContainer(name: "OurWeek")
            plainContainer.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
            plainContainer.loadPersistentStores { _, error in
                if let error = error as NSError? {
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            }
            self.container = plainContainer
        } else {
            // Production: dual-store architecture (private + shared)
            let ckContainer = NSPersistentCloudKitContainer(name: "OurWeek")

            guard let storeDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                fatalError("Cannot find Application Support directory")
            }

            // --- Private Store ---
            let privateStoreURL = storeDirectory.appendingPathComponent("private.sqlite")
            let privateDescription = NSPersistentStoreDescription(url: privateStoreURL)
            privateDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID
            )
            privateDescription.cloudKitContainerOptions?.databaseScope = .private
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            privateDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            // --- Shared Store ---
            let sharedStoreURL = storeDirectory.appendingPathComponent("shared.sqlite")
            let sharedDescription = NSPersistentStoreDescription(url: sharedStoreURL)
            sharedDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: Self.cloudKitContainerID
            )
            sharedDescription.cloudKitContainerOptions?.databaseScope = .shared
            sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

            ckContainer.persistentStoreDescriptions = [privateDescription, sharedDescription]

            ckContainer.loadPersistentStores { description, error in
                if let error = error as NSError? {
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            }
            self.container = ckContainer
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Pin the view context to the current query generation for consistency
        // (only needed for production — preview uses a plain container)
        if !inMemory {
            do {
                try container.viewContext.setQueryGenerationFrom(.current)
            } catch {
                fatalError("Failed to pin viewContext to the current generation: \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// Check if a managed object lives in the shared store
    func isShared(object: NSManagedObject) -> Bool {
        guard let persistentStore = object.objectID.persistentStore else { return false }
        return persistentStore == sharedPersistentStore
    }

    /// Check if a managed object is shared (has an associated CKShare)
    func isShared(objectID: NSManagedObjectID) -> Bool {
        guard let ckContainer = cloudKitContainer else { return false }
        var isShared = false
        if let persistentStore = objectID.persistentStore {
            do {
                let shares = try ckContainer.fetchShares(matching: [objectID])
                isShared = shares.first != nil
            } catch {
                print("Failed to fetch shares: \(error)")
            }
            // Also check if it's in the shared store
            if !isShared {
                isShared = persistentStore == sharedPersistentStore
            }
        }
        return isShared
    }

    /// Fetch the CKShare for a given managed object, if one exists
    func fetchShare(for object: NSManagedObject) -> CKShare? {
        guard let ckContainer = cloudKitContainer else { return nil }
        do {
            let shares = try ckContainer.fetchShares(matching: [object.objectID])
            return shares[object.objectID]
        } catch {
            print("Failed to fetch share: \(error)")
            return nil
        }
    }

    func fetchShare(forObjectID objectID: NSManagedObjectID) async -> CKShare? {
        guard let ckContainer = cloudKitContainer else { return nil }
        do {
            let shares = try ckContainer.fetchShares(matching: [objectID])
            return shares[objectID]
        } catch {
            print("Failed to fetch share: \(error)")
            return nil
        }
    }

    /// Get a CKShare for a Household, creating one if needed
    func getOrCreateShare(for household: Household) async throws -> (CKShare, CKContainer) {
        guard let ckContainer = cloudKitContainer else {
            throw NSError(domain: "PersistenceController", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "CloudKit is not available in this configuration"
            ])
        }
        let (_, share, container) = try await ckContainer.share(
            [household],
            to: nil
        )
        share[CKShare.SystemFieldKey.title] = household.name ?? "Our Week"
        return (share, container)
    }
}
