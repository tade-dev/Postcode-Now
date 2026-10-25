import Foundation

public struct RingState: Equatable, Sendable {
    public var radius: Double
    public var opacity: Double
    public var lineWidth: Double

    public init(radius: Double, opacity: Double, lineWidth: Double) {
        self.radius = radius
        self.opacity = opacity
        self.lineWidth = lineWidth
    }
}

public struct CharacterState: Equatable, Sendable {
    public var opacity: Double
    public var offsetY: Double
    public var scale: Double
    /// 0 renders the medium weight, 1 the bold. Crossfaded between.
    public var weightBlend: Double

    public init(opacity: Double, offsetY: Double, scale: Double, weightBlend: Double) {
        self.opacity = opacity
        self.offsetY = offsetY
        self.scale = scale
        self.weightBlend = weightBlend
    }
}

/// Everything the canvas needs to draw one frame. Pure data: no UIKit,
/// no SwiftUI, no geometry the view owns.
public struct RevealSample: Equatable, Sendable {
    public var rings: [RingState]
    public var lockRadius: Double
    public var lockOpacity: Double
    /// Fraction of the hero's width the line currently spans, 0...1.
    public var lineLength: Double
    public var lineThickness: Double
    public var lineOpacity: Double
    public var characters: [CharacterState]
    public var washProgress: Double
    public var captionOpacity: Double
    public var wordmarkOpacity: Double
    public var sectionOpacity: Double
    public var districtOpacity: Double
    public var districtOffset: Double
    public var ctaOpacity: Double
    public var ctaOffset: Double
    public var bannerOpacity: Double

    public static func settled(outcodeCount: Int, incodeCount: Int) -> RevealSample {
        RevealSample(
            rings: Array(
                repeating: RingState(radius: RevealTiming.lockRadius, opacity: 0, lineWidth: 1),
                count: RevealTiming.scanRingCount
            ),
            lockRadius: RevealTiming.lockRadius,
            lockOpacity: 0,
            lineLength: 1,
            lineThickness: 0,
            lineOpacity: 0,
            characters: Array(
                repeating: CharacterState(opacity: 1, offsetY: 0, scale: 1, weightBlend: 1),
                count: max(0, outcodeCount + incodeCount)
            ),
            washProgress: 1,
            captionOpacity: 0,
            wordmarkOpacity: 1,
            sectionOpacity: 1,
            districtOpacity: 1,
            districtOffset: 0,
            ctaOpacity: 1,
            ctaOffset: 0,
            bannerOpacity: 1
        )
    }
}
