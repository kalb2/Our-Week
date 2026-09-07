//
//  CalendarSettingsView.swift
//  OurWeek
//
//  Settings UI for Apple Calendar integration.
//

import SwiftUI
import EventKit

struct CalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarSyncManager.self) private var syncManager

    var body: some View {
        NavigationStack {
            List {
                // Sync toggle + status
                syncStatusSection

                // Calendar selection
                if syncManager.isSyncEnabled &&
                   syncManager.authorizationStatus == .fullAccess {
                    calendarSelectionSection
                    writeBackSection
                }
            }
            .navigationTitle("Calendar Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lilac500)
                }
            }
        }
        .onAppear {
            syncManager.refreshAuthorizationStatus()
            if syncManager.authorizationStatus == .fullAccess {
                syncManager.loadCalendars()
            }
        }
    }

    // MARK: - Sync Status Section

    @ViewBuilder
    private var syncStatusSection: some View {
        Section {
            @Bindable var sm = syncManager

            Toggle(isOn: $sm.isSyncEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.lilac500)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Calendar Sync")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Show events from Apple Calendar")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(Color.lilac500)
            .onChange(of: syncManager.isSyncEnabled) { _, isOn in
                if isOn {
                    Task {
                        await syncManager.requestAccess()
                    }
                }
            }

            // Permission status
            if syncManager.isSyncEnabled {
                permissionStatusRow
            }
        } header: {
            Text("Sync")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.lilac500)
        }
    }

    @ViewBuilder
    private var permissionStatusRow: some View {
        switch syncManager.authorizationStatus {
        case .fullAccess:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.lime500)
                Text("Calendar access granted")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }

        case .denied, .restricted:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.terra500)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Calendar access denied")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Text("Open Settings to grant access")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.lilac500)
            }

        case .notDetermined:
            Button {
                Task { await syncManager.requestAccess() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Color.lilac400)
                    Text("Tap to grant calendar access")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
            }

        case .writeOnly:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.terra500)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Only write access granted")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    Text("Full access is needed to read events. Open Settings to update.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.lilac500)
            }

        @unknown default:
            EmptyView()
        }
    }

    // MARK: - Calendar Selection Section

    @ViewBuilder
    private var calendarSelectionSection: some View {
        Section {
            let grouped = Dictionary(grouping: syncManager.availableCalendars) { $0.accountName }
            let sortedKeys = grouped.keys.sorted()

            ForEach(sortedKeys, id: \.self) { account in
                if let calendars = grouped[account] {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(account.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.gray)
                            .tracking(0.5)
                            .padding(.vertical, 4)

                        ForEach(calendars) { cal in
                            calendarRow(cal)
                        }
                    }
                }
            }

            if syncManager.availableCalendars.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading calendars…")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Show Events From")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.lilac500)
        } footer: {
            Text("Selected calendars will appear in your weekly view.")
                .font(.system(size: 11, design: .rounded))
        }
    }

    @ViewBuilder
    private func calendarRow(_ cal: SelectableCalendar) -> some View {
        let isSelected = syncManager.selectedCalendarIDs.contains(cal.id)
        Button {
            var ids = syncManager.selectedCalendarIDs
            if isSelected {
                ids.remove(cal.id)
            } else {
                ids.insert(cal.id)
            }
            syncManager.selectedCalendarIDs = ids
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(uiColor: cal.color))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.15), lineWidth: 1)
                    )

                Text(cal.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.lilac500)
                        .font(.system(size: 18))
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.gray.opacity(0.3))
                        .font(.system(size: 18))
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Write-Back Section

    @ViewBuilder
    private var writeBackSection: some View {
        Section {
            ForEach(syncManager.availableCalendars) { cal in
                let isSelected = syncManager.writeBackCalendarID == cal.id
                Button {
                    syncManager.writeBackCalendarID = cal.id
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(uiColor: cal.color))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle().stroke(Color.black.opacity(0.15), lineWidth: 1)
                            )

                        Text(cal.title)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.terra500)
                                .font(.system(size: 18))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Write Events To")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.terra500)
        } footer: {
            Text("Events you create in OurWeek with sync enabled will be added to this calendar.")
                .font(.system(size: 11, design: .rounded))
        }
    }
}
