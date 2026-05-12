import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalImageDetailPane: View {
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    @State private var resetToken = UUID()
    @State private var saveMessage = ""
    private let headerHeight: CGFloat = 54
    private let filmstripHeight: CGFloat = 112

    var body: some View {
        if let folder = localLibrary.selectedFolder, let image = localLibrary.selectedImage {
            ZStack {
                ZStack {
                    Color(red: 0.06, green: 0.06, blue: 0.065)

                    GeometryReader { proxy in
                        let maxPixelSize = max(proxy.size.width, proxy.size.height) * 2
                        ZoomableImageCanvas(
                            url: image.url,
                            resetToken: resetToken,
                            contentInsets: EdgeInsets(top: headerHeight, leading: 0, bottom: filmstripHeight, trailing: 0),
                            localMaxPixelSize: maxPixelSize
                        ) {
                            DetailPlaceholder(kind: .loading)
                        } onDisplayed: {}
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .clipped()

                    HStack {
                        StepButton(systemName: "chevron.left") { localLibrary.stepImage(-1) }
                            .disabled(localLibrary.selectedImageIndex == 0)
                        Spacer()
                        StepButton(systemName: "chevron.right") { localLibrary.stepImage(1) }
                            .disabled(localLibrary.selectedImageIndex >= localLibrary.selectedImages.count - 1)
                    }
                    .padding(.horizontal, 18)
                }

                VStack(spacing: 0) {
                    header(folder: folder, image: image)
                        .frame(height: headerHeight)
                    Spacer()
                    LocalFilmstrip(images: localLibrary.selectedImages, selectedIndex: localLibrary.selectedImageIndex) { index in
                        localLibrary.selectImage(at: index)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: image.id) { _, _ in
                resetToken = UUID()
                saveMessage = ""
            }
        } else {
            ContentUnavailableView("没有可显示图片", systemImage: "photo")
        }
    }

    private func header(folder: LocalFolderNode, image: LocalImageItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(localLibrary.selectedImageIndex + 1) / \(localLibrary.selectedImages.count) · \(image.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Spacer()

            if !saveMessage.isEmpty {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                localLibrary.isFullscreenViewerPresented = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 22)
            }
            .help("全屏")

            Button {
                resetToken = UUID()
            } label: {
                Image(systemName: "1.magnifyingglass")
                    .frame(width: 22)
            }
            .help("实际大小")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([image.url])
            } label: {
                Image(systemName: "finder")
                    .frame(width: 22)
            }
            .help("在 Finder 中显示")

            Button {
                saveImage(image)
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 22)
            }
            .help("保存副本")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private func saveImage(_ image: LocalImageItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.image]
        panel.nameFieldStringValue = image.title
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }

        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: image.url, to: target)
            saveMessage = "已保存"
        } catch {
            saveMessage = "保存失败"
        }
    }
}

struct LocalFilmstrip: View {
    let images: [LocalImageItem]
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(images.indices, id: \.self) { index in
                        let image = images[index]
                        Button {
                            onSelect(index)
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                LocalImageThumbnail(url: image.url)
                                Text("#\(index + 1)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.5), in: Capsule())
                                    .padding(5)
                            }
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedIndex == index ? Color.accentColor : Color.white.opacity(0.15), lineWidth: selectedIndex == index ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(height: 112)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider().opacity(0.35)
            }
            .onChange(of: selectedIndex) { _, index in
                guard images.indices.contains(index) else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    scrollProxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
}

private struct LocalImageThumbnail: View {
    let url: URL

    var body: some View {
        RemoteImageView(url: url, contentMode: .fill, priority: .utility, localMaxPixelSize: 220) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .overlay(Image(systemName: "photo").font(.caption).foregroundStyle(.secondary))
        }
        .frame(width: 72, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
