//
//  AlarmEditView.swift
//  RandomizerAlarmClock
//
//  Create or edit a single alarm: time, label, repeat days, sound pool, randomization ranges.
//

import SwiftUI
import SwiftData

struct AlarmEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var alarm: Alarm
    /// True when this alarm was just created for this screen and hasn't been saved yet;
    /// canceling in that case removes it instead of leaving an empty alarm behind.
    let isNew: Bool

    @State private var timeSelection: Date
    @State private var didScheduleTest = false

    init(alarm: Alarm, isNew: Bool = false) {
        self.alarm = alarm
        self.isNew = isNew
        var components = DateComponents()
        components.hour = alarm.hour
        components.minute = alarm.minute
        _timeSelection = State(initialValue: Calendar.current.date(from: components) ?? Date())
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Time", selection: $timeSelection, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }

            Section("Label") {
                TextField("Alarm name", text: $alarm.label)
            }

            Section("Repeat") {
                RepeatDayPicker(selectedDays: $alarm.repeatDays)
            }

            Section {
                NavigationLink {
                    SoundPoolPickerView(alarm: alarm)
                } label: {
                    HStack {
                        Text("Sound pool")
                        Spacer()
                        Text("\(alarm.soundPool.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if alarm.soundPool.isEmpty {
                    Text("Pick at least one sound or this alarm won't be scheduled.")
                        .foregroundStyle(.orange)
                }
            }

            RandomizationRangeView(alarm: alarm)

            Section {
                Toggle("Enabled", isOn: $alarm.isEnabled)
            }

            Section {
                Button {
                    AlarmScheduler.scheduleTestFiring(for: alarm, inSeconds: 15)
                    didScheduleTest = true
                } label: {
                    Label("Test fire in 15 seconds", systemImage: "bell.badge")
                }
                .disabled(alarm.soundPool.isEmpty)
            } footer: {
                Text(didScheduleTest
                     ? "Test scheduled. Background the app or lock the phone to see it as a banner."
                     : "Schedules a one-off notification using this alarm's sound pool, so you can confirm delivery without waiting for the alarm time.")
            }
        }
        .navigationTitle(isNew ? "New Alarm" : "Edit Alarm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { cancel() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: timeSelection)
        alarm.hour = components.hour ?? alarm.hour
        alarm.minute = components.minute ?? alarm.minute

        if isNew {
            modelContext.insert(alarm)
        }

        AlarmScheduler.log.info("Saving alarm \(alarm.id.uuidString, privacy: .public): \(alarm.soundPool.count) sound(s) in pool, enabled=\(alarm.isEnabled), repeatDays=\(String(describing: alarm.repeatDays), privacy: .public)")

        do {
            try modelContext.save()
        } catch {
            AlarmScheduler.log.error("Saving alarm before scheduling failed: \(error.localizedDescription, privacy: .public)")
        }

        AlarmScheduler.reschedule(alarm)

        do {
            try modelContext.save()
        } catch {
            AlarmScheduler.log.error("Saving alarm after scheduling failed: \(error.localizedDescription, privacy: .public)")
        }
        dismiss()
    }

    private func cancel() {
        if isNew {
            modelContext.delete(alarm)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        AlarmEditView(alarm: Alarm(), isNew: true)
    }
    .modelContainer(for: [Alarm.self, AudioFile.self], inMemory: true)
}
