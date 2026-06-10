import CoreImage
import Foundation
import MovieCutCore

final class MaskCompositor {
    static func apply(mask: Mask, to image: CIImage, at time: TimeInterval) -> CIImage {
        MaskPixelProcessor.apply(mask, to: image, at: time)
    }
}
