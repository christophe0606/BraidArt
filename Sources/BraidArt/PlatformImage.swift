import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
extension CGImage { var platformImage:PlatformImage { NSImage(cgImage:self,size:NSSize(width:width,height:height)) } }
extension Image { init(platformImage:PlatformImage) { self.init(nsImage:platformImage) } }
#else
import UIKit
typealias PlatformImage = UIImage
extension CGImage { var platformImage:PlatformImage { UIImage(cgImage:self) } }
extension Image { init(platformImage:PlatformImage) { self.init(uiImage:platformImage) } }
enum AppIcon { static var image:UIImage { UIImage(named:"AppIconPreview") ?? UIImage(systemName:"circle.hexagongrid.fill")! } }
#endif
