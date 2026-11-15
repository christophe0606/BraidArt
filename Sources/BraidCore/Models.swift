import Foundation

public enum BraidError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public struct RGB: Codable, Equatable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    public static let black = RGB(0, 0, 0)
    public static let white = RGB(1, 1, 1)
    public static let gray = RGB(0.5, 0.5, 0.5)
    public var valid: Bool { [r,g,b].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    public static func + (a: RGB, b: RGB) -> RGB { RGB(a.r+b.r, a.g+b.g, a.b+b.b) }
    public static func * (a: RGB, s: Double) -> RGB { RGB(a.r*s, a.g*s, a.b*s) }
}

/// Normalized coordinates, origin at the top left of the oriented source image.
public struct Crop: Codable, Equatable, Sendable {
    public var x: Double = 0
    public var y: Double = 0
    public var width: Double = 1
    public var height: Double = 1
    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) {
        self.x=x; self.y=y; self.width=width; self.height=height
    }
    public var valid: Bool {
        [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x+width <= 1.000001 && y+height <= 1.000001
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var crop = Crop()
    public var columns = 50
    public var partitionSize = 7
    public var strandWidth = 0.414
    public var gap = 0.4
    public var background = RGB.gray
    public var palette: [RGB] = [.black, .white]
    public var grayscale = false
    public var contrast = 1.0
    public var brightness = 0.0
    public var alphaBackground = RGB.black
    public var secondsPerPartition = 30.0
    public var relativeGap = 0.01
    public var threads = 4
    public init() {}
    public func hasSameImagePreparation(as other: Settings) -> Bool {
        crop == other.crop && columns == other.columns && grayscale == other.grayscale &&
        contrast == other.contrast && brightness == other.brightness && alphaBackground == other.alphaBackground
    }
    public func validate() throws {
        guard crop.valid, (8...256).contains(columns), (1...20).contains(partitionSize),
              (0.1...0.6).contains(strandWidth), (0...0.6).contains(gap), strandWidth+gap <= 0.98,
              (1...8).contains(palette.count), palette.allSatisfy(\.valid), Set(palette).count == palette.count,
              background.valid, alphaBackground.valid, (0.25...3).contains(contrast), (-0.5...0.5).contains(brightness),
              (1...600).contains(secondsPerPartition), (0...0.2).contains(relativeGap), (1...16).contains(threads)
        else { throw BraidError.invalid("Invalid image, palette, geometry, or solver settings.") }
    }
}

public struct PixelImage: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    /// sRGB samples in row-major order, top row first. One sample becomes one tile.
    public var pixels: [RGB]
    public init(width: Int, height: Int, pixels: [RGB]) { self.width=width; self.height=height; self.pixels=pixels }
    public func validate() throws {
        guard (1...256).contains(width), (1...256).contains(height), pixels.count == width*height, pixels.allSatisfy(\.valid)
        else { throw BraidError.invalid("Invalid sampled image (maximum 256 × 256 tiles).") }
    }
}

public enum TileKind: String, Codable, CaseIterable, Sendable {
    case vCross = "VCross", hCross = "HCross", circLeft = "CircLeft", circRight = "CircRight"
}
public struct Tile: Codable, Equatable, Sendable, Identifiable {
    /// Same one-based tile order as mkDarkTiles: type, then first color, then second color.
    public var id: Int
    public var kind: TileKind
    public var firstColor: Int
    public var secondColor: Int
    public var average: RGB
    public var top: Int
    public var right: Int
    public var bottom: Int
    public var left: Int
}
public struct TopologyGroup: Codable, Equatable, Sendable {
    public var color: Int
    public var outgoing: [Int]
    public var incoming: [Int]
}
public struct TileData: Codable, Equatable, Sendable {
    public var background: RGB
    public var palette: [RGB]
    public var strandWidth: Double
    public var gap: Double
    public var allTiles: [Tile]
    public var topologyH: [TopologyGroup]
    public var topologyV: [TopologyGroup]
    public var tileColorValue: [RGB]
    public init(settings: Settings) {
        background=settings.background; palette=settings.palette; strandWidth=settings.strandWidth; gap=settings.gap
        var tiles: [Tile] = []
        for kind in TileKind.allCases {
            for a in palette.indices { for b in palette.indices {
                let wb: Double, wc: Double
                switch kind {
                case .vCross: wb=1-strandWidth-gap; wc=strandWidth
                case .hCross: wb=strandWidth; wc=1-strandWidth-gap
                case .circLeft, .circRight: wb=Double.pi*strandWidth/4; wc=wb
                }
                let average = background*(1-wb-wc) + palette[a]*wb + palette[b]*wc
                let top = kind == .circLeft ? a : b
                let bottom = kind == .circRight ? a : b
                tiles.append(Tile(id: tiles.count+1, kind: kind, firstColor: a, secondColor: b,
                                  average: average, top: top, right: kind == .circLeft || kind == .circRight ? b : a,
                                  bottom: bottom, left: a))
            }}
        }
        allTiles=tiles
        tileColorValue=tiles.map(\.average)
        topologyH=palette.indices.map { color in TopologyGroup(color: color, outgoing: tiles.filter{$0.right == color}.map(\.id), incoming: tiles.filter{$0.left == color}.map(\.id)) }
        topologyV=palette.indices.map { color in TopologyGroup(color: color, outgoing: tiles.filter{$0.bottom == color}.map(\.id), incoming: tiles.filter{$0.top == color}.map(\.id)) }
    }
}

public struct PartitionReport: Codable, Equatable, Sendable {
    public var row: Int
    public var column: Int
    public var width: Int
    public var height: Int
    public var objective: Double
    public var provenOptimal: Bool
    public var solverStatus: String
    public var elapsedSeconds: Double
}
public struct SolveResult: Codable, Equatable, Sendable {
    /// One-based tile IDs; solution[row][column], top row first, matching Mathematica.
    public var solution: [[Int]]
    public var reports: [PartitionReport]
    public var costBackend: String
    public var elapsedSeconds: Double
    public var objective: Double { reports.reduce(0) { $0+$1.objective } }
    public var allPartitionsOptimal: Bool { reports.allSatisfy(\.provenOptimal) }
    public func validate(tileData: TileData) throws {
        guard let width=solution.first?.count, width>0, !solution.isEmpty, width<=256, solution.count<=256,
              solution.allSatisfy({$0.count == width}),
              solution.joined().allSatisfy({ (1...tileData.allTiles.count).contains($0) })
        else { throw BraidError.invalid("The solution contains invalid tile IDs or dimensions.") }
        for y in solution.indices { for x in 0..<width {
            let tile=tileData.allTiles[solution[y][x]-1]
            if x>0 && tileData.allTiles[solution[y][x-1]-1].right != tile.left { throw BraidError.invalid("Broken horizontal strand continuity at (\(x), \(y)).") }
            if y>0 && tileData.allTiles[solution[y-1][x]-1].bottom != tile.top { throw BraidError.invalid("Broken vertical strand continuity at (\(x), \(y)).") }
        }}
    }
}

public struct BraidProject: Codable, Sendable {
    public var sceneSettings: SceneSettings? = nil
    public var cameraState: CameraState? = nil
    public var pictureExportSize: PictureExportSize? = nil
    public var formatVersion = 1
    public var createdAt = Date()
    public var sourceName: String
    public var settings: Settings
    public var sampledImage: PixelImage
    public var tileData: TileData
    public var result: SolveResult
    public init(sourceName: String, settings: Settings, sampledImage: PixelImage, tileData: TileData, result: SolveResult) {
        self.sourceName=sourceName; self.settings=settings; self.sampledImage=sampledImage; self.tileData=tileData; self.result=result
    }
    public func validate() throws {
        guard formatVersion == 1 else { throw BraidError.invalid("Unsupported project format version.") }
        try settings.validate(); try sampledImage.validate(); try sceneSettings?.validate(); try cameraState?.validate()
        guard tileData == TileData(settings: settings), sampledImage.width == result.solution.first?.count,
              sampledImage.height == result.solution.count else { throw BraidError.invalid("Project tile data does not match its settings or sampled image.") }
        try result.validate(tileData: tileData)
    }
    public func save(to url: URL) throws {
        try validate()
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }
    public static func load(from url: URL) throws -> BraidProject {
        let data=try Data(contentsOf: url)
        guard data.count<=100_000_000 else { throw BraidError.invalid("Project is too large.") }
        let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let project=try decoder.decode(BraidProject.self, from: data); try project.validate(); return project
    }
}
