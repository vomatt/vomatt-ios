import CoreGraphics
import Foundation
import Testing
@testable import VomattCore

@Suite("Avatar crop")
struct AvatarCropTests {
    private let wide = CGSize(width: 1000, height: 500)

    @Test(arguments: [
        [0xFF, 0xD8, 0xFF, 0xE0],
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        Array("GIF89a".utf8),
        Array("BM6".utf8),
    ] as [[UInt8]])
    func acceptsTheTypesTheAPITakes(bytes: [UInt8]) {
        #expect(AvatarCrop.check(Data(bytes)) == nil)
    }

    @Test func rejectsAHEICPhoto() {
        let heic = Data([0, 0, 0, 0x18] + Array("ftypheic".utf8))
        #expect(AvatarCrop.check(heic) == .unsupported)
    }

    @Test func rejectsAnEmptyFile() {
        #expect(AvatarCrop.check(Data()) == .unsupported)
    }

    @Test func rejectsAPickOver25MB() {
        let jpeg = Data([0xFF, 0xD8, 0xFF]) + Data(count: 25 * 1024 * 1024)
        #expect(AvatarCrop.check(jpeg) == .tooLarge)
    }

    @Test func acceptsAPickOfExactly25MB() {
        let jpeg = Data([0xFF, 0xD8, 0xFF]) + Data(count: 25 * 1024 * 1024 - 3)
        #expect(AvatarCrop.check(jpeg) == nil)
    }

    @Test func namesTheTypeBeforeTheSize() {
        #expect(AvatarCrop.check(Data(count: 26 * 1024 * 1024)) == .unsupported)
    }

    @Test func cropsTheCenteredSquareOfTheShortSideAtZoomOne() {
        let rect = AvatarCrop.cropRect(image: wide, box: 300, zoom: 1, offset: .zero)
        #expect(rect == CGRect(x: 250, y: 0, width: 500, height: 500))
    }

    @Test func zoomingInCropsASmallerCenteredSquare() {
        let rect = AvatarCrop.cropRect(image: wide, box: 300, zoom: 2, offset: .zero)
        #expect(rect == CGRect(x: 375, y: 125, width: 250, height: 250))
    }

    @Test func draggingTheImageRightCropsFurtherLeft() {
        // 300 pt over 500 px: 0.6 pt per pixel, so 60 pt is 100 px
        let rect = AvatarCrop.cropRect(image: wide, box: 300, zoom: 1, offset: CGSize(width: 60, height: 0))
        #expect(rect == CGRect(x: 150, y: 0, width: 500, height: 500))
    }

    @Test func dragStopsAtTheImageEdge() {
        let offset = AvatarCrop.clamp(CGSize(width: 1000, height: -1000), image: wide, box: 300, zoom: 1)
        #expect(offset == CGSize(width: 150, height: 0))
        #expect(AvatarCrop.cropRect(image: wide, box: 300, zoom: 1, offset: offset).minX == 0)
    }

    @Test func zoomingInGivesTheDragMoreRoom() {
        let offset = AvatarCrop.clamp(CGSize(width: -1000, height: 1000), image: wide, box: 300, zoom: 2)
        #expect(offset == CGSize(width: -450, height: 150))
        let rect = AvatarCrop.cropRect(image: wide, box: 300, zoom: 2, offset: offset)
        #expect(rect == CGRect(x: 750, y: 0, width: 250, height: 250))
    }
}
