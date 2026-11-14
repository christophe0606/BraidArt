import Foundation
import CoreGraphics

public enum PictureExportSize: String, CaseIterable, Identifiable, Sendable {
    case viewport, hd, fullHD, ultraHD, instagramSquare, instagramPortrait, instagramTallPortrait, instagramLandscape, instagramStory
    public var id:String { rawValue }
    public var title:String {
        switch self {
        case .viewport: return "Current viewport"
        case .hd: return "HD — 1280 × 720"
        case .fullHD: return "Full HD — 1920 × 1080"
        case .ultraHD: return "4K UHD — 3840 × 2160"
        case .instagramSquare: return "Instagram Square — 1080 × 1080 (1:1)"
        case .instagramPortrait: return "Instagram Portrait — 1080 × 1350 (4:5)"
        case .instagramTallPortrait: return "Instagram Tall Portrait — 1080 × 1440 (3:4)"
        case .instagramLandscape: return "Instagram Landscape — 1080 × 566 (1.91:1)"
        case .instagramStory: return "Instagram Story — 1080 × 1920 (9:16)"
        }
    }
    public func pixelSize(viewport:CGSize)->CGSize {
        switch self {
        case .viewport: return viewport
        case .hd: return CGSize(width:1280,height:720)
        case .fullHD: return CGSize(width:1920,height:1080)
        case .ultraHD: return CGSize(width:3840,height:2160)
        case .instagramSquare: return CGSize(width:1080,height:1080)
        case .instagramPortrait: return CGSize(width:1080,height:1350)
        case .instagramTallPortrait: return CGSize(width:1080,height:1440)
        case .instagramLandscape: return CGSize(width:1080,height:566)
        case .instagramStory: return CGSize(width:1080,height:1920)
        }
    }
}
