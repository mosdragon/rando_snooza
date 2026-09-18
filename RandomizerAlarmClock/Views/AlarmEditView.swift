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
    @State private var alarmKitStatus: String?


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
                        Text(alarm.soundPoolSummary)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Randomize pitch & speed", isOn: $alarm.randomizePitchAndSpeed)
            } header: {
                Text("Sound")
            } footer: {
                if AlarmScheduler.candidates(for: alarm).isEmpty {
                    Text("Nothing is switched on, so this alarm will ring with the system sound.")
                        .foregroundStyle(.orange)
                } else if alarm.randomizePitchAndSpeed {
                    Text("Each save picks one sound at random and re-renders it with a random pitch and speed from the ranges below.")
                } else {
                    Text("Each save picks one sound at random and plays it as-is.")
                }
            }

            if alarm.randomizePitchAndSpeed {
                RandomizationRangeView(alarm: alarm)
            }

            snoozeSection

            Section {
                Toggle("Enabled", isOn: $alarm.isEnabled)
            }

            testFireSection
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

    // MARK: - Snooze / test sections

    @ViewBuilder
    private var snoozeSection: some View {
        Section {
            Toggle("Snooze", isOn: $alarm.isSnoozeEnabled)

            if alarm.isSnoozeEnabled {
                Stepper(value: $alarm.snoozeMinutes, in: 1...60) {
                    HStack {
                        Text("Snooze length")
                        Spacer()
                        Text("\(alarm.snoozeMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Snooze")
        } footer: {
            if alarm.isSnoozeEnabled {
                Text("Adds a Snooze button to the alarm alert. Tapping it re-triggers the alarm after \(alarm.snoozeMinutes) minute\(alarm.snoozeMinutes == 1 ? "" : "s").")
            } else {
                Text("The alarm alert shows only the system Stop button.")
            }
        }
    }

    @ViewBuilder
    private var testFireSection: some View {
        Section {
            Button {
                testFire()
            } label: {
                Label("Test fire in 20 seconds", systemImage: "bell.badge")
            }
        } footer: {
            if let alarmKitStatus {
                Text(alarmKitStatus)
            } else if didScheduleTest {
                Text("Test scheduled. Lock the phone to see the full-screen alert.")
            } else {
                Text("Fires once with this alarm's current settings, so delivery and snooze can be checked without waiting for the alarm time.")
            }
        }
    }

    private func testFire() {
        alarmKitStatus = nil

        let soundName = AlarmScheduler.soundName(for: alarm)
        let label = alarm.label
        let snooze = alarm.effectiveSnoozeMinutes
        Task {
            let ok = await AlarmKitScheduler.scheduleTestFiring(
                label: label,
                inSeconds: 20,
                soundName: soundName,
                snoozeMinutes: snooze
            )
            await MainActor.run {
                didScheduleTest = ok
                alarmKitStatus = ok
                    ? "Test scheduled for 20 seconds from now (sound: \(soundName ?? "system default"))."
                    : "AlarmKit refused the alarm — check the console for the error."
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
