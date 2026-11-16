import Foundation
import CoreGraphics

public struct CustomPictureSize: Codable, Hashable, Sendable {
    public let id:UUID
    public let name:String
    public let width:Int
    public let height:Int
    public init(id:UUID = UUID(),name:String,width:Int,height:Int) throws {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.count<=80 else { throw BraidError.invalid(L("Enter a name between 1 and 80 characters.")) }
        guard (1...8192).contains(width),(1...8192).contains(height) else {
            throw BraidError.invalid(L("Picture dimensions must be whole pixels between 1 and 8192."))
        }
        self.id=id;self.name=name;self.width=width;self.height=height
    }
    private enum CodingKeys:String,CodingKey { case id,name,width,height }
    public init(from decoder:Decoder) throws {
        let values=try decoder.container(keyedBy:CodingKeys.self)
        try self.init(id:values.decode(UUID.self,forKey:.id),name:values.decode(String.self,forKey:.name),
                      width:values.decode(Int.self,forKey:.width),height:values.decode(Int.self,forKey:.height))
    }
}

public enum PictureExportSize: Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case viewport, hd, fullHD, quadHD, ultraHD, tikTokVideo, vertical4K
    case instagramSquare, instagramPortrait, instagramTallPortrait, instagramLandscape, instagramStory, instagramReels
    case instagramFeedVideo, instagramSquareVideo, instagramLandscapeVideo
    case custom(CustomPictureSize)
    public static let allCases:[Self] = [.viewport,.hd,.fullHD,.quadHD,.ultraHD,.tikTokVideo,.vertical4K,
        .instagramSquare,.instagramPortrait,.instagramTallPortrait,.instagramLandscape,.instagramStory,.instagramReels,
        .instagramFeedVideo,.instagramSquareVideo,.instagramLandscapeVideo]
    public var rawValue:String {
        switch self {
        case .viewport: return "viewport"
        case .hd: return "hd"
        case .fullHD: return "fullHD"
        case .quadHD: return "quadHD"
        case .ultraHD: return "ultraHD"
        case .tikTokVideo: return "tikTokVideo"
        case .vertical4K: return "vertical4K"
        case .instagramSquare: return "instagramSquare"
        case .instagramPortrait: return "instagramPortrait"
        case .instagramTallPortrait: return "instagramTallPortrait"
        case .instagramLandscape: return "instagramLandscape"
        case .instagramStory: return "instagramStory"
        case .instagramReels: return "instagramReels"
        case .instagramFeedVideo: return "instagramFeedVideo"
        case .instagramSquareVideo: return "instagramSquareVideo"
        case .instagramLandscapeVideo: return "instagramLandscapeVideo"
        case .custom(let size): return "custom-\(size.id.uuidString)"
        }
    }
    public var id:String { rawValue }
    public var customSize:CustomPictureSize? { if case .custom(let size)=self { return size };return nil }
    // Keep built-ins encoded as their original strings so existing projects remain readable.
    public init(from decoder:Decoder) throws {
        if let raw=try? decoder.singleValueContainer().decode(String.self) {
            guard let preset=Self.allCases.first(where:{$0.rawValue==raw}) else {
                throw DecodingError.dataCorrupted(.init(codingPath:decoder.codingPath,debugDescription:"Unknown picture size"))
            }
            self=preset
        } else { self = .custom(try CustomPictureSize(from:decoder)) }
    }
    public func encode(to encoder:Encoder) throws {
        if case .custom(let size)=self { try size.encode(to:encoder) }
        else { var value=encoder.singleValueContainer();try value.encode(rawValue) }
    }
    public static let imageSizes:[Self] = [.instagramSquare,.instagramPortrait,.instagramTallPortrait,.instagramLandscape,.instagramStory]
    public static let videoSizes:[Self] = [.hd,.fullHD,.quadHD,.ultraHD,.vertical4K,.tikTokVideo,
        .instagramReels,.instagramFeedVideo,.instagramSquareVideo,.instagramLandscapeVideo]
    /// Fixed dimensions available for the source crop and woven image, grouped by use.
    public static var outputSizes:[Self] { imageSizes+videoSizes }
    public var title:String {
        switch self {
        case .viewport: return L("Current viewport")
        case .hd: return L("720p HD — 1280 × 720")
        case .fullHD: return L("1080p Full HD — 1920 × 1080")
        case .quadHD: return L("1440p QHD — 2560 × 1440")
        case .ultraHD: return L("4K UHD — 3840 × 2160")
        case .tikTokVideo: return L("TikTok / YouTube Shorts — 1080 × 1920 (9:16)")
        case .vertical4K: return L("4K Vertical — 2160 × 3840 (9:16)")
        case .instagramSquare: return L("Instagram Square — 1080 × 1080 (1:1)")
        case .instagramPortrait: return L("Instagram Portrait — 1080 × 1350 (4:5)")
        case .instagramTallPortrait: return L("Instagram Tall Portrait — 1080 × 1440 (3:4)")
        case .instagramLandscape: return L("Instagram Landscape — 1080 × 566 (1.91:1)")
        case .instagramStory: return L("Instagram Story — 1080 × 1920 (9:16)")
        case .instagramReels: return L("Instagram Reels / Video — 1080 × 1920 (9:16)")
        case .instagramFeedVideo: return L("Instagram Feed Video — 1080 × 1350 (4:5)")
        case .instagramSquareVideo: return L("Instagram Square Video — 1080 × 1080 (1:1)")
        case .instagramLandscapeVideo: return L("Instagram Landscape Video — 1920 × 1080 (16:9)")
        case .custom(let size): return L("%@ — %@ × %@",size.name,String(size.width),String(size.height))
        }
    }
    public func pixelSize(viewport:CGSize)->CGSize {
        switch self {
        case .viewport: return viewport
        case .hd: return CGSize(width:1280,height:720)
        case .fullHD: return CGSize(width:1920,height:1080)
        case .quadHD: return CGSize(width:2560,height:1440)
        case .ultraHD: return CGSize(width:3840,height:2160)
        case .tikTokVideo: return CGSize(width:1080,height:1920)
        case .vertical4K: return CGSize(width:2160,height:3840)
        case .instagramSquare: return CGSize(width:1080,height:1080)
        case .instagramPortrait: return CGSize(width:1080,height:1350)
        case .instagramTallPortrait: return CGSize(width:1080,height:1440)
        case .instagramLandscape: return CGSize(width:1080,height:566)
        case .instagramStory: return CGSize(width:1080,height:1920)
        case .instagramReels: return CGSize(width:1080,height:1920)
        case .instagramFeedVideo: return CGSize(width:1080,height:1350)
        case .instagramSquareVideo: return CGSize(width:1080,height:1080)
        case .instagramLandscapeVideo: return CGSize(width:1920,height:1080)
        case .custom(let size): return CGSize(width:size.width,height:size.height)
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
