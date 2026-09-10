//
//  RootTabView.swift
//  RandomizerAlarmClock
//

import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            AlarmListView()
                .tabItem {
                    Label("Alarms", systemImage: "alarm")
                }

            AudioLibraryView()
                .tabItem {
                    Label("Sound Library", systemImage: "waveform")
                }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Alarm.self, AudioFile.self], inMemory: true)
}
