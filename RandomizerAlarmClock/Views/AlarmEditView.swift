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

    @AppStorage(AlarmScheduler.soundSourceKey) private var soundSourceRaw = AlarmKitSoundSource.bundled.rawValue

    private var soundSource: AlarmKitSoundSource { AlarmKitSoundSource(rawValue: soundSourceRaw) ?? .bundled }

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

            soundSection
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

    // MARK: - Engine / test section

    @ViewBuilder
    private var soundSection: some View {
        Section {
            Picker("Alarm sound", selection: $soundSourceRaw) {
                ForEach(AlarmKitSoundSource.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }

            if soundSource == .bundled {
                if BundledAlarmSound.all.isEmpty {
                    Label("No sounds in the app bundle", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else {
                    ForEach(BundledAlarmSound.all) { sound in
                        HStack {
                            Text(sound.displayName)
                            Spacer()
                            Text(sound.fileName)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        } header: {
            Text("Alarm sound")
        } footer: {
            switch soundSource {
            case .bundled:
                if BundledAlarmSound.all.isEmpty {
                    Text("No .caf files were found in the bundle. Run tools/make_alarm_sound.py to add one, then `xcodegen generate` and rebuild.")
                        .foregroundStyle(.red)
                } else {
                    Text("One of the bundled songs is picked at random each time the alarm is saved.")
                }
            case .randomizedRender:
                Text("Renders a fresh take with randomized pitch and speed into Library/Sounds each time the alarm is saved, using this alarm's sound pool — or a bundled song if the pool is empty.")
            case .systemDefault:
                Text("The system alarm sound. Useful for isolating whether a problem is the sound file or the scheduling.")
            }
        }

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
                Text("Fires once, so delivery can be confirmed without waiting for the alarm time.")
            }
        }
    }

    private func testFire() {
        alarmKitStatus = nil

        let soundName = AlarmScheduler.soundName(for: alarm)
        let label = alarm.label
        Task {
            let ok = await AlarmKitScheduler.scheduleTestFiring(
                label: label,
                inSeconds: 20,
                soundName: soundName
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
