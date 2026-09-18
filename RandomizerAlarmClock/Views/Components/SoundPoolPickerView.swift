//
//  SoundPoolPickerView.swift
//  RandomizerAlarmClock
//
//  One alarm's sound pool. Bundled songs and imported library files live in the same pool —
//  the alarm draws at random from whatever is switched on here.
//

import SwiftUI
import SwiftData

struct SoundPoolPickerView: View {
    @Bindable var alarm: Alarm
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \AudioFile.displayName) private var allFiles: [AudioFile]

    private var bundled: [BundledAlarmSound] { BundledAlarmSound.all }

    private var enabledCount: Int {
        bundled.filter { isBundledEnabled($0) }.count + alarm.soundPool.count
    }

    var body: some View {
        List {
            Section {
                if bundled.isEmpty {
                    Label("No sounds in the app bundle", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else {
                    ForEach(bundled) { sound in
                        row(
                            title: sound.displayName,
                            subtitle: sound.fileName,
                            isOn: isBundledEnabled(sound)
                        ) {
                            toggleBundled(sound)
                        }
                    }
                }
            } header: {
                Text("Bundled with the app")
            } footer: {
                if bundled.isEmpty {
                    Text("Add one with tools/make_alarm_sound.py, then run `xcodegen generate` and rebuild.")
                } else {
                    Text("Ship with the app and play directly — no conversion needed. Add more with tools/make_alarm_sound.py.")
                }
            }

            Section {
                if allFiles.isEmpty {
                    Text("Nothing imported yet. Use the Sound Library tab.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allFiles) { file in
                        row(
                            title: file.displayName,
                            subtitle: "\(file.format.uppercased()) · \(file.durationSeconds.asMinuteSecondString)",
                            isOn: isImportedEnabled(file)
                        ) {
                            toggleImported(file)
                        }
                    }
                }
            } header: {
                Text("Imported")
            } footer: {
                Text("MP3/M4A aren't valid alert-sound formats, so an imported file is always converted into Library/Sounds before it can ring. Only the first ~28 seconds is used.")
            }
        }
        .navigationTitle("Sound Pool")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Text("\(enabledCount) on")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { try? modelContext.save() }
    }

    private func row(title: String, subtitle: String, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }
        }
    }

    // MARK: - Bundled
    //
    // Stored as an exclusion list (`disabledBundledSounds`), so a song is on unless it has
    // been explicitly switched off — which is what makes a newly bundled song eligible
    // without touching every existing alarm.

    private func isBundledEnabled(_ sound: BundledAlarmSound) -> Bool {
        !alarm.disabledBundledSounds.contains(sound.fileName)
    }

    private func toggleBundled(_ sound: BundledAlarmSound) {
        if let index = alarm.disabledBundledSounds.firstIndex(of: sound.fileName) {
            alarm.disabledBundledSounds.remove(at: index)
        } else {
            alarm.disabledBundledSounds.append(sound.fileName)
        }
    }

    // MARK: - Imported

    private func isImportedEnabled(_ file: AudioFile) -> Bool {
        alarm.soundPool.contains { $0.id == file.id }
    }

    private func toggleImported(_ file: AudioFile) {
        if let index = alarm.soundPool.firstIndex(where: { $0.id == file.id }) {
            alarm.soundPool.remove(at: index)
        } else {
            alarm.soundPool.append(file)
        }
    }
}
