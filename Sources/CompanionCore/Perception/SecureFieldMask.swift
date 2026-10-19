import CoreGraphics

/// Secure text fields are painted over in every screen frame before it
/// leaves the Mac. The AX tree gives each field's box in global points with
/// a top-left origin; a frame is pixels of one display. This file is the
/// geometry and the verdict; the painting lives in Services.
package enum SecureFieldMask {
    /// The AX box is the control; glyphs can spill a pixel or two past it.
    package static let padding: CGFloat = 2

    /// What an AX read of the captured apps found.
    package enum Read: Equatable, Sendable {
        case fields([CGRect])
        /// A failed, timed-out or over-budget read: the frame cannot prove it
        /// holds no secure field, so it is not sent.
        case incomplete(String)
    }

    package enum Plan: Equatable, Sendable {
        case mask([CGRect])
        case withhold(String)
    }

    package static func plan(read: Read, display: CGRect, imageWidth: Int, imageHeight: Int) -> Plan {
        switch read {
        case .incomplete(let reason):
            return .withhold(reason)
        case .fields(let frames):
            return .mask(pixelRects(
                for: frames, display: display, imageWidth: imageWidth, imageHeight: imageHeight))
        }
    }

    /// The display frame, not its pixel size, anchors the mapping: a display
    /// left of or above the main one has a negative origin in AX space, and
    /// the captured image can be scaled below native (see `maxSide`). Scaling
    /// comes from the real image size, so both cases fall out of one ratio.
    package static func pixelRects(
        for fields: [CGRect], display: CGRect, imageWidth: Int, imageHeight: Int
    ) -> [CGRect] {
        guard display.width > 0, display.height > 0, imageWidth > 0, imageHeight > 0 else {
            return []
        }
        // Multiply before dividing: a Retina or 1280-px frame lands on exact
        // pixel edges, and `integral` must not round a sub-pixel error up.
        let pixelsWide = CGFloat(imageWidth)
        let pixelsHigh = CGFloat(imageHeight)
        let image = CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh)
        return fields.compactMap { field in
            let local = CGRect(
                x: (field.minX - display.minX) * pixelsWide / display.width,
                y: (field.minY - display.minY) * pixelsHigh / display.height,
                width: field.width * pixelsWide / display.width,
                height: field.height * pixelsHigh / display.height)
            // `integral` rounds outward: a fractional edge must cover its pixel.
            let masked = local.insetBy(dx: -padding, dy: -padding).integral.intersection(image)
            return masked.isNull || masked.isEmpty ? nil : masked
        }
    }
}
