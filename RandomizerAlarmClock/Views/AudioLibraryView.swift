//
//  AudioLibraryView.swift
//  RandomizerAlarmClock
//
//  Manage every imported audio file: import new ones, preview, rename, delete.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AudioLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AudioFile.displayName) private var files: [AudioFile]

    @State private var isImporting = false
    @State private var playingFileID: UUID?
    @State private var renamingFile: AudioFile?
    @State private var renameText = ""
    @State private var importErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if files.isEmpty {
                    ContentUnavailableView(
                        "No sounds yet",
                        systemImage: "waveform",
                        description: Text("Import MP3, M4A, or WAV files from Files, iCloud Drive, or Google Drive.")
                    )
                } else {
                    ForEach(files) { file in
                        row(for: file)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Sound Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.mp3, .mpeg4Audio, .wav],
                allowsMultipleSelection: true
            ) { result in
                handleImportResult(result)
            }
            .alert("Import Error", isPresented: .constant(importErrorMessage != nil), actions: {
                Button("OK") { importErrorMessage = nil }
            }, message: {
                Text(importErrorMessage ?? "")
            })
            .alert("Rename Sound", isPresented: .constant(renamingFile != nil), actions: {
                TextField("Name", text: $renameText)
                Button("Save") { commitRename() }
                Button("Cancel", role: .cancel) { renamingFile = nil }
            })
        }
    }

    private func row(for file: AudioFile) -> some View {
        HStack {
            Button {
                togglePreview(file)
            } label: {
                Image(systemName: playingFileID == file.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                HStack(spacing: 6) {
                    Text(file.format.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                    Text(file.durationSeconds.asMinuteSecondString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if file.exceedsUsableWindow {
                        Text("only first 28s used")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            Button {
                renamingFile = file
                renameText = file.displayName
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func togglePreview(_ file: AudioFile) {
        if playingFileID == file.id {
            AudioLibraryManager.shared.stopPreview()
            playingFileID = nil
        } else {
            AudioLibraryManager.shared.previewPlay(file)
            playingFileID = file.id
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let newFiles = AudioLibraryManager.shared.importFiles(from: urls)
            for file in newFiles {
                modelContext.insert(file)
            }
            if newFiles.count < urls.count {
                importErrorMessage = "Imported \(newFiles.count) of \(urls.count) files. Unsupported or unreadable files were skipped."
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let file = files[index]
            AudioLibraryManager.shared.deleteFile(for: file)
            modelContext.delete(file)
        }
    }

    private func commitRename() {
        guard let file = renamingFile else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            file.displayName = trimmed
        }
        renamingFile = nil
    }
}

#Preview {
    AudioLibraryView()
        .modelContainer(for: [Alarm.self, AudioFile.self], inMemory: true)
}
