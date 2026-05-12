import AppKit
import SwiftUI

struct LocalFolderPane: View {
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    @State private var expandedFolderIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地图库")
                        .font(.headline)
                    Text("\(localLibrary.roots.count) 个根目录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    importRootFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .frame(width: 22)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("导入本地图片文件夹")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if localLibrary.roots.isEmpty {
                ContentUnavailableView("还没有本地目录", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(localLibrary.roots) { root in
                            LocalRootFolderRow(
                                root: root,
                                isExpanded: expandedFolderIDs.contains(root.tree.id),
                                isSelected: localLibrary.selectedFolder?.id == root.tree.id
                            ) {
                                toggle(root.tree.id)
                                localLibrary.selectFolder(root.tree)
                            }
                            .contextMenu {
                                Button("移除目录") {
                                    localLibrary.removeFolder(root.tree)
                                }
                            }

                            if expandedFolderIDs.contains(root.tree.id) {
                                LocalFolderTree(
                                    folder: root.tree,
                                    level: 1,
                                    expandedFolderIDs: $expandedFolderIDs
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .onAppear {
            if expandedFolderIDs.isEmpty {
                expandedFolderIDs.formUnion(localLibrary.roots.map(\.tree.id))
            }
        }
    }

    private func toggle(_ id: String) {
        if expandedFolderIDs.contains(id) {
            expandedFolderIDs.remove(id)
        } else {
            expandedFolderIDs.insert(id)
        }
    }

    private func importRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "导入"
        panel.message = "选择一个包含图片的文件夹"

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        localLibrary.importRootFolder(folderURL)
        expandedFolderIDs.insert(folderURL.standardizedFileURL.path)
    }
}

private struct LocalFolderTree: View {
    @EnvironmentObject private var localLibrary: LocalLibraryStore

    let folder: LocalFolderNode
    let level: Int
    @Binding var expandedFolderIDs: Set<String>

    var body: some View {
        ForEach(folder.folders) { child in
            LocalFolderRow(
                folder: child,
                level: level,
                isExpanded: expandedFolderIDs.contains(child.id),
                isSelected: localLibrary.selectedFolder?.id == child.id
            ) {
                toggle(child.id)
                localLibrary.selectFolder(child)
            }
            .contextMenu {
                Button("移除目录") {
                    localLibrary.removeFolder(child)
                }
            }

            if expandedFolderIDs.contains(child.id) {
                LocalFolderTree(folder: child, level: level + 1, expandedFolderIDs: $expandedFolderIDs)
            }
        }
    }

    private func toggle(_ id: String) {
        if expandedFolderIDs.contains(id) {
            expandedFolderIDs.remove(id)
        } else {
            expandedFolderIDs.insert(id)
        }
    }
}

private struct LocalRootFolderRow: View {
    let root: LocalLibraryRoot
    let isExpanded: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        LocalFolderRowContent(
            title: root.title,
            subtitle: "\(root.imageCount) 张 · \(root.url.path)",
            coverURL: root.tree.coverURL,
            isExpanded: isExpanded,
            indent: 0,
            isSelected: isSelected,
            action: action
        )
    }
}

private struct LocalFolderRow: View {
    let folder: LocalFolderNode
    let level: Int
    let isExpanded: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        LocalFolderRowContent(
            title: folder.title,
            subtitle: "\(folder.images.count) 张当前目录 · \(folder.imageCount) 张含子目录",
            coverURL: folder.coverURL,
            isExpanded: isExpanded,
            indent: CGFloat(level) * 16,
            isSelected: isSelected,
            action: action
        )
    }
}

private struct LocalFolderRowContent: View {
    let title: String
    let subtitle: String
    let coverURL: URL?
    let isExpanded: Bool
    let indent: CGFloat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Color.clear.frame(width: indent, height: 1)

                ZStack(alignment: .bottomTrailing) {
                    RemoteImageView(url: coverURL, contentMode: .fill, priority: .utility) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.secondary))
                    }
                    .frame(width: 46, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .padding(4)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
