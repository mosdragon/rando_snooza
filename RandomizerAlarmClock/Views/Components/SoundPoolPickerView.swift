//
//  SoundPoolPickerView.swift
//  RandomizerAlarmClock
//
//  Multi-select list of every audio file in the library, bound to one alarm's sound pool.
//

import SwiftUI
import SwiftData

struct SoundPoolPickerView: View {
    @Bindable var alarm: Alarm
    @Query(sort: \AudioFile.displayName) private var allFiles: [AudioFile]

    var body: some View {
        List {
            if allFiles.isEmpty {
                ContentUnavailableView(
                    "No sounds yet",
                    systemImage: "waveform",
                    description: Text("Import audio files from the Sound Library tab first.")
                )
            } else {
                ForEach(allFiles) { file in
                    Button {
                        toggle(file)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(file.displayName)
                                    .foregroundStyle(.primary)
                                Text("\(file.format.uppercased()) · \(file.durationSeconds.asMinuteSecondString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected(file) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sound Pool")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Text("\(alarm.soundPool.count) selected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isSelected(_ file: AudioFile) -> Bool {
        alarm.soundPool.contains(where: { $0.id == file.id })
    }

    private func toggle(_ file: AudioFile) {
        if let index = alarm.soundPool.firstIndex(where: { $0.id == file.id }) {
            alarm.soundPool.remove(at: index)
        } else {
            alarm.soundPool.append(file)
        }
    }
}
