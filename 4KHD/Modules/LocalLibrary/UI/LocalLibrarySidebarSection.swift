import SwiftUI

struct LocalLibrarySidebarSection: View {
    @Environment(LocalLibraryStore.self) private var localLibrary
    @Environment(SidebarDisclosureState.self) private var sidebarDisclosure

    @Binding var selection: WorkspaceRoute?
    let importRootFolder: () -> Void

    var body: some View {
        Section("本地") {
            if localLibrary.isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                    Text(localLibrary.roots.isEmpty ? "正在扫描目录" : "正在更新目录")
                }
                .foregroundStyle(.secondary)
            }

            if localLibrary.roots.isEmpty && !localLibrary.isScanning {
                Button {
                    importRootFolder()
                } label: {
                    Label("导入本地目录", systemImage: "folder.badge.plus")
                }
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            } else {
                ForEach(localLibrary.roots) { root in
                    LocalFolderSidebarRow(folder: root.tree, level: 0)
                }
            }
        }
    }
}

private struct LocalFolderSidebarRow: View {
    @Environment(LocalLibraryStore.self) private var localLibrary
    @Environment(SidebarDisclosureState.self) private var sidebarDisclosure

    let folder: LocalFolderNode
    let level: Int

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { sidebarDisclosure.isExpanded(folder.id) },
            set: { sidebarDisclosure.setExpanded($0, for: folder.id) }
        )
    }

    private var leafLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title).lineLimit(1)
                Text("\(folder.imageCount) 张")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: folder.images.isEmpty ? "folder" : "folder.fill")
                .foregroundStyle(.tint)
        }
    }

    var body: some View {
        if folder.folders.isEmpty {
            leafLabel
                .tag(WorkspaceRoute(moduleID: .localLibrary, itemID: folder.id))
                .contextMenu {
                    Button("移除目录") { localLibrary.removeFolder(folder) }
                }
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(folder.folders) { child in
                    LocalFolderSidebarRow(folder: child, level: level + 1)
                }
            } label: {
                leafLabel
                    .contextMenu {
                        Button("移除目录") { localLibrary.removeFolder(folder) }
                    }
            }
            .tag(WorkspaceRoute(moduleID: .localLibrary, itemID: folder.id))
        }
    }
}
