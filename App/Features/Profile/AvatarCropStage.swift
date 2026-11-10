import ImageIO
import SwiftUI
import VomattCore

/// Framing the picked photo in a circle (the web's `CropStage`): drag to move, pinch or the slider to zoom,
/// then upload just that square as a 512 px JPEG.
struct AvatarCropStage: View {
    @Environment(AppModel.self) private var app
    let image: CGImage
    let onCancel: () -> Void
    let onDone: () -> Void
    @Binding var isUploading: Bool
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var dragStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var box: CGFloat = 0

    private var pixels: CGSize { CGSize(width: image.width, height: image.height) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(app.t("avatar.crop.body")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                frame
                HStack(spacing: 12) {
                    Text(app.t("avatar.crop.zoom")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                    Slider(value: $zoom, in: AvatarCrop.zoomRange) { Text(app.t("avatar.crop.zoom")) }
                        .tint(Tokens.primary)
                }
                .frame(minHeight: Metrics.minTarget)
            }
            .padding(Metrics.gutter)
        }
        .canvas()
        .navigationTitle(app.t("avatar.crop.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(app.t("common.cancel"), action: onCancel).disabled(isUploading) }
            ToolbarItem(placement: .confirmationAction) {
                LoadingButton(style: .vm(.link), isLoading: isUploading, action: upload) {
                    Text(app.t("avatar.crop.use")).fontWeight(.semibold)
                }
            }
        }
        .onChange(of: zoom) { offset = clamped(offset) }
    }

    /// The photo filling a square at zoom 1, veiled outside the circle that becomes the avatar.
    private var frame: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { box = $0 }
            .overlay {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: box, height: box)
                    .scaleEffect(zoom)
                    .offset(offset)
            }
            .overlay {
                Path { path in
                    path.addRect(CGRect(x: 0, y: 0, width: box, height: box))
                    path.addEllipse(in: CGRect(x: 0, y: 0, width: box, height: box))
                }
                .fill(Tokens.background.opacity(0.7), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            }
            .overlay { Circle().strokeBorder(Tokens.borderStrong).allowsHitTesting(false) }
            .contentShape(Rectangle())
            .gesture(drag.simultaneously(with: pinch))
            .background(Tokens.field)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .accessibilityElement()
        .accessibilityLabel(app.t("avatar.crop.title"))
        .accessibilityAddTraits(.isImage)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? offset
                dragStart = start
                offset = clamped(CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? zoom
                zoomStart = start
                zoom = min(max(start * value.magnification, AvatarCrop.zoomRange.lowerBound), AvatarCrop.zoomRange.upperBound)
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func clamped(_ offset: CGSize) -> CGSize {
        AvatarCrop.clamp(offset, image: pixels, box: box, zoom: zoom)
    }

    private func upload() async {
        guard box > 0 else { return }
        isUploading = true
        defer { isUploading = false }
        let rect = AvatarCrop.cropRect(image: pixels, box: box, zoom: zoom, offset: offset)
        let image = image
        guard let jpeg = await Task.detached(priority: .userInitiated, operation: { Self.jpeg(image, crop: rect) }).value else {
            app.showToast(app.t("avatar.upload.unsupported"), isError: true)
            onCancel()
            return
        }
        do {
            let updated = try await app.service.uploadAvatar(jpeg)
            app.updateMe { $0.avatarUrl = updated.avatarUrl }
            app.showToast(app.t("avatar.savedToast"))
            onDone()
        } catch {
            app.showToast(app.t.message(for: error, fallback: "account.saveFailed"), isError: true)
        }
    }

    /// `crop` (image pixels) as the square JPEG the API stores.
    nonisolated private static func jpeg(_ image: CGImage, crop: CGRect) -> Data? {
        guard let cropped = image.cropping(to: crop.integral) else { return nil }
        let side = AvatarCrop.outputSide
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).jpegData(withCompressionQuality: 0.9) { context in
            // JPEG has no alpha; white is what the API puts behind a transparent PNG
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// The picked photo upright and no larger than needed: at 3x zoom a 4:3 or 16:9 photo still gives 512 px.
    nonisolated static func decode(_ data: Data, maxPixels: Int = 3072) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
