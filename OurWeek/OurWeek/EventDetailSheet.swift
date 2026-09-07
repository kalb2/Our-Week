//
//  EventDetailSheet.swift
//  OurWeek
//
//  Modal for viewing event details — supports both OurWeek and Apple Calendar events.
//

import SwiftUI

// MARK: - OurWeek Event Detail

struct EventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    
    let event: CalendarEvent
    
    private var timeString: String {
        if event.isAllDay { return "All Day" }
        let f = DateFormatter()
        f.timeStyle = .short
        var s = f.string(from: event.date ?? Date())
        if let end = event.endDate {
            s += " – " + f.string(from: end)
        }
        return s
    }
    
    private var dateString: String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: event.date ?? Date())
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title ?? "Event")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        if event.appleEventID != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Synced to Apple Calendar")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Color.lime500)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.lime100)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                    
                    // Info rows
                    VStack(spacing: 0) {
                        detailRow(
                            icon: "calendar",
                            iconColor: Color.lilac500,
                            title: "Date",
                            value: dateString
                        )
                        
                        Divider().padding(.leading, 56)
                        
                        detailRow(
                            icon: "clock",
                            iconColor: Color.terra500,
                            title: "Time",
                            value: timeString
                        )
                        
                        if let notes = event.notes, !notes.isEmpty {
                            Divider().padding(.leading, 56)
                            
                            detailRow(
                                icon: "note.text",
                                iconColor: Color.sky500,
                                title: "Notes",
                                value: notes
                            )
                        }
                    }
                    .background(Color.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.lilac200, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    
                    Spacer().frame(height: 24)
                    
                    // Delete button
                    Button(role: .destructive) {
                        dataManager.delete(event)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Event")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 20)
                }
            }
            .background(Color.bgBase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lilac500)
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.gray)
                    .tracking(0.5)
                Text(value)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Apple Calendar Event Detail

struct AppleEventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let event: AppleCalendarEvent
    
    private var timeString: String {
        if event.isAllDay { return "All Day" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: event.startDate) + " – " + f.string(from: event.endDate)
    }
    
    private var dateString: String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: event.startDate)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title)
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(uiColor: event.calendarColor))
                                .frame(width: 10, height: 10)
                            Image(systemName: "calendar")
                                .font(.system(size: 10, weight: .bold))
                            Text(event.calendarTitle)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color(uiColor: event.calendarColor))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(uiColor: event.calendarColor).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                    
                    // Info rows
                    VStack(spacing: 0) {
                        detailRow(
                            icon: "calendar",
                            iconColor: Color(uiColor: event.calendarColor),
                            title: "Date",
                            value: dateString
                        )
                        
                        Divider().padding(.leading, 56)
                        
                        detailRow(
                            icon: "clock",
                            iconColor: Color.terra500,
                            title: "Time",
                            value: timeString
                        )
                    }
                    .background(Color.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(uiColor: event.calendarColor).opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    
                    Spacer().frame(height: 16)
                    
                    // Info banner
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.sky500)
                        Text("This event is from Apple Calendar. Edit it in the Calendar app.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.gray)
                    }
                    .padding(14)
                    .background(Color.sky100.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                }
            }
            .background(Color.bgBase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.lilac500)
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.gray)
                    .tracking(0.5)
                Text(value)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
