//
//  SharingManager.swift
//  OurWeek
//
//  Handles CloudKit sharing: creating shares, managing participants,
//  and presenting the system sharing UI.
//

import SwiftUI
import CoreData
import CloudKit
import UIKit

// MARK: - Sharing Manager

@Observable
class SharingManager {
    let persistenceController: PersistenceController

    var isSharing = false
    var shareStatus: ShareStatus = .notShared
    var participants: [Participant] = []
    var connectionBanner: ConnectionBanner?

    /// Timer reference for auto-refreshing share status
    private var refreshTimer: Timer?

    enum ShareStatus {
        case notShared
        case shared
        case pending
    }

    struct Participant: Identifiable {
        let id = UUID()
        let name: String
        let status: AcceptanceStatus
        let role: ParticipantRole
    }

    enum AcceptanceStatus: String {
        case pending = "Pending"
        case accepted = "Connected"
        case removed = "Removed"
        case unknown = "Unknown"
    }

    enum ParticipantRole {
        case owner
        case participant
    }

    struct ConnectionBanner: Identifiable {
        let id = UUID()
        let name: String
        let message: String
    }

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    /// Create or retrieve a CKShare for the given Household
    func share(household: Household) async throws -> (CKShare, CKContainer) {
        // Check for existing share first
        if let existingShare = persistenceController.fetchShare(for: household) {
            let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
            return (existingShare, ckContainer)
        }

        // Create a new share
        let (share, ckContainer) = try await persistenceController.getOrCreateShare(for: household)
        share[CKShare.SystemFieldKey.title] = household.name ?? "Our Week"
        share.publicPermission = .none // Only invited participants

        self.shareStatus = .pending

        return (share, ckContainer)
    }

    /// Update the sharing status for a given Household
    func refreshShareStatus(for household: Household) {
        let previousAccepted = Set(
            participants.filter { $0.status == .accepted && $0.role == .participant }.map { $0.name }
        )

        if let share = persistenceController.fetchShare(for: household) {
            let nonOwners = share.participants.filter { $0.role != .owner }

            participants = nonOwners.map { ckParticipant in
                let name = ckParticipant.userIdentity.nameComponents?.formatted() ?? "Partner"
                let status: AcceptanceStatus
                switch ckParticipant.acceptanceStatus {
                case .accepted:
                    status = .accepted
                case .pending:
                    status = .pending
                case .removed:
                    status = .removed
                case .unknown:
                    status = .unknown
                @unknown default:
                    status = .unknown
                }
                return Participant(name: name, status: status, role: .participant)
            }

            let hasAccepted = participants.contains { $0.status == .accepted }
            let hasPending = participants.contains { $0.status == .pending }

            if hasAccepted {
                shareStatus = .shared
            } else if hasPending || !nonOwners.isEmpty {
                shareStatus = .pending
            } else {
                shareStatus = .notShared
            }

            // Check for newly accepted participants (connection confirmation)
            let newlyAccepted = participants.filter {
                $0.status == .accepted && $0.role == .participant && !previousAccepted.contains($0.name)
            }
            if let first = newlyAccepted.first, !previousAccepted.isEmpty || participants.count > 1 {
                connectionBanner = ConnectionBanner(
                    name: first.name,
                    message: "\(first.name) joined your household!"
                )
            }
        } else if persistenceController.isShared(object: household) {
            shareStatus = .shared
            participants = [Participant(name: "Partner", status: .accepted, role: .participant)]
        } else {
            shareStatus = .notShared
            participants = []
        }
    }

    /// Start automatically refreshing share status every 10 seconds
    func startAutoRefresh(for household: Household) {
        stopAutoRefresh()
        refreshShareStatus(for: household)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.refreshShareStatus(for: household)
        }
    }

    /// Stop the auto-refresh timer
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Dismiss the connection banner
    func dismissBanner() {
        connectionBanner = nil
    }

    // MARK: - Diagnostics

    struct DiagnosticInfo: Identifiable {
        let id = UUID()
        let timestamp: Date
        let iCloudAccountStatus: String
        let iCloudAccountID: String
        let privateStoreExists: Bool
        let sharedStoreExists: Bool
        let privateStoreURL: String
        let sharedStoreURL: String
        let containerType: String
        let householdsInPrivateStore: Int
        let householdsInSharedStore: Int
        let totalHouseholds: Int
        let householdDetails: [HouseholdDiag]
        let shareExists: Bool
        let shareURL: String
        let shareParticipants: [ParticipantDiag]
        let shareOwner: String
        let errors: [String]
    }

    struct HouseholdDiag: Identifiable {
        let id: UUID
        let name: String
        let ownerName: String
        let store: String
        let isShared: Bool
        let hasShare: Bool
        let objectID: String
    }

    struct ParticipantDiag: Identifiable {
        let id = UUID()
        let name: String
        let status: String
        let role: String
        let permission: String
    }

    func runDiagnostics(for household: Household?) async -> DiagnosticInfo {
        let pc = persistenceController
        var errors: [String] = []

        // 1. iCloud account
        let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
        var accountStatusStr = "Unknown"
        var accountIDStr = "Unknown"
        do {
            let status = try await ckContainer.accountStatus()
            switch status {
            case .available: accountStatusStr = "✅ Available"
            case .couldNotDetermine: accountStatusStr = "⚠️ Could Not Determine"
            case .noAccount: accountStatusStr = "❌ No Account"
            case .restricted: accountStatusStr = "❌ Restricted"
            case .temporarilyUnavailable: accountStatusStr = "⚠️ Temporarily Unavailable"
            @unknown default: accountStatusStr = "❓ Unknown (\(status.rawValue))"
            }
        } catch {
            accountStatusStr = "❌ Error: \(error.localizedDescription)"
            errors.append("iCloud check failed: \(error.localizedDescription)")
        }

        do {
            let userID = try await ckContainer.userRecordID()
            accountIDStr = userID.recordName
        } catch {
            accountIDStr = "Error: \(error.localizedDescription)"
        }

        // 2. Persistent stores
        let privateExists = pc.privatePersistentStore != nil
        let sharedExists = pc.sharedPersistentStore != nil
        let privateURL = pc.privatePersistentStore?.url?.lastPathComponent ?? "NOT FOUND"
        let sharedURL = pc.sharedPersistentStore?.url?.lastPathComponent ?? "NOT FOUND"
        let containerType = pc.cloudKitContainer != nil ? "NSPersistentCloudKitContainer ✅" : "NSPersistentContainer ⚠️ (no CloudKit)"

        if !privateExists { errors.append("Private persistent store not found") }
        if !sharedExists { errors.append("Shared persistent store not found") }
        if pc.cloudKitContainer == nil { errors.append("Container is not CloudKit-enabled") }

        // 3. Households across stores
        let viewContext = pc.container.viewContext
        let allRequest: NSFetchRequest<Household> = Household.fetchRequest()
        allRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Household.createdAt, ascending: true)]

        var allHouseholds: [Household] = []
        do {
            allHouseholds = try viewContext.fetch(allRequest)
        } catch {
            errors.append("Failed to fetch households: \(error.localizedDescription)")
        }

        var householdDiags: [HouseholdDiag] = []
        var privateCount = 0
        var sharedCount = 0

        for h in allHouseholds {
            let store = h.objectID.persistentStore
            let storeName: String
            if store == pc.privatePersistentStore {
                storeName = "Private"
                privateCount += 1
            } else if store == pc.sharedPersistentStore {
                storeName = "Shared"
                sharedCount += 1
            } else {
                storeName = "Unknown"
            }

            let hasShare = pc.fetchShare(for: h) != nil

            householdDiags.append(HouseholdDiag(
                id: h.id ?? UUID(),
                name: h.name ?? "(no name)",
                ownerName: h.ownerName ?? "(no owner)",
                store: storeName,
                isShared: pc.isShared(object: h),
                hasShare: hasShare,
                objectID: h.objectID.uriRepresentation().lastPathComponent
            ))
        }

        // 4. Share details
        var shareExists = false
        var shareURLStr = "None"
        var participantDiags: [ParticipantDiag] = []
        var shareOwner = "N/A"

        if let household = household, let share = pc.fetchShare(for: household) {
            shareExists = true
            shareURLStr = share.url?.absoluteString ?? "No URL"

            if let owner = share.owner.userIdentity.nameComponents?.formatted() {
                shareOwner = owner
            } else {
                shareOwner = share.owner.userIdentity.userRecordID?.recordName ?? "Unknown"
            }

            for p in share.participants {
                let name = p.userIdentity.nameComponents?.formatted() ?? p.userIdentity.userRecordID?.recordName ?? "Unknown"
                let statusStr: String
                switch p.acceptanceStatus {
                case .accepted: statusStr = "✅ Accepted"
                case .pending: statusStr = "🟡 Pending"
                case .removed: statusStr = "❌ Removed"
                case .unknown: statusStr = "❓ Unknown"
                @unknown default: statusStr = "❓ Unknown"
                }
                let roleStr: String
                switch p.role {
                case .owner: roleStr = "Owner"
                case .administrator: roleStr = "Administrator"
                case .privateUser: roleStr = "Private User"
                case .publicUser: roleStr = "Public User"
                case .unknown: roleStr = "Unknown"
                @unknown default: roleStr = "Unknown"
                }
                let permStr: String
                switch p.permission {
                case .readWrite: permStr = "Read/Write"
                case .readOnly: permStr = "Read Only"
                case .none: permStr = "None"
                case .unknown: permStr = "Unknown"
                @unknown default: permStr = "Unknown"
                }
                participantDiags.append(ParticipantDiag(
                    name: name, status: statusStr, role: roleStr, permission: permStr
                ))
            }
        }

        return DiagnosticInfo(
            timestamp: Date(),
            iCloudAccountStatus: accountStatusStr,
            iCloudAccountID: accountIDStr,
            privateStoreExists: privateExists,
            sharedStoreExists: sharedExists,
            privateStoreURL: privateURL,
            sharedStoreURL: sharedURL,
            containerType: containerType,
            householdsInPrivateStore: privateCount,
            householdsInSharedStore: sharedCount,
            totalHouseholds: allHouseholds.count,
            householdDetails: householdDiags,
            shareExists: shareExists,
            shareURL: shareURLStr,
            shareParticipants: participantDiags,
            shareOwner: shareOwner,
            errors: errors
        )
    }
}

// MARK: - UICloudSharingController Wrapper for SwiftUI

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let household: Household

    func makeUIViewController(context: Context) -> UICloudSharingController {
        share[CKShare.SystemFieldKey.title] = household.name ?? "Our Week"
        let controller = UICloudSharingController(share: share, container: container)
        controller.modalPresentationStyle = .formSheet
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(
            _ ctr: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            print("CloudKit sharing error: \(error.localizedDescription)")
        }

        func itemTitle(for ctr: UICloudSharingController) -> String? {
            return "Our Week"
        }

        func cloudSharingControllerDidSaveShare(_ ctr: UICloudSharingController) {
            print("Share saved successfully")
        }

        func cloudSharingControllerDidStopSharing(_ ctr: UICloudSharingController) {
            print("Sharing stopped")
        }
    }
}

// MARK: - Share Invitation Sheet Modifier

struct ShareSheetModifier: ViewModifier {
    @Binding var isPresented: Bool
    let share: CKShare?
    let container: CKContainer?
    let household: Household?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                if let share = share, let container = container, let household = household {
                    CloudSharingView(
                        share: share,
                        container: container,
                        household: household
                    )
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Preparing share…")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                    }
                }
            }
    }
}

extension View {
    func shareSheet(
        isPresented: Binding<Bool>,
        share: CKShare?,
        container: CKContainer?,
        household: Household?
    ) -> some View {
        modifier(ShareSheetModifier(
            isPresented: isPresented,
            share: share,
            container: container,
            household: household
        ))
    }
}
