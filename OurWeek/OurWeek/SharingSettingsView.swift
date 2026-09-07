//
//  SharingSettingsView.swift
//  OurWeek
//
//  UI for creating a Household, inviting a partner,
//  and managing sharing status.
//

import SwiftUI
import CloudKit
import CoreData
import PhotosUI

struct SharingSettingsView: View {
    @Environment(DataManager.self) var dataManager
    @Environment(SharingManager.self) var sharingManager
    @Environment(\.managedObjectContext) private var viewContext

    @AppStorage("userProfileName") private var profileName = ""
    @AppStorage("profileImageData") private var profileImageData: Data?

    @State private var householdName = ""
    @State private var showShareSheet = false
    @State private var activeShare: CKShare?
    @State private var activeContainer: CKContainer?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showDebugConsole = false
    @State private var householdToMerge: Household?
    @State private var showMergeConfirmation = false
    @State private var showLeaveConfirmation = false
    @State private var householdToLeave: Household?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "house.2.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.lilac500, Color.terra500],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.bottom, 8)

                        Text("Household Sharing")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))

                        Text("Sync calendars, meals, recipes & more")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    // Connection banner
                    if let banner = sharingManager.connectionBanner {
                        connectionBannerView(banner)
                    }

                    // Profile name card (always visible)
                    profileNameCard

                    if let household = dataManager.currentHousehold {
                        // Existing household card
                        householdCard(household)
                    } else {
                        // Create household card
                        createHouseholdCard
                    }

                    if dataManager.allHouseholds.count > 1 {
                        multipleHouseholdsSection
                    }

                    // Shared data info
                    sharedDataInfo
                    
                    // AI Settings Link
                    aiSettingsLink

                    // Connection Doctor button
                    Button {
                        showDebugConsole = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 11))
                            Text("Connection Doctor")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(Color.bgBase)
            .navigationBarTitleDisplayMode(.inline)
            .shareSheet(
                isPresented: $showShareSheet,
                share: activeShare,
                container: activeContainer,
                household: dataManager.currentHousehold
            )
            .onChange(of: showShareSheet) { _, isShown in
                if let household = dataManager.currentHousehold {
                    if isShown {
                        sharingManager.stopAutoRefresh()
                    } else {
                        sharingManager.startAutoRefresh(for: household)
                    }
                }
            }
            .sheet(isPresented: $showDebugConsole) {
                ConnectionDoctorView(
                    sharingManager: sharingManager,
                    household: dataManager.currentHousehold
                )
            }
            .alert("Merge Households?", isPresented: $showMergeConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Merge & Delete", role: .destructive) {
                    if let source = householdToMerge, let target = dataManager.currentHousehold {
                        dataManager.mergeHousehold(from: source, to: target)
                    }
                }
            } message: {
                Text("This will copy all recipes, meals, events, and lists from the selected household into your active household. The selected household will then be deleted. This cannot be undone.")
            }
            .alert("Leave Household?", isPresented: $showLeaveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("How to Leave") {
                    if let hh = householdToLeave {
                        dataManager.switchHousehold(to: hh)
                        // Trigger manage sharing to allow users to legally remove themselves
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            initiateSharing(household: hh)
                        }
                    }
                }
            } message: {
                Text("To safely leave this shared household, we will switch you to it and open the 'Manage Sharing' menu. From there, select your name and tap 'Remove Me'.")
            }
        }
    }

    // MARK: - Connection Banner

    @ViewBuilder
    func connectionBannerView(_ banner: SharingManager.ConnectionBanner) -> some View {
        HStack(spacing: 12) {
            Text("🎉")
                .font(.system(size: 28))

            VStack(alignment: .leading, spacing: 2) {
                Text("Partner Connected!")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                Text(banner.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3)) {
                    sharingManager.dismissBanner()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.lime400.opacity(0.2), Color.lime500.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.lime500, lineWidth: 2)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Profile Name Card

    var profileNameCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.lilac500, Color.terra500],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Your Profile")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))

                Spacer()

                if !profileName.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.lime500)
                        .font(.system(size: 16))
                }
            }

            HStack(spacing: 16) {
                AvatarButton(imageData: profileImageData)
                    .scaleEffect(1.2)
                    .padding(.leading, 8)
                    .padding(.trailing, 4)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Enter your name", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15, weight: .medium, design: .rounded))

                    HStack(spacing: 16) {
                        Button {
                            showPhotoPicker = true
                        } label: {
                            Text("Change Picture")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.terra600)
                        }

                        if profileImageData != nil {
                            Button(role: .destructive) {
                                profileImageData = nil
                            } label: {
                                Text("Remove")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            profileImageData = data
                        }
                    }
                }
            }

            Text("This is how your partner will see you.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(profileName.isEmpty ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }

    // MARK: - Household Card

    @ViewBuilder
    func householdCard(_ household: Household) -> some View {
        VStack(spacing: 16) {
            // Household info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(household.name ?? "Our Home")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text("Created by \(household.ownerName ?? "You")")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Status badge
                statusBadge
            }

            Divider()

            // Share button
            Button(action: { initiateSharing(household: household) }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: sharingManager.shareStatus == .notShared
                              ? "person.badge.plus" : "person.2.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(sharingManager.shareStatus == .notShared
                         ? "Invite Partner" : "Manage Sharing")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color.lilac500, Color.lilac600],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.lilac600, lineWidth: 2)
                )
            }
            .disabled(isLoading)
            .boldShadow(Color.lilac400, radius: 12)

            // Participants
            if !sharingManager.participants.isEmpty {
                participantsSection
            }

            // Error
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.lilac500, lineWidth: 2)
        )
        .boldShadow(Color.lilac400)
        .onAppear {
            sharingManager.startAutoRefresh(for: household)
        }
        .onDisappear {
            sharingManager.stopAutoRefresh()
        }
    }

    // MARK: - Participants Section

    var participantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEMBERS")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)

            ForEach(sharingManager.participants) { participant in
                HStack(spacing: 10) {
                    // Status indicator dot
                    Circle()
                        .fill(participantStatusColor(participant.status))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(participantStatusColor(participant.status).opacity(0.3), lineWidth: 3)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text(participant.status == .pending ? "Waiting for response…" : participant.name)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(participant.status == .pending ? .secondary : .primary)

                        Text(participant.status.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(participantStatusColor(participant.status))
                    }

                    Spacer()

                    // Status icon
                    Image(systemName: participantStatusIcon(participant.status))
                        .foregroundStyle(participantStatusColor(participant.status))
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.vertical, 6)
            }
        }
    }

    func participantStatusColor(_ status: SharingManager.AcceptanceStatus) -> Color {
        switch status {
        case .accepted: return Color.lime500
        case .pending: return Color.orange
        case .removed: return Color.red
        case .unknown: return Color.gray
        }
    }

    func participantStatusIcon(_ status: SharingManager.AcceptanceStatus) -> String {
        switch status {
        case .accepted: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        case .removed: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var statusBadge: some View {
        Group {
            switch sharingManager.shareStatus {
            case .shared:
                Label("Synced", systemImage: "checkmark.icloud.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.lime500)
                    .clipShape(Capsule())
            case .pending:
                Label("Pending", systemImage: "clock.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .clipShape(Capsule())
            case .notShared:
                Label("Private", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Create Household Card

    var createHouseholdCard: some View {
        VStack(spacing: 16) {
            Text("Create Your Household")
                .font(.system(size: 18, weight: .heavy, design: .rounded))

            Text("Set up a household to start sharing data with your partner.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                TextField("Household Name", text: $householdName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
            }

            if profileName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                    Text("Set your profile name above first")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button(action: createHousehold) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Create Household")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.terra500)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.terra600, lineWidth: 2)
                )
            }
            .disabled(householdName.isEmpty || profileName.isEmpty)
            .opacity(householdName.isEmpty || profileName.isEmpty ? 0.5 : 1.0)
            .boldShadow(Color.terra500, radius: 12)
        }
        .padding(20)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.terra500, lineWidth: 2)
        )
        .boldShadow(Color.terra500)
    }

    // MARK: - Shared Data Info

    @AppStorage("lastCloudKitSyncDate") private var lastSyncTimestamp: Double = 0
    
    var lastSyncDate: Date? {
        guard lastSyncTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: lastSyncTimestamp)
    }

    private var syncDateFormatted: String {
        guard let date = lastSyncDate else { return "Waiting for first sync..." }
        if Calendar.current.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today at \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    var sharedDataInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                Text("WHAT GETS SHARED")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Show last sync time if it's connected
                if sharingManager.shareStatus == .shared || sharingManager.shareStatus == .pending {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text(syncDateFormatted)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 8) {
                sharedDataRow(icon: "calendar", text: "Calendar Events", color: Color.lilac500)
                sharedDataRow(icon: "fork.knife", text: "Meal Plans", color: Color.terra500)
                sharedDataRow(icon: "book.fill", text: "Recipes", color: Color.sky500)
                sharedDataRow(icon: "bag.fill", text: "Shopping Lists", color: Color.lime500)
            }
        }
        .padding(16)
        .background(Color.cardWhite.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    func sharedDataRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI Settings Link
    
    var aiSettingsLink: some View {
        NavigationLink {
            AISettingsView()
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    LinearGradient(
                        colors: [Color.lilac500, Color.sky500],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 1.5))
                .boldShadow(.black, size: 2, radius: 12)
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Features")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Powered by Google Gemini")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Status / Chevron
                HStack(spacing: 8) {
                    if KeychainManager.hasGeminiAPIKey() {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.lime500)
                            .font(.system(size: 14))
                    } else {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }
            .padding(16)
            .background(Color.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black, lineWidth: 2))
            .boldShadow(.black, size: 3, radius: 16)
        }
    }

    // MARK: - Multiple Households Section

    var multipleHouseholdsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR HOUSEHOLDS")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)
            
            Text("You are a member of multiple households. Select one to make it active. Long-press to delete an unused one.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(dataManager.allHouseholds) { hh in
                Button {
                    withAnimation {
                        dataManager.switchHousehold(to: hh)
                    }
                } label: {
                    HStack(spacing: 12) {
                        let isShared = sharingManager.persistenceController.isShared(object: hh)
                        let isOwner = dataManager.isOwner(of: hh)
                        
                        householdAvatarStack(for: hh, isOwner: isOwner, isShared: isShared)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(hh.name ?? "Our Home")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if isShared && !isOwner {
                                    Text("Shared with you")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                } else if isShared && isOwner {
                                    Text("Shared by you")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                } else {
                                    Text("Private Account")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                }
                                
                                if !isOwner {
                                    Text("• By \(hh.ownerName ?? "Unknown")")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                }
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if dataManager.currentHousehold == hh {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.lime500)
                                .font(.system(size: 22))
                        } else {
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                                .frame(width: 22, height: 22)
                        }
                    }
                    .padding(16)
                    .background(Color.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(dataManager.currentHousehold == hh ? Color.lime500 : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if dataManager.allHouseholds.count > 1, let active = dataManager.currentHousehold {
                        if hh != active {
                            Button {
                                householdToMerge = hh
                                showMergeConfirmation = true
                            } label: {
                                Label("Merge into Active Household", systemImage: "arrow.triangle.merge")
                            }
                            
                            Divider()
                        }
                        
                        let isOwner = dataManager.isOwner(of: hh)
                        
                        if isOwner {
                            Button(role: .destructive) {
                                withAnimation {
                                    dataManager.deleteHousehold(hh)
                                }
                            } label: {
                                Label("Delete Household", systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) {
                                householdToLeave = hh
                                showLeaveConfirmation = true
                            } label: {
                                Label("Leave Household", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func householdAvatarStack(for hh: Household, isOwner: Bool, isShared: Bool) -> some View {
        HStack(spacing: -8) {
            // Partner/Owner Avatar
            if isShared {
                if !isOwner {
                    // The Owner's initial
                    let initial = String(hh.ownerName?.prefix(1) ?? "P").uppercased()
                    Circle()
                        .fill(
                            LinearGradient(colors: [Color.sky200, Color.sky400], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 36, height: 36)
                        .overlay(Text(initial).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Color.white))
                        .overlay(Circle().stroke(Color.cardWhite, lineWidth: 2))
                } else {
                    // A partner icon (since we don't store partner names reliably)
                    Circle()
                        .fill(
                            LinearGradient(colors: [Color.sky200, Color.sky400], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(Color.white).font(.system(size: 16)))
                        .overlay(Circle().stroke(Color.cardWhite, lineWidth: 2))
                }
            }
            
            // Your Avatar
            if let imageData = profileImageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.cardWhite, lineWidth: 2))
            } else {
                let initial = String(profileName.prefix(1)).uppercased()
                Circle()
                    .fill(
                        LinearGradient(colors: [Color.terra300, Color.terra500], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 36, height: 36)
                    .overlay(Text(initial.isEmpty ? "U" : initial).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Color.white))
                    .overlay(Circle().stroke(Color.cardWhite, lineWidth: 2))
            }
        }
    }

    // MARK: - Actions

    func createHousehold() {
        let _ = dataManager.createHousehold(name: householdName, ownerName: profileName)
        householdName = ""
    }

    func initiateSharing(household: Household) {
        isLoading = true
        errorMessage = nil

        Task {
            // Check iCloud account status first
            let ckContainer = CKContainer(identifier: PersistenceController.cloudKitContainerID)
            let accountStatus = try? await ckContainer.accountStatus()

            if accountStatus != .available {
                await MainActor.run {
                    errorMessage = "Please sign in to iCloud in Settings to share your household."
                    isLoading = false
                }
                return
            }

            do {
                let (share, container) = try await sharingManager.share(household: household)
                await MainActor.run {
                    activeShare = share
                    activeContainer = container
                    isLoading = false
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create share: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Connection Doctor

struct ConnectionDoctorView: View {
    let sharingManager: SharingManager
    let household: Household?
    @Environment(\.dismiss) private var dismiss
    @State private var diagnostics: SharingManager.DiagnosticInfo?
    @State private var isRunning = true

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    if isRunning {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Diagnosing Connection...")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    } else if let diag = diagnostics {
                        diagnosticResults(diag)
                    }
                }
                .padding(20)
            }
            .background(Color.bgBase)
            .navigationTitle("Connection Doctor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: runDiag) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .disabled(isRunning)
                }
            }
            .task {
                runDiag()
            }
        }
    }

    func runDiag() {
        isRunning = true
        Task {
            let result = await sharingManager.runDiagnostics(for: household)
            // Add slight delay for smoother UI transition
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                diagnostics = result
                isRunning = false
            }
        }
    }

    @ViewBuilder
    func diagnosticResults(_ diag: SharingManager.DiagnosticInfo) -> some View {
        // 1. Overall Status
        let isHealthy = diag.errors.isEmpty && diag.iCloudAccountStatus.contains("Available")
        
        VStack(spacing: 12) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(isHealthy ? Color.lime500 : Color.orange)
            
            Text(isHealthy ? "Connection Healthy" : "Issues Detected")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
            
            Text("Your app is \(isHealthy ? "properly configured for syncing." : "experiencing problems syncing data.")")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)

        // Errors (only if present)
        if !diag.errors.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("ERRORS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.red)
                
                ForEach(diag.errors, id: \.self) { error in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.red)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }

        // 2. iCloud connection
        statusCard(
            title: "iCloud Account",
            icon: "icloud.fill",
            color: Color.sky500,
            items: [
                ("Status", diag.iCloudAccountStatus.contains("Available") ? "Connected" : diag.iCloudAccountStatus, diag.iCloudAccountStatus.contains("Available") ? .green : .red),
                ("Account ID", String(diag.iCloudAccountID.prefix(15)) + "...", .primary)
            ]
        )

        // 3. Database Stores
        let storesOkay = diag.privateStoreExists && diag.sharedStoreExists
        statusCard(
            title: "Database Syncing",
            icon: "externaldrive.fill.badge.icloud",
            color: Color.lilac500,
            items: [
                ("Private Store", diag.privateStoreExists ? "Ready" : "Missing", diag.privateStoreExists ? .green : .red),
                ("Shared Store", diag.sharedStoreExists ? "Ready" : "Missing", diag.sharedStoreExists ? .green : .red),
                ("Local Households", "\(diag.totalHouseholds) total", .primary)
            ]
        )

        // 4. Share Participants
        if diag.shareExists {
            VStack(alignment: .leading, spacing: 12) {
                Text("CURRENT SHARE")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 0) {
                    // Owner Row
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                            .foregroundStyle(Color.terra500)
                            .frame(width: 24)
                        Text(diag.shareOwner)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("Owner")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.terra100)
                            .foregroundStyle(Color.terra600)
                            .clipShape(Capsule())
                    }
                    .padding(16)
                    
                    if !diag.shareParticipants.isEmpty {
                        Divider()
                    }
                    
                    ForEach(Array(diag.shareParticipants.enumerated()), id: \.offset) { index, p in
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color.lilac500)
                                .frame(width: 24)
                            Text(p.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Spacer()
                            
                            let isAccepted = p.status.contains("Accepted")
                            Text(isAccepted ? "Connected" : "Pending")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isAccepted ? Color.lime100 : Color.orange.opacity(0.15))
                                .foregroundStyle(isAccepted ? Color.lime500 : Color.orange)
                                .clipShape(Capsule())
                        }
                        .padding(16)
                        
                        if index < diag.shareParticipants.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color.cardWhite)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
        }
        
        Text("Diagnostics logged at \(diag.timestamp.formatted(date: .omitted, time: .standard))")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
    }

    @ViewBuilder
    func statusCard(title: String, icon: String, color: Color, items: [(String, String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack {
                        if index == 0 {
                            Image(systemName: icon)
                                .foregroundStyle(color)
                                .frame(width: 24)
                        } else {
                            Spacer().frame(width: 24)
                        }
                        Text(item.0)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.1)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(item.2)
                    }
                    .padding(16)
                    
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
            .background(Color.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        }
    }
}
