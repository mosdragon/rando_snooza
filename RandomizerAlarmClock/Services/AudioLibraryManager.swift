//
//  AudioLibraryManager.swift
//  RandomizerAlarmClock
//
//  Imports user-picked audio files (from Files / iCloud Drive / Google Drive) into local
//  app storage, and manages preview playback of library files.
//

import Foundation
import AVFoundation
import SwiftData

enum AudioLibraryError: Error, LocalizedError {
    case unsupportedFormat
    case couldNotAccessSource
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "That file type isn't supported. Use MP3, M4A, or WAV."
        case .couldNotAccessSource: return "Couldn't access the selected file."
        case .copyFailed: return "Couldn't copy the file into the app's audio library."
        }
    }
}

@MainActor
final class AudioLibraryManager {
    static let shared = AudioLibraryManager()

    private var previewPlayer: AVAudioPlayer?

    static let supportedExtensions: Set<String> = ["mp3", "m4a", "wav"]

    /// Documents/AudioLibrary/ — where every imported file's actual bytes live.
    /// `nonisolated` because it's pure FileManager path computation (thread-safe) that
    /// SwiftData model types like `AudioFile` need to reference from a non-MainActor context.
    nonisolated static var libraryDirectory: URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioLibrary", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Copies each picked file into local storage and creates an `AudioFile` model for it.
    /// Returns the created models; the caller inserts them into the SwiftData context.
    func importFiles(from urls: [URL]) -> [AudioFile] {
        var imported: [AudioFile] = []

        for sourceURL in urls {
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() } }

            do {
                let audioFile = try importSingleFile(from: sourceURL)
                imported.append(audioFile)
            } catch {
                // Skip files that fail; the caller can surface a summary if `imported.count`
                // is fewer than `urls.count`.
                continue
            }
        }

        return imported
    }

    private func importSingleFile(from sourceURL: URL) throws -> AudioFile {
        let ext = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            throw AudioLibraryError.unsupportedFormat
        }

        let destinationFileName = "\(UUID().uuidString).\(ext)"
        let destinationURL = Self.libraryDirectory.appendingPathComponent(destinationFileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw AudioLibraryError.copyFailed
        }

        // AVURLAsset's modern `.duration` is async; the synchronous `CMTime`-based property
        // is deprecated but reads local file metadata instantly and avoids bouncing this
        // MainActor-isolated import path through a background Task.
        let asset = AVURLAsset(url: destinationURL)
        let duration = asset.duration.seconds.isFinite ? asset.duration.seconds : 0

        let displayName = sourceURL.deletingPathExtension().lastPathComponent

        return AudioFile(
            displayName: displayName,
            fileName: destinationFileName,
            format: ext,
            durationSeconds: duration
        )
    }

    /// Removes the on-disk file backing an `AudioFile`. Call before deleting the model itself.
    func deleteFile(for audioFile: AudioFile) {
        try? FileManager.default.removeItem(at: audioFile.fileURL)
    }

    // MARK: - Preview playback

    func previewPlay(_ audioFile: AudioFile) {
        stopPreview()
        do {
            let player = try AVAudioPlayer(contentsOf: audioFile.fileURL)
            player.play()
            previewPlayer = player
        } catch {
            previewPlayer = nil
        }
    }

    func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    var isPreviewPlaying: Bool {
        previewPlayer?.isPlaying ?? false
    }
}
