import SwiftUI

struct LocalFullscreenImageViewerOverlay: View {
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    @State private var resetToken = UUID()
    @State private var isChromeHidden = false

    var body: some View {
        if localLibrary.isFullscreenViewerPresented {
            ZStack {
                Color.black.ignoresSafeArea()

                if let folder = localLibrary.selectedFolder, let image = localLibrary.selectedImage {
                    if isChromeHidden {
                        GeometryReader { proxy in
                            ZoomableImageCanvas(url: image.url, resetToken: resetToken, contentInsets: .init()) {
                                DetailPlaceholder(kind: .loading)
                            } onDisplayed: {}
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                        .clipped()
                        restoreChromeButton()
                    } else {
                        ZStack {
                            GeometryReader { proxy in
                                ZoomableImageCanvas(
                                    url: image.url,
                                    resetToken: resetToken,
                                    contentInsets: EdgeInsets(top: 54, leading: 0, bottom: 112, trailing: 0)
                                ) {
                                    DetailPlaceholder(kind: .loading)
                                } onDisplayed: {}
                                .frame(width: proxy.size.width, height: proxy.size.height)
                            }
                            .clipped()
                            VStack(spacing: 0) {
                                fullscreenHeader(folder: folder, image: image)
                                    .frame(height: 54)
                                Spacer()
                                LocalFilmstrip(images: localLibrary.selectedImages, selectedIndex: localLibrary.selectedImageIndex) { index in
                                    localLibrary.selectImage(at: index)
                                }
                            }
                        }
                    }

                    HStack {
                        StepButton(systemName: "chevron.left") { localLibrary.stepImage(-1) }
                            .disabled(localLibrary.selectedImageIndex == 0)
                        Spacer()
                        StepButton(systemName: "chevron.right") { localLibrary.stepImage(1) }
                            .disabled(localLibrary.selectedImageIndex >= localLibrary.selectedImages.count - 1)
                    }
                    .padding(.horizontal, 24)
                } else {
                    ContentUnavailableView("没有可显示图片", systemImage: "photo")
                }
            }
            .transition(.opacity)
            .zIndex(20)
            .onChange(of: localLibrary.selectedImage?.id) { _, _ in
                resetToken = UUID()
            }
            .onExitCommand {
                localLibrary.isFullscreenViewerPresented = false
            }
        }
    }

    private func fullscreenHeader(folder: LocalFolderNode, image: LocalImageItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.title)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(localLibrary.selectedImageIndex + 1) / \(localLibrary.selectedImages.count) · \(image.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                resetToken = UUID()
            } label: {
                Label("实际大小", systemImage: "1.magnifyingglass")
            }

            Button {
                isChromeHidden = true
            } label: {
                Label("隐藏控制", systemImage: "rectangle.compress.vertical")
            }

            Button {
                localLibrary.isFullscreenViewerPresented = false
            } label: {
                Label("关闭", systemImage: "xmark")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    private func restoreChromeButton() -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    isChromeHidden = false
                } label: {
                    Label("显示控制", systemImage: "rectangle.expand.vertical")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(14)
            }
            Spacer()
        }
    }
}
