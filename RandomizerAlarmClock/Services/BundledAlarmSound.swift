//
//  BundledAlarmSound.swift
//  RandomizerAlarmClock
//
//  The alarm sounds compiled into the app bundle, DISCOVERED AT RUNTIME rather than listed
//  in code. Drop a new .caf into Resources/Sounds/ (tools/make_alarm_sound.py does this),
//  re-run `xcodegen generate`, rebuild — and it shows up. No Swift edit per song.
//
//  Display titles come from an optional `sounds.json` manifest the script maintains; any
//  file missing from the manifest falls back to a prettified version of its file name.
//

import Foundation
import os

struct BundledAlarmSound: Identifiable, Hashable {

    /// File name *including* extension, e.g. "viva.caf". This is exactly what
    /// `AlertConfiguration.AlertSound.named(_:)` expects.
    let fileName: String

    /// Human-readable name for the UI.
    let displayName: String

    var id: String { fileName }

    var bundleURL: URL? {
        let stem = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        return Bundle.main.url(forResource: stem, withExtension: ext)
    }

    // MARK: - Discovery

    private static let log = Logger(subsystem: "com.personal.RandomizerAlarmClock", category: "sounds")

    /// Every alarm sound in the bundle, sorted by display name. Computed once.
    ///
    /// An EMPTY array means no `.caf` made it into the built product — almost always a
    /// missing `xcodegen generate` after adding files, not a code problem.
    static let all: [BundledAlarmSound] = discover()

    private static func discover() -> [BundledAlarmSound] {
        let titles = loadTitleManifest()
        let urls = Bundle.main.urls(forResourcesWithExtension: "caf", subdirectory: nil) ?? []

        let sounds = urls.map { url -> BundledAlarmSound in
            let fileName = url.lastPathComponent
            let stem = url.deletingPathExtension().lastPathComponent
            let title = titles[stem] ?? titles[fileName] ?? prettify(stem)
            return BundledAlarmSound(fileName: fileName, displayName: title)
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        if sounds.isEmpty {
            log.error("No .caf alarm sounds found in the app bundle. Did `xcodegen generate` run after adding them to Resources/Sounds/?")
        } else {
            log.info("Discovered \(sounds.count) bundled alarm sound(s): \(sounds.map(\.fileName).joined(separator: ", "), privacy: .public)")
        }
        return sounds
    }

    /// `sounds.json` is a flat `{ "<file stem or name>": "<display title>" }` map.
    /// Absent or malformed is fine — titles just fall back to the file name.
    private static func loadTitleManifest() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "sounds", withExtension: "json") else {
            log.info("No sounds.json in the bundle; deriving display names from file names.")
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            log.error("Could not read sounds.json: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private static func prettify(_ stem: String) -> String {
        stem.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
