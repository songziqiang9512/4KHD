import Foundation
import UniformTypeIdentifiers

@MainActor
@Observable
final class LocalLibraryStore {
    private(set) var roots: [LocalLibraryRoot] = []
    var selectedFolderID: LocalFolderNode.ID?
    var selectedImageIndex = 0
    var isFullscreenViewerPresented = false
    private(set) var isScanning = false

    @ObservationIgnored private var rootURLs: [URL] = []
    @ObservationIgnored private var excludedFolderPathsByRootPath: [String: Set<String>] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private static let rootFoldersDefaultsKey = "com.songziqiang.4khd.localRootFolders.v2"
    @ObservationIgnored private static let legacyRootFoldersDefaultsKey = "com.songziqiang.4khd.localFolders.v1"
    @ObservationIgnored private static let excludedFoldersDefaultsKey = "com.songziqiang.4khd.localExcludedFolders.v1"

    init() {
        loadRootFolders()
    }

    var selectedFolder: LocalFolderNode? {
        guard let selectedFolderID else { return firstFolder }
        return roots.lazy.compactMap { Self.folder(withID: selectedFolderID, in: $0.tree) }.first ?? firstFolder
    }

    var selectedImages: [LocalImageItem] {
        selectedFolder?.images ?? []
    }

    var selectedImage: LocalImageItem? {
        guard selectedImages.indices.contains(selectedImageIndex) else { return selectedImages.first }
        return selectedImages[selectedImageIndex]
    }

    var upcomingImageURLs: [URL] {
        let startIndex = max(selectedImageIndex + 1, 0)
        guard startIndex < selectedImages.count else { return [] }
        return selectedImages[startIndex...].prefix(8).map(\.url)
    }

    func importRootFolder(_ folderURL: URL) {
        let url = folderURL.standardizedFileURL
        isScanning = true
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let excludedPaths = self?.excludedFolderPathsByRootPath[url.path, default: []] ?? []
            let root = await Task.detached(priority: .userInitiated) {
                Self.scanRoot(at: url, excluding: excludedPaths)
            }.value

            guard !Task.isCancelled, let root else {
                self?.isScanning = false
                return
            }
            self?.applyImportedRoot(root, url: url)
        }
    }

    func removeFolder(_ folder: LocalFolderNode) {
        guard let root = roots.first(where: { Self.contains(folderID: folder.id, in: $0.tree) }) else { return }
        if root.tree.id == folder.id {
            removeRoot(root)
            return
        }

        excludedFolderPathsByRootPath[root.url.path, default: []].insert(folder.url.path)
        reloadRoot(root.url)
        saveExcludedFolders()
    }

    func removeRoot(_ root: LocalLibraryRoot) {
        rootURLs.removeAll { $0 == root.url }
        roots.removeAll { $0.id == root.id }
        excludedFolderPathsByRootPath[root.url.path] = nil
        saveRootFolders()
        saveExcludedFolders()
        if selectedFolderID == root.tree.id || Self.folder(withID: selectedFolderID, in: root.tree) != nil {
            selectedFolderID = firstFolder?.id
            selectedImageIndex = 0
        }
    }

    func selectFolder(_ folder: LocalFolderNode, force: Bool = false) {
        let targetFolder = folder.images.isEmpty ? Self.firstFolderWithImages(in: folder) ?? folder : folder
        guard force || selectedFolderID != targetFolder.id else { return }
        selectedFolderID = targetFolder.id
        selectedImageIndex = 0
    }

    func selectImage(at index: Int) {
        guard selectedImages.indices.contains(index) else { return }
        selectedImageIndex = index
    }

    func stepImage(_ delta: Int) {
        selectImage(at: selectedImageIndex + delta)
    }

    func refreshSelectedRoot() {
        guard let root = selectedRoot else { return }
        reloadRoot(root.url)
    }

    private var firstFolder: LocalFolderNode? {
        roots.lazy.compactMap { Self.firstFolderWithImages(in: $0.tree) ?? $0.tree }.first
    }

    private var selectedRoot: LocalLibraryRoot? {
        guard let selectedFolderID else { return roots.first }
        return roots.first { Self.contains(folderID: selectedFolderID, in: $0.tree) }
    }

    func findFolder(id: LocalFolderNode.ID) -> LocalFolderNode? {
        roots.lazy.compactMap { Self.folder(withID: id, in: $0.tree) }.first
    }

    private func loadRootFolders() {
        let storedPaths = (UserDefaults.standard.array(forKey: Self.rootFoldersDefaultsKey) as? [String])
            ?? (UserDefaults.standard.array(forKey: Self.legacyRootFoldersDefaultsKey) as? [String])
            ?? []
        loadExcludedFolders()
        rootURLs = storedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        roots = []
        selectedFolderID = nil
        isScanning = !rootURLs.isEmpty
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            let rootURLs = self.rootURLs
            let excluded = self.excludedFolderPathsByRootPath
            let scannedRoots = await Self.scanRoots(rootURLs, excluded: excluded)

            guard !Task.isCancelled else { return }
            self.roots = scannedRoots
            self.selectedFolderID = self.firstFolder?.id
            self.isScanning = false
        }
    }

    private func saveRootFolders() {
        UserDefaults.standard.set(rootURLs.map(\.path), forKey: Self.rootFoldersDefaultsKey)
    }

    private func saveExcludedFolders() {
        let payload = excludedFolderPathsByRootPath.mapValues { Array($0).sorted() }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.excludedFoldersDefaultsKey)
    }

    private func loadExcludedFolders() {
        guard let data = UserDefaults.standard.data(forKey: Self.excludedFoldersDefaultsKey),
              let payload = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            excludedFolderPathsByRootPath = [:]
            return
        }
        excludedFolderPathsByRootPath = payload.mapValues(Set.init)
    }

    private func reloadRoot(_ url: URL) {
        let excludedPaths = excludedFolderPathsByRootPath[url.path, default: []]
        isScanning = true
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let scannedRoot = await Task.detached(priority: .userInitiated) {
                Self.scanRoot(at: url, excluding: excludedPaths)
            }.value

            guard !Task.isCancelled else { return }
            if let scannedRoot,
               let index = self?.roots.firstIndex(where: { $0.url == url }) {
                self?.roots[index] = scannedRoot
                if self?.selectedFolderID == nil || Self.folder(withID: self?.selectedFolderID, in: scannedRoot.tree) == nil {
                    self?.selectedFolderID = Self.firstFolderWithImages(in: scannedRoot.tree)?.id ?? scannedRoot.tree.id
                    self?.selectedImageIndex = 0
                }
                self?.isScanning = false
            } else if let root = self?.roots.first(where: { $0.url == url }) {
                self?.isScanning = false
                self?.removeRoot(root)
            } else {
                self?.isScanning = false
            }
        }
    }

    private func applyImportedRoot(_ root: LocalLibraryRoot, url: URL) {
        rootURLs.removeAll { $0 == url }
        rootURLs.insert(url, at: 0)
        roots.removeAll { $0.url == url }
        roots.insert(root, at: 0)
        saveRootFolders()
        isScanning = false
        selectFolder(root.tree, force: true)
    }

    private nonisolated static func scanRoot(at url: URL, excluding excludedFolderPaths: Set<String>) -> LocalLibraryRoot? {
        guard !Task.isCancelled else { return nil }
        guard let tree = scanFolder(at: url, excluding: excludedFolderPaths), tree.imageCount > 0 else { return nil }
        return LocalLibraryRoot(url: url, tree: tree)
    }

    private nonisolated static func scanRoots(
        _ urls: [URL],
        excluded: [String: Set<String>]
    ) async -> [LocalLibraryRoot] {
        await withTaskGroup(of: (Int, LocalLibraryRoot?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask(priority: .utility) {
                    guard !Task.isCancelled else { return (index, nil) }
                    return (index, scanRoot(at: url, excluding: excluded[url.path, default: []]))
                }
            }

            var results: [(Int, LocalLibraryRoot)] = []
            for await (index, root) in group {
                if let root {
                    results.append((index, root))
                }
            }
            return results
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    private nonisolated static func scanFolder(at url: URL, excluding excludedFolderPaths: Set<String>) -> LocalFolderNode? {
        guard !Task.isCancelled else { return nil }
        let standardizedURL = url.standardizedFileURL
        guard !excludedFolderPaths.contains(standardizedURL.path) else { return nil }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .contentTypeKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: standardizedURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var folders: [LocalFolderNode] = []
        var images: [LocalImageItem] = []

        for child in children {
            if Task.isCancelled { return nil }
            guard let values = try? child.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory == true {
                if let folder = scanFolder(at: child, excluding: excludedFolderPaths), folder.imageCount > 0 {
                    folders.append(folder)
                }
            } else if values.isRegularFile == true,
                      values.contentType?.conforms(to: .image) == true {
                images.append(LocalImageItem(url: child.standardizedFileURL, title: child.lastPathComponent))
            }
        }

        folders.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        images.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        return LocalFolderNode(
            url: standardizedURL,
            title: standardizedURL.lastPathComponent.isEmpty ? standardizedURL.path : standardizedURL.lastPathComponent,
            folders: folders,
            images: images
        )
    }

    private static func folder(withID id: String?, in folder: LocalFolderNode) -> LocalFolderNode? {
        guard let id else { return nil }
        if folder.id == id { return folder }
        return folder.folders.lazy.compactMap { Self.folder(withID: id, in: $0) }.first
    }

    private static func firstFolderWithImages(in folder: LocalFolderNode) -> LocalFolderNode? {
        if !folder.images.isEmpty { return folder }
        return folder.folders.lazy.compactMap(Self.firstFolderWithImages).first
    }

    private static func contains(folderID: String, in folder: LocalFolderNode) -> Bool {
        folder.id == folderID || folder.folders.contains { contains(folderID: folderID, in: $0) }
    }
}
