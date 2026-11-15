import Foundation
import CoreGraphics

public enum PictureExportSize: String, Codable, CaseIterable, Identifiable, Sendable {
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
    /// The largest centered picture frame that fits inside the visible 3D viewport.
    public static func frame(for pictureSize:CGSize,in viewport:CGRect)->CGRect {
        guard pictureSize.width>0,pictureSize.height>0,viewport.width>0,viewport.height>0 else { return .zero }
        let scale=min(viewport.width/pictureSize.width,viewport.height/pictureSize.height)
        let size=CGSize(width:pictureSize.width*scale,height:pictureSize.height*scale)
        return CGRect(x:viewport.midX-size.width/2,y:viewport.midY-size.height/2,width:size.width,height:size.height)
    }
    public func frame(in viewport:CGRect)->CGRect {
        Self.frame(for:pixelSize(viewport:viewport.size),in:viewport)
    }
}
