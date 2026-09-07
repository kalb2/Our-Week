//
//  OurWeekApp.swift
//  OurWeek
//
//  Created by Kaleb Jensen on 2/12/26.
//

import SwiftUI
import CoreData
import CloudKit

@main
struct OurWeekApp: App {
    let persistenceController = PersistenceController.shared

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(SharingManager(persistenceController: persistenceController))
                .environment(DataManager(persistenceController: persistenceController))
                .environment(CalendarSyncManager())
        }
    }
}

// MARK: - App Delegate for CloudKit Share Acceptance

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }
}

class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let persistence = PersistenceController.shared

        guard let ckContainer = persistence.cloudKitContainer else {
            print("Error: CloudKit container not available")
            return
        }

        guard let sharedStore = persistence.sharedPersistentStore else {
            print("Error: Shared persistent store not found")
            return
        }

        ckContainer.acceptShareInvitations(
            from: [cloudKitShareMetadata],
            into: sharedStore
        ) { shareMetadatas, error in
            if let error = error {
                print("Error accepting share: \(error.localizedDescription)")
            } else {
                print("Successfully accepted CloudKit share invitation")
            }
        }
    }
}
