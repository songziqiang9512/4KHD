import Foundation
import UniformTypeIdentifiers

nonisolated struct LocalLibraryRootBookmarkRecord: Codable, Sendable {
    let path: String
    let bookmarkData: Data?
}

@MainActor
@Observable
final class LocalLibraryStore {
    static let allImagesFolderID: LocalFolderNode.ID = "localLibrary.allImages"

    private(set) var roots: [LocalLibraryRoot] = []
    var selectedFolderID: LocalFolderNode.ID? = LocalLibraryStore.allImagesFolderID
    var selectedImageIndex = 0
    var isFullscreenViewerPresented = false
    private(set) var isScanning = false

    @ObservationIgnored private var rootURLs: [URL] = []
    @ObservationIgnored private var bookmarkRecordsByPath: [String: LocalLibraryRootBookmarkRecord] = [:]
    @ObservationIgnored private var securityScopedAccessByPath: [String: (url: URL, didStart: Bool)] = [:]
    @ObservationIgnored private var excludedFolderPathsByRootPath: [String: Set<String>] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var cachedAllImages: [LocalImageItem] = []
    @ObservationIgnored private var cachedAllImagesRootSignature: [String] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let rootBookmarksDefaultsKey = "com.songziqiang.4khd.localRootBookmarks.v3"
    @ObservationIgnored private static let rootFoldersDefaultsKey = "com.songziqiang.4khd.localRootFolders.v2"
    @ObservationIgnored private static let legacyRootFoldersDefaultsKey = "com.songziqiang.4khd.localFolders.v1"
    @ObservationIgnored private static let excludedFoldersDefaultsKey = "com.songziqiang.4khd.localExcludedFolders.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadRootFolders()
    }

    deinit {
        for access in securityScopedAccessByPath.values where access.didStart {
            access.url.stopAccessingSecurityScopedResource()
        }
    }

    var selectedFolder: LocalFolderNode? {
        guard !isAllImagesSelected else { return nil }
        guard let selectedFolderID else { return firstFolder }
        return roots.lazy.compactMap { Self.folder(withID: selectedFolderID, in: $0.tree) }.first ?? firstFolder
    }

    var selectedImages: [LocalImageItem] {
        if isAllImagesSelected {
            return allImages
        }
        return selectedFolder?.images ?? []
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
        installBookmarkAndAccess(for: url)
        isScanning = true
        scanTask?.cancel()
        let wasAlreadyAdded = rootURLs.contains(url)
        scanTask = Task { [weak self] in
            let excludedPaths = self?.excludedFolderPathsByRootPath[url.path, default: []] ?? []
            let root = await Self.scanRootInWorker(at: url, excluding: excludedPaths)

            // 被更新的扫描取消时不动 isScanning，否则会覆盖新任务刚设置的 true。
            guard !Task.isCancelled else { return }
            guard let root else {
                if !wasAlreadyAdded {
                    self?.releaseSecurityScopedAccess(forPath: url.path)
                    self?.bookmarkRecordsByPath[url.path] = nil
                }
                self?.isScanning = false
                return
            }
            // 扫描期间用户删除了该根目录：尊重删除，不重新插回。
            if wasAlreadyAdded, self?.rootURLs.contains(url) == false {
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
        releaseSecurityScopedAccess(forPath: root.url.path)
        bookmarkRecordsByPath[root.url.path] = nil
        rootURLs.removeAll { $0 == root.url }
        roots.removeAll { $0.id == root.id }
        localPixelSizeCache.removeEntries(under: root.url)
        excludedFolderPathsByRootPath[root.url.path] = nil
        saveRootFolders()
        saveExcludedFolders()
        if selectedFolderID == root.tree.id || Self.folder(withID: selectedFolderID, in: root.tree) != nil {
            selectedFolderID = Self.allImagesFolderID
            selectedImageIndex = 0
        } else if isAllImagesSelected {
            clampSelectedImageIndex()
        }
    }

    func selectAllImages(force: Bool = false) {
        guard force || selectedFolderID != Self.allImagesFolderID else { return }
        selectedFolderID = Self.allImagesFolderID
        selectedImageIndex = 0
    }

    func selectFolder(_ folder: LocalFolderNode, force: Bool = false) {
        let targetFolder = folder.images.isEmpty ? Self.firstFolderWithImages(in: folder) ?? folder : folder
        guard force || selectedFolderID != targetFolder.id else { return }
        selectedFolderID = targetFolder.id
        selectedImageIndex = 0
    }

    func reorderRootFolder(id: LocalFolderNode.ID, to destinationIndex: Int) {
        guard let sourceIndex = roots.firstIndex(where: { $0.tree.id == id }) else { return }
        var targetIndex = max(0, min(destinationIndex, roots.count))
        if sourceIndex < targetIndex {
            targetIndex -= 1
        }
        guard sourceIndex != targetIndex else { return }

        var updatedRoots = roots
        let movedRoot = updatedRoots.remove(at: sourceIndex)
        updatedRoots.insert(movedRoot, at: max(0, min(targetIndex, updatedRoots.count)))
        roots = updatedRoots
        rootURLs = updatedRoots.map(\.url)
        saveRootFolders()
    }

    func reorderRootFolders(ids orderedIDs: [LocalFolderNode.ID]) {
        let rootByFolderID = Dictionary(uniqueKeysWithValues: roots.map { ($0.tree.id, $0) })
        let orderedRoots = orderedIDs.compactMap { rootByFolderID[$0] }
        let orderedIDSet = Set(orderedIDs)
        let remainingRoots = roots.filter { !orderedIDSet.contains($0.tree.id) }
        let updatedRoots = orderedRoots + remainingRoots
        guard updatedRoots.count == roots.count,
              updatedRoots.map(\.id) != roots.map(\.id) else { return }
        roots = updatedRoots
        rootURLs = updatedRoots.map(\.url)
        saveRootFolders()
    }

    func selectImage(at index: Int) {
        guard selectedImages.indices.contains(index) else { return }
        selectedImageIndex = index
    }

    func stepImage(_ delta: Int) {
        selectImage(at: selectedImageIndex + delta)
    }

    func refreshSelectedRoot() {
        if isAllImagesSelected {
            reloadAllRoots()
            return
        }
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

    var defaultFolderID: LocalFolderNode.ID? {
        Self.allImagesFolderID
    }

    func findFolder(id: LocalFolderNode.ID) -> LocalFolderNode? {
        guard id != Self.allImagesFolderID else { return nil }
        return roots.lazy.compactMap { Self.folder(withID: id, in: $0.tree) }.first
    }

    func isAllImagesFolderID(_ id: LocalFolderNode.ID) -> Bool {
        id == Self.allImagesFolderID
    }

    private func loadRootFolders() {
        let bookmarkRecords: [LocalLibraryRootBookmarkRecord]? = defaults
            .data(forKey: Self.rootBookmarksDefaultsKey)
            .flatMap { try? JSONDecoder().decode([LocalLibraryRootBookmarkRecord].self, from: $0) }
        let storedPaths = (defaults.array(forKey: Self.rootFoldersDefaultsKey) as? [String])
            ?? (defaults.array(forKey: Self.legacyRootFoldersDefaultsKey) as? [String])
            ?? []
        let records = bookmarkRecords ?? storedPaths.map {
            LocalLibraryRootBookmarkRecord(path: $0, bookmarkData: nil)
        }
        loadExcludedFolders()
        var resolvedURLs: [URL] = []
        for record in records {
            let resolved = resolveBookmark(record) ?? URL(fileURLWithPath: record.path).standardizedFileURL
            resolvedURLs.append(resolved)
            let refreshedRecord = makeBookmarkRecord(for: resolved) ?? LocalLibraryRootBookmarkRecord(
                path: resolved.path,
                bookmarkData: record.bookmarkData
            )
            bookmarkRecordsByPath[resolved.path] = refreshedRecord
            registerSecurityScopedAccess(for: resolved)
        }
        rootURLs = resolvedURLs
        if bookmarkRecords == nil, !records.isEmpty {
            saveRootFolders()
        }
        roots = []
        selectedFolderID = Self.allImagesFolderID
        isScanning = !rootURLs.isEmpty
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            let rootURLs = self.rootURLs
            let excluded = self.excludedFolderPathsByRootPath
            let scannedRoots = await Self.scanRoots(rootURLs, excluded: excluded)

            guard !Task.isCancelled else { return }
            self.roots = scannedRoots
            self.selectedFolderID = Self.allImagesFolderID
            self.isScanning = false
        }
    }

    private func saveRootFolders() {
        let records = rootURLs.map { url in
            bookmarkRecordsByPath[url.path]
                ?? makeBookmarkRecord(for: url)
                ?? LocalLibraryRootBookmarkRecord(path: url.path, bookmarkData: nil)
        }
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.rootBookmarksDefaultsKey)
        }
        defaults.removeObject(forKey: Self.rootFoldersDefaultsKey)
        defaults.removeObject(forKey: Self.legacyRootFoldersDefaultsKey)
    }

    private func saveExcludedFolders() {
        let payload = excludedFolderPathsByRootPath.mapValues { Array($0).sorted() }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.excludedFoldersDefaultsKey)
    }

    private func loadExcludedFolders() {
        guard let data = defaults.data(forKey: Self.excludedFoldersDefaultsKey),
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
            let scannedRoot = await Self.scanRootInWorker(at: url, excluding: excludedPaths)

            guard !Task.isCancelled else { return }
            if let scannedRoot,
               let index = self?.roots.firstIndex(where: { $0.url == url }) {
                self?.roots[index] = scannedRoot
                self?.invalidateAllImagesCache()
                if self?.selectedFolderID == nil || Self.folder(withID: self?.selectedFolderID, in: scannedRoot.tree) == nil {
                    self?.selectedFolderID = Self.allImagesFolderID
                    self?.selectedImageIndex = 0
                } else {
                    self?.clampSelectedImageIndex()
                }
                self?.isScanning = false
            } else if let root = self?.roots.first(where: { $0.url == url }) {
                self?.isScanning = false
                // 目录不可读（外接磁盘断开等）时保留库内容；仅当目录确实存在（扫描结果为空）才移除。
                if FileManager.default.fileExists(atPath: url.path) {
                    self?.removeRoot(root)
                }
            } else {
                self?.isScanning = false
            }
        }
    }

    private func reloadAllRoots() {
        isScanning = !rootURLs.isEmpty
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            let rootURLs = self.rootURLs
            let excluded = self.excludedFolderPathsByRootPath
            let scannedRoots = await Self.scanRoots(rootURLs, excluded: excluded)

            guard !Task.isCancelled else { return }
            self.roots = scannedRoots
            self.invalidateAllImagesCache()
            self.selectedFolderID = Self.allImagesFolderID
            self.clampSelectedImageIndex()
            self.isScanning = false
        }
    }

    private func applyImportedRoot(_ root: LocalLibraryRoot, url: URL) {
        rootURLs.removeAll { $0 == url }
        rootURLs.insert(url, at: 0)
        roots.removeAll { $0.url == url }
        roots.insert(root, at: 0)
        saveRootFolders()
        isScanning = false
        if !isAllImagesSelected {
            selectFolder(root.tree, force: true)
        }
    }

    private func installBookmarkAndAccess(for url: URL) {
        releaseSecurityScopedAccess(forPath: url.path)
        bookmarkRecordsByPath[url.path] = makeBookmarkRecord(for: url)
            ?? LocalLibraryRootBookmarkRecord(path: url.path, bookmarkData: nil)
        registerSecurityScopedAccess(for: url)
    }

    private func resolveBookmark(_ record: LocalLibraryRootBookmarkRecord) -> URL? {
        guard let bookmarkData = record.bookmarkData else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL
    }

    private func makeBookmarkRecord(for url: URL) -> LocalLibraryRootBookmarkRecord? {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return nil
        }
        return LocalLibraryRootBookmarkRecord(path: url.path, bookmarkData: data)
    }

    private func registerSecurityScopedAccess(for url: URL) {
        guard securityScopedAccessByPath[url.path] == nil else { return }
        securityScopedAccessByPath[url.path] = (url, url.startAccessingSecurityScopedResource())
    }

    private func releaseSecurityScopedAccess(forPath path: String) {
        guard let access = securityScopedAccessByPath.removeValue(forKey: path), access.didStart else { return }
        access.url.stopAccessingSecurityScopedResource()
    }

    private nonisolated static func scanRoot(at url: URL, excluding excludedFolderPaths: Set<String>) -> LocalLibraryRoot? {
        guard !Task.isCancelled else { return nil }
        var visitedDirectoryPaths = Set<String>()
        guard let tree = scanFolder(
            at: url,
            excluding: excludedFolderPaths,
            visitedDirectoryPaths: &visitedDirectoryPaths
        ), tree.imageCount > 0 else { return nil }
        return LocalLibraryRoot(url: url, tree: tree)
    }

    private nonisolated static func scanRootInWorker(
        at url: URL,
        excluding excludedFolderPaths: Set<String>
    ) async -> LocalLibraryRoot? {
        let worker = Task.detached(priority: .userInitiated) {
            scanRoot(at: url, excluding: excludedFolderPaths)
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
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

    private nonisolated static func scanFolder(
        at url: URL,
        excluding excludedFolderPaths: Set<String>,
        visitedDirectoryPaths: inout Set<String>
    ) -> LocalFolderNode? {
        guard !Task.isCancelled else { return nil }
        let standardizedURL = url.standardizedFileURL
        guard !excludedFolderPaths.contains(standardizedURL.path) else { return nil }
        let resolvedDirectoryPath = standardizedURL.resolvingSymlinksInPath().path
        guard visitedDirectoryPaths.insert(resolvedDirectoryPath).inserted else { return nil }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .contentTypeKey
        ]
        guard let directoryValues = try? standardizedURL.resourceValues(forKeys: keys),
              directoryValues.isPackage != true else {
            return nil
        }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: standardizedURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var folders: [LocalFolderNode] = []
        var images: [LocalImageItem] = []

        for child in children {
            if Task.isCancelled { return nil }
            guard let values = try? child.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory == true,
               values.isSymbolicLink != true,
               values.isPackage != true {
                if let folder = scanFolder(
                    at: child,
                    excluding: excludedFolderPaths,
                    visitedDirectoryPaths: &visitedDirectoryPaths
                ), folder.imageCount > 0 {
                    folders.append(folder)
                }
            } else if values.isRegularFile == true,
                      values.contentType?.conforms(to: .image) == true {
                let imageURL = child.standardizedFileURL
                // 先查 mtime/fileSize 缓存,未变时复用像素尺寸,避免重扫全量读图头。
                let pixelSize = localPixelSizeCache.size(for: imageURL)
                images.append(LocalImageItem(
                    url: imageURL,
                    title: child.lastPathComponent,
                    pixelWidth: pixelSize?.width,
                    pixelHeight: pixelSize?.height
                ))
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

    private var isAllImagesSelected: Bool {
        selectedFolderID == Self.allImagesFolderID
    }

    private func invalidateAllImagesCache() {
        cachedAllImages = []
        cachedAllImagesRootSignature = []
    }

    private var allImages: [LocalImageItem] {
        let signature = roots.map { "\($0.id):\($0.imageCount)" }
        if signature == cachedAllImagesRootSignature {
            return cachedAllImages
        }
        var images: [LocalImageItem] = []
        var seenPaths = Set<String>()
        for root in roots {
            Self.appendImages(from: root.tree, to: &images, seenPaths: &seenPaths)
        }
        cachedAllImages = images
        cachedAllImagesRootSignature = signature
        return images
    }

    private static func appendImages(
        from folder: LocalFolderNode,
        to images: inout [LocalImageItem],
        seenPaths: inout Set<String>
    ) {
        for image in folder.images {
            let path = image.url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seenPaths.insert(path).inserted else { continue }
            images.append(image)
        }
        for child in folder.folders {
            appendImages(from: child, to: &images, seenPaths: &seenPaths)
        }
    }

    private func clampSelectedImageIndex() {
        selectedImageIndex = min(selectedImageIndex, max(selectedImages.count - 1, 0))
    }

    private static func contains(folderID: String, in folder: LocalFolderNode) -> Bool {
        folder.id == folderID || folder.folders.contains { contains(folderID: folderID, in: $0) }
    }
}

/// 像素尺寸缓存:(mtime, fileSize) 未变时直接复用,重扫/导入不再全量读图头。
/// 多个根目录的扫描任务并发执行,锁保护共享字典。
nonisolated final class LocalPixelSizeCache: @unchecked Sendable {
    private struct Entry {
        let modificationDate: Date?
        let fileSize: Int
        let size: (width: Int, height: Int)?
        var lastAccess: UInt64
    }

    private let lock = NSLock()
    private var entries: [URL: Entry] = [:]
    private var accessCounter: UInt64 = 0
    private let maxEntryCount: Int
    private let trimTargetCount: Int

    init(maxEntryCount: Int = 20_000) {
        self.maxEntryCount = max(maxEntryCount, 1)
        self.trimTargetCount = max(Int(Double(maxEntryCount) * 0.9), 1)
    }

    func size(for url: URL) -> (width: Int, height: Int)? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        // stat 失败(文件刚被移动/删除)时不缓存,直接读图头。
        guard let fileSize = values?.fileSize else {
            return pixelSize(for: url)
        }
        let modificationDate = values?.contentModificationDate
        lock.lock()
        accessCounter &+= 1
        if var entry = entries[url],
           entry.modificationDate == modificationDate,
           entry.fileSize == fileSize {
            entry.lastAccess = accessCounter
            entries[url] = entry
            lock.unlock()
            return entry.size
        }
        lock.unlock()
        // 图头读取放锁外,保持多根目录扫描的并发性;并发 miss 时重复读取结果相同。
        let size = pixelSize(for: url)
        lock.lock()
        accessCounter &+= 1
        entries[url] = Entry(
            modificationDate: modificationDate,
            fileSize: fileSize,
            size: size,
            lastAccess: accessCounter
        )
        trimIfNeeded()
        lock.unlock()
        return size
    }

    func removeEntries(under rootURL: URL) {
        let rootPath = rootURL.standardizedFileURL.path
        let childPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        lock.lock()
        entries = entries.filter { url, _ in
            let path = url.standardizedFileURL.path
            return path != rootPath && !path.hasPrefix(childPrefix)
        }
        lock.unlock()
    }

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    private func trimIfNeeded() {
        guard entries.count > maxEntryCount else { return }
        let removeCount = entries.count - trimTargetCount
        let oldestURLs = entries
            .sorted { $0.value.lastAccess < $1.value.lastAccess }
            .prefix(removeCount)
            .map(\.key)
        for url in oldestURLs {
            entries[url] = nil
        }
    }
}

nonisolated private let localPixelSizeCache = LocalPixelSizeCache()
