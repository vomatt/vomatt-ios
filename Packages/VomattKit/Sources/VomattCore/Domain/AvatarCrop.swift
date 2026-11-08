import CoreGraphics
import Foundation

/// Framing a picked photo for the avatar (the web's `CropStage` and `cropImage`): the image fills a square box
/// at zoom 1, can be zoomed up to 3x and dragged, and the square under the box is what's uploaded.
public enum AvatarCrop {
    /// What the API stores; cropping to it here makes the API's own center crop a no-op.
    public static let outputSide: CGFloat = 512
    public static let zoomRange: ClosedRange<CGFloat> = 1...3
    /// Bounds the full-size decode; what's uploaded is the 512 px crop, far under the API's 2 MB.
    public static let maxPickBytes = 25 * 1024 * 1024

    public enum Rejection: Equatable, Sendable { case unsupported, tooLarge }

    /// Why a picked file can't be framed, if it can't: the API takes JPEG, PNG, GIF and BMP, told apart by
    /// their leading bytes, and the type is checked before the size, as on the web.
    public static func check(_ data: Data) -> Rejection? {
        let signatures: [[UInt8]] = [[0xFF, 0xD8, 0xFF], [0x89, 0x50, 0x4E, 0x47], Array("GIF8".utf8), Array("BM".utf8)]
        guard signatures.contains(where: { data.starts(with: $0) }) else { return .unsupported }
        return data.count > maxPickBytes ? .tooLarge : nil
    }

    /// `offset` (points, from centered) held to where the image still covers the whole box.
    public static func clamp(_ offset: CGSize, image: CGSize, box: CGFloat, zoom: CGFloat) -> CGSize {
        let scale = scale(image: image, box: box, zoom: zoom)
        let maxX = max(0, (image.width * scale - box) / 2)
        let maxY = max(0, (image.height * scale - box) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    /// The square of the image (in its pixels) that shows in the box.
    public static func cropRect(image: CGSize, box: CGFloat, zoom: CGFloat, offset: CGSize) -> CGRect {
        let scale = scale(image: image, box: box, zoom: zoom)
        let side = box / scale
        return CGRect(
            x: image.width / 2 - offset.width / scale - side / 2,
            y: image.height / 2 - offset.height / scale - side / 2,
            width: side,
            height: side
        )
    }

    /// Box points per image pixel: the short side fills the box at zoom 1.
    private static func scale(image: CGSize, box: CGFloat, zoom: CGFloat) -> CGFloat {
        box / min(image.width, image.height) * zoom
    }
}
