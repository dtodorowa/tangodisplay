import Foundation
import Combine

/// Persists user-created appearance profiles as individual JSON files under
/// ~/Library/Application Support/TangoDisplay/profiles/
/// Built-in profiles are never written to disk; they are synthesised at runtime.
public final class ProfileStore: ObservableObject {
    @Published public var userProfiles: [AppearanceProfile] = []

    private let storeURL: URL

    public init(storeURL: URL? = nil) {
        if let url = storeURL {
            self.storeURL = url
        } else {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.storeURL = appSupport
                .appendingPathComponent("TangoDisplay", isDirectory: true)
                .appendingPathComponent("profiles", isDirectory: true)
        }
    }

    // MARK: - Image storage

    /// Directory where per-profile background images are stored.
    public var imagesDirectoryURL: URL {
        storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("images", isDirectory: true)
    }

    /// Full URL for a stored image filename (e.g. "{uuid}.jpg").
    public func imageURL(for filename: String) -> URL {
        imagesDirectoryURL.appendingPathComponent(filename)
    }

    /// Creates the images directory if it doesn't already exist.
    public func createImagesDirectoryIfNeeded() {
        let url = imagesDirectoryURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public var allProfiles: [AppearanceProfile] {
        AppearanceProfile.builtIns + userProfiles
    }

    // MARK: - Load

    public func load() {
        createDirectoryIfNeeded()
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: storeURL,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" }
        } catch {
            files = []
        }

        let decoder = JSONDecoder()
        userProfiles = files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let profile = try? decoder.decode(AppearanceProfile.self, from: data),
                  !profile.isBuiltIn
            else { return nil }
            return profile
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Save

    public func save(_ profile: AppearanceProfile) throws {
        guard !profile.isBuiltIn else {
            throw ProfileStoreError.cannotModifyBuiltIn
        }
        createDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(profile)
        let fileURL = storeURL.appendingPathComponent("\(profile.id.uuidString).json")
        try data.write(to: fileURL, options: .atomic)

        // Update in-memory list
        if let idx = userProfiles.firstIndex(where: { $0.id == profile.id }) {
            userProfiles[idx] = profile
        } else {
            userProfiles.append(profile)
            userProfiles.sort { $0.name < $1.name }
        }
    }

    // MARK: - Delete

    public func delete(_ profile: AppearanceProfile) throws {
        guard !profile.isBuiltIn else {
            throw ProfileStoreError.cannotModifyBuiltIn
        }
        let fileURL = storeURL.appendingPathComponent("\(profile.id.uuidString).json")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        // Clean up any associated background images
        if let filename = profile.backgroundImageFilename {
            try? FileManager.default.removeItem(at: imageURL(for: filename))
        }
        if let filename = profile.cortinaImageFilename {
            try? FileManager.default.removeItem(at: imageURL(for: filename))
        }
        for entry in profile.artistBackgrounds {
            if let filename = entry.imageFilename {
                try? FileManager.default.removeItem(at: imageURL(for: filename))
            }
        }
        userProfiles.removeAll { $0.id == profile.id }
    }

    // MARK: - Helpers

    private func createDirectoryIfNeeded() {
        guard !FileManager.default.fileExists(atPath: storeURL.path) else { return }
        try? FileManager.default.createDirectory(at: storeURL,
                                                  withIntermediateDirectories: true)
    }
}

public enum ProfileStoreError: Error, LocalizedError {
    case cannotModifyBuiltIn

    public var errorDescription: String? {
        switch self {
        case .cannotModifyBuiltIn: "Built-in profiles cannot be modified or deleted."
        }
    }
}
