import SwiftUI

struct AddEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarSyncManager.self) private var calendarSyncManager
    
    let date: Date
    let dataManager: DataManager
    
    @State private var title = ""
    @State private var isAllDay = false
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes = ""
    @State private var color = "lilac500"
    @State private var syncToApple = false
    
    init(date: Date, dataManager: DataManager) {
        self.date = date
        self.dataManager = dataManager
        
        let cal = Calendar.current
        var start = date
        if cal.isDateInToday(date) {
            start = Date()
        }
        
        // Round to next hour
        let roundedStart = cal.date(bySettingHour: cal.component(.hour, from: start) + 1, minute: 0, second: 0, of: start) ?? start
        _startDate = State(initialValue: roundedStart)
        _endDate = State(initialValue: cal.date(byAdding: .hour, value: 1, to: roundedStart) ?? roundedStart)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    
                    Toggle("All-day", isOn: $isAllDay)
                        .tint(Color.lilac500)
                    
                    if isAllDay {
                        DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                        DatePicker("Ends", selection: $endDate, displayedComponents: .date)
                    } else {
                        DatePicker("Starts", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Ends", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                if calendarSyncManager.isSyncEnabled && calendarSyncManager.writeBackCalendarID != nil {
                    Section {
                        Toggle(isOn: $syncToApple) {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundStyle(Color.lilac500)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Add to Apple Calendar")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                    Text("Syncs to your linked calendar")
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(Color.lilac500)
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.terra500)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveEvent()
                    }
                    .bold()
                    .foregroundStyle(Color.lilac500)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveEvent() {
        let event = dataManager.createEvent(
            title: title,
            date: startDate,
            endDate: isAllDay ? nil : endDate,
            notes: notes.isEmpty ? nil : notes,
            color: color,
            isAllDay: isAllDay,
            in: dataManager.currentHousehold
        )
        
        // Sync to Apple Calendar if toggled on
        if syncToApple {
            let appleID = calendarSyncManager.writeEvent(
                title: title,
                startDate: startDate,
                endDate: isAllDay ? nil : endDate,
                isAllDay: isAllDay,
                notes: notes.isEmpty ? nil : notes
            )
            if let appleID {
                event.appleEventID = appleID
                dataManager.save()
            }
        }
        
        dismiss()
    }
}
