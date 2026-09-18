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

    @AppStorage("alarmEngine") private var engineRaw = AlarmEngine.notifications.rawValue
    @AppStorage("alarmKitSoundSource") private var soundSourceRaw = AlarmKitSoundSource.bundled.rawValue

    private var engine: AlarmEngine { AlarmEngine(rawValue: engineRaw) ?? .notifications }
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

            engineSection
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
    private var engineSection: some View {
        Section {
            Picker("Engine", selection: $engineRaw) {
                ForEach(AlarmEngine.allCases) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)

            if engine == .alarmKit {
                Picker("AlarmKit sound", selection: $soundSourceRaw) {
                    ForEach(AlarmKitSoundSource.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }

                if soundSource == .bundled {
                    ForEach(BundledAlarmSound.allCases) { sound in
                        HStack {
                            Text(sound.displayName)
                                .font(.caption)
                            Spacer()
                            Image(systemName: sound.existsInBundle ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(sound.existsInBundle ? .green : .red)
                        }
                    }
                }
            }
        } header: {
            Text("Alarm engine")
        } footer: {
            if engine == .alarmKit {
                Text("AlarmKit shows a full-screen alert and overrides Focus and silent mode. One alarm covers the whole repeat schedule, so the sound is randomized per save rather than per firing.")
            } else {
                Text("Notifications show a banner only, cap the sound at 30 seconds, and are suppressed by Focus / Do Not Disturb.")
            }
        }

        Section {
            Button {
                testFire()
            } label: {
                Label("Test fire in 20 seconds", systemImage: "bell.badge")
            }
            .disabled(engine == .notifications && alarm.soundPool.isEmpty)
        } footer: {
            if let alarmKitStatus {
                Text(alarmKitStatus)
            } else if didScheduleTest {
                Text("Test scheduled. Lock the phone or background the app to see how it presents.")
            } else {
                Text("Fires once, using the engine selected above, so delivery can be confirmed without waiting for the alarm time.")
            }
        }
    }

    private func testFire() {
        alarmKitStatus = nil

        guard engine == .alarmKit else {
            AlarmScheduler.scheduleTestFiring(for: alarm, inSeconds: 20)
            didScheduleTest = true
            return
        }

        let soundName = AlarmRouter.alarmKitSoundName(for: alarm)
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
                    ? "AlarmKit test scheduled for 20 seconds from now (sound: \(soundName ?? "system default"))."
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

        AlarmRouter.reschedule(alarm)

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
