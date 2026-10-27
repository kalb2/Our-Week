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
    @State private var calendarSyncManager = CalendarSyncManager()
    @State private var remindersSync = RemindersSync()
    /// Changes after "Delete all my data" so every view starts fresh.
    @State private var resetID = UUID()
    @State private var showDataDeleted = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(resetID)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environment(SharingManager(persistenceController: persistenceController))
                .environment(DataManager(persistenceController: persistenceController))
                .environment(calendarSyncManager)
                .environment(remindersSync)
                .overlay(alignment: .top) {
                    if showDataDeleted {
                        DataDeletedBanner()
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .ourWeekDataDeleted)) { _ in
                    calendarSyncManager = CalendarSyncManager()
                    remindersSync = RemindersSync()
                    resetID = UUID()
                    withAnimation(.easeOut(duration: 0.25)) { showDataDeleted = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation(.easeIn(duration: 0.25)) { showDataDeleted = false }
                    }
                }
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
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let url = connectionOptions.urlContexts.first?.url {
            DispatchQueue.main.async {
                Self.route(url)
            }
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            let url = context.url
            DispatchQueue.main.async {
                Self.route(url)
            }
        }
    }

    private static func route(_ url: URL) {
        if url.scheme?.lowercased() == "ourweek" {
            let host = url.host?.lowercased()
            if host == "recipe", let id = UUID(uuidString: url.lastPathComponent) {
                RecipeOpenRoute.pendingRecipeID = id
                NotificationCenter.default.post(name: RecipeOpenRoute.didArrive, object: nil)
            } else if host == "home" || host == "todo" {
                NotificationCenter.default.post(name: .ourWeekOpenHome, object: nil)
            } else if host == "goals" {
                GoalReminderRoute.openGoals = true
                NotificationCenter.default.post(name: .ourWeekOpenGoals, object: nil)
            } else {
                NotificationCenter.default.post(name: ShareImportStore.didArrive, object: nil)
            }
            return
        }
        RecipePackOpenHandler.handle(url: url)
    }

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
