//
//  AudioFile.swift
//  RandomizerAlarmClock
//
//  Represents one imported audio file living in Documents/AudioLibrary/.
//

import Foundation
import SwiftData

@Model
final class AudioFile {
    var id: UUID
    /// Name shown in the UI. Editable by the user; independent of the file on disk.
    var displayName: String
    /// File name only (not a full path), relative to Documents/AudioLibrary/.
    var fileName: String
    /// One of "mp3", "m4a", "wav".
    var format: String
    /// Duration of the original, unmodified file.
    var durationSeconds: Double
    var dateAdded: Date

    init(displayName: String, fileName: String, format: String, durationSeconds: Double) {
        self.id = UUID()
        self.displayName = displayName
        self.fileName = fileName
        self.format = format
        self.durationSeconds = durationSeconds
        self.dateAdded = Date()
    }

    /// Absolute location of the underlying audio file on disk.
    var fileURL: URL {
        AudioLibraryManager.libraryDirectory.appendingPathComponent(fileName)
    }

    /// True if this file is longer than the ~28s window alarms actually use.
    var exceedsUsableWindow: Bool {
        durationSeconds > AudioProcessor.maxRenderedDuration
    }
}
