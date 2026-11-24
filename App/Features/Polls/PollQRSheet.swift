import CoreImage.CIFilterBuiltins
import SwiftUI
import VomattCore

/// A Poll's link as a QR code to scan from this screen, with the link to copy (the web's `PollQrDialog`).
struct PollQRSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let poll: Poll

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(poll.title).displayHeading(20)
                        Text(app.t("poll.qrHint")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let code = Self.code(for: app.shareURL(for: poll)) {
                        // Its own black on white in both themes: scanners read dark modules on a light ground
                        Image(code, scale: 1, label: Text(app.t("poll.qrLabel")))
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 256)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                    }
                    Button { app.copyLink(of: poll) } label: {
                        Label(app.t("poll.copyLink"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.vm(.outline, fullWidth: true))
                }
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Tokens.card)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(app.t("common.close")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static let context = CIContext()

    /// One pixel per module, with the 4 blank modules a scanner needs around the code
    /// (Core Image leaves 1, so 3 more of white).
    private static func code(for url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let code = filter.outputImage else { return nil }
        let extent = code.extent.insetBy(dx: -3, dy: -3)
        let framed = code.composited(over: CIImage(color: .white).cropped(to: extent))
        return context.createCGImage(framed, from: extent)
    }
}
