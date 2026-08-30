//
//  ReminderTimeWindowSettingsView.swift
//  BeReallyReal
//
//  Created by Oliver Wege on 26.08.26.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: PhotoStore

    private let defaultWeekdayStart = 6
    private let defaultWeekdayEnd = 22
    private let defaultWeekendStart = 8
    private let defaultWeekendEnd = 24

    @AppStorage("includeLocationByDefault") private var includeLocationByDefault = true
    @AppStorage("weekdayReminderStartHour") private var weekdayStartHour = 6
    @AppStorage("weekdayReminderEndHour") private var weekdayEndHour = 22
    @AppStorage("weekendReminderStartHour") private var weekendStartHour = 8
    @AppStorage("weekendReminderEndHour") private var weekendEndHour = 24

    @State private var backupExportItem: BackupExportItem?
    @State private var showingBackupImporter = false
    @State private var pendingImportURL: URL?
    @State private var showingImportOptions = false
    @State private var showingBackupAlert = false
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""
    @State private var isPreparingBackup = false

    let done: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $includeLocationByDefault) {
                        Label("Add location by default", systemImage: "map")
                    }
                }

                Section {
                    HourRangeEditor(
                        title: "Weekdays",
                        startHour: $weekdayStartHour,
                        endHour: $weekdayEndHour
                    )

                    HourRangeEditor(
                        title: "Weekends",
                        startHour: $weekendStartHour,
                        endHour: $weekendEndHour
                    )

                    Button {
                        restoreDefaults()
                    } label: {
                        Label("Restore Default Times", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("A reminder will be scheduled at a random time inside the selected window.")
                }

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label(
                            isPreparingBackup ? "Preparing Backup" : "Export Backup",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    .disabled(isPreparingBackup)

                    Button {
                        showingBackupImporter = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Export all memories, captions, dates, locations, and photo files into one backup package. You can import it on another device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        normalizeHours()
                        NotificationScheduler.scheduleNext()
                        done()
                    }
                }
            }
            .onAppear {
                normalizeHours()
            }
            .onDisappear {
                normalizeHours()
                NotificationScheduler.scheduleNext()
            }
            .sheet(item: $backupExportItem, onDismiss: cleanupExportPackage) { item in
                BackupDocumentExporter(url: item.url) { result in
                    switch result {
                    case .success:
                        showBackupAlert(
                            title: "Backup Exported",
                            message: "Your BeReallyReal backup was exported successfully."
                        )

                    case .failure(let error):
                        showBackupAlert(
                            title: "Export Failed",
                            message: error.localizedDescription
                        )
                    }
                }
            }
            .fileImporter(
                isPresented: $showingBackupImporter,
                allowedContentTypes: [.beReallyRealBackup, .package, .folder, .propertyList, .data],
                allowsMultipleSelection: false
            ) { result in
                handleImportPickerResult(result)
            }
            .confirmationDialog(
                "Import Backup",
                isPresented: $showingImportOptions,
                titleVisibility: .visible
            ) {
                Button("Merge with Current Data") {
                    importPendingBackup(mode: .merge)
                }

                Button("Replace Current Data", role: .destructive) {
                    importPendingBackup(mode: .replace)
                }

                Button("Cancel", role: .cancel) {
                    cleanupPendingImport()
                }
            } message: {
                Text("Merge keeps your existing memories and adds memories from the backup. Replace deletes current app data first.")
            }
            .alert(backupAlertTitle, isPresented: $showingBackupAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupAlertMessage)
            }
        }
    }

    private func normalizeHours() {
        weekdayStartHour = min(max(weekdayStartHour, 0), 23)
        weekdayEndHour = min(max(weekdayEndHour, 1), 24)

        if weekdayStartHour >= weekdayEndHour {
            weekdayStartHour = defaultWeekdayStart
            weekdayEndHour = defaultWeekdayEnd
        }

        weekendStartHour = min(max(weekendStartHour, 0), 23)
        weekendEndHour = min(max(weekendEndHour, 1), 24)

        if weekendStartHour >= weekendEndHour {
            weekendStartHour = defaultWeekendStart
            weekendEndHour = defaultWeekendEnd
        }
    }

    private func restoreDefaults() {
        weekdayStartHour = defaultWeekdayStart
        weekdayEndHour = defaultWeekdayEnd
        weekendStartHour = defaultWeekendStart
        weekendEndHour = defaultWeekendEnd
    }

    private func exportBackup() {
        guard !isPreparingBackup else { return }

        isPreparingBackup = true

        do {
            let url = try store.createBackupPackage()
            backupExportItem = BackupExportItem(url: url)
            isPreparingBackup = false
        } catch {
            isPreparingBackup = false

            showBackupAlert(
                title: "Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func handleImportPickerResult(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }

            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            cleanupPendingImport()

            let copiedURL = try copyImportCandidateToTemporaryLocation(url)
            pendingImportURL = copiedURL
            showingImportOptions = true
        } catch {
            showBackupAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func importPendingBackup(mode: PhotoBackupImportMode) {
        guard let pendingImportURL else {
            return
        }

        do {
            try store.importBackup(at: pendingImportURL, mode: mode)
            cleanupPendingImport()

            showBackupAlert(
                title: "Backup Imported",
                message: mode == .replace
                    ? "Your current data was replaced with the backup."
                    : "The backup was merged with your current data."
            )
        } catch {
            showBackupAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func copyImportCandidateToTemporaryLocation(_ url: URL) throws -> URL {
        let fileExtension = url.pathExtension.isEmpty ? "backup" : url.pathExtension

        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Imported Backup-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: url, to: destinationURL)

        return destinationURL
    }

    private func cleanupPendingImport() {
        if let pendingImportURL {
            try? FileManager.default.removeItem(at: pendingImportURL)
        }

        pendingImportURL = nil
    }

    private func cleanupExportPackage() {
        if let url = backupExportItem?.url {
            try? FileManager.default.removeItem(at: url)
        }

        backupExportItem = nil
    }

    private func showBackupAlert(title: String, message: String) {
        backupAlertTitle = title
        backupAlertMessage = message
        showingBackupAlert = true
    }
}

private struct BackupExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct BackupDocumentExporter: UIViewControllerRepresentable {
    let url: URL
    let completion: (Result<Void, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let viewController = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        viewController.delegate = context.coordinator
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<Void, Error>) -> Void

        init(completion: @escaping (Result<Void, Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(.success(()))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        }
    }
}

private extension UTType {
    static let beReallyRealBackup = UTType(
        exportedAs: "com.bereallyreal.backup",
        conformingTo: .package
    )
}
