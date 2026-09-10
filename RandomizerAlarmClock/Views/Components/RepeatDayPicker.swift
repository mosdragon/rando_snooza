//
//  RepeatDayPicker.swift
//  RandomizerAlarmClock
//
//  Seven-button day-of-week toggle row. Empty selection means "one-shot".
//

import SwiftUI

struct RepeatDayPicker: View {
    @Binding var selectedDays: [Int]

    private let symbols = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { day in
                Button {
                    toggle(day)
                } label: {
                    Text(symbols[day])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(isSelected(day) ? Color.accentColor : Color(.systemGray5))
                        .foregroundStyle(isSelected(day) ? .white : .primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fullDayName(day))
            }
        }
    }

    private func isSelected(_ day: Int) -> Bool {
        selectedDays.contains(day)
    }

    private func toggle(_ day: Int) {
        if let index = selectedDays.firstIndex(of: day) {
            selectedDays.remove(at: index)
        } else {
            selectedDays.append(day)
        }
    }

    private func fullDayName(_ day: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return names[day]
    }
}

#Preview {
    RepeatDayPicker(selectedDays: .constant([1, 3, 5]))
        .padding()
}
