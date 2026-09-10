//
//  AlarmListView.swift
//  RandomizerAlarmClock
//
//  Main screen: list of alarms, with quick enable/disable and swipe-to-delete.
//

import SwiftUI
import SwiftData

struct AlarmListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Alarm.hour), SortDescriptor(\Alarm.minute)]) private var alarms: [Alarm]

    @State private var newAlarm: Alarm?

    var body: some View {
        NavigationStack {
            List {
                if alarms.isEmpty {
                    ContentUnavailableView(
                        "No alarms yet",
                        systemImage: "alarm",
                        description: Text("Tap + to create one.")
                    )
                } else {
                    ForEach(alarms) { alarm in
                        NavigationLink {
                            AlarmEditView(alarm: alarm)
                        } label: {
                            row(for: alarm)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newAlarm = Alarm()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $newAlarm) { alarm in
                NavigationStack {
                    AlarmEditView(alarm: alarm, isNew: true)
                }
            }
        }
    }

    private func row(for alarm: Alarm) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.timeString)
                    .font(.title2.weight(.medium))
                Text(alarm.label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(alarm.repeatDaysString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { newValue in
                    alarm.isEnabled = newValue
                    AlarmScheduler.reschedule(alarm)
                    try? modelContext.save()
                }
            ))
            .labelsHidden()
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let alarm = alarms[index]
            AlarmScheduler.cancelPending(for: alarm)
            modelContext.delete(alarm)
        }
    }
}

#Preview {
    AlarmListView()
        .modelContainer(for: [Alarm.self, AudioFile.self], inMemory: true)
}
