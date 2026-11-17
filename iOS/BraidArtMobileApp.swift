import SwiftUI
import BraidCore

@main
struct BraidArtMobileApp:App {
    @StateObject private var model=makeMobileModel()
    var body:some Scene {
        WindowGroup {
            MobileContentView(model:model)
                .onOpenURL { model.importMobileFile($0) }
                #if DEBUG
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--background-weave-fixture") {
                        do {
                            let pixels:[RGB]=(0..<800).map { index in
                                let r=Double((index*37)%101)/100,g=Double((index*71)%101)/100,b=Double((index*19)%101)/100
                                return RGB(r,g,b)
                            }
                            let image=try ImageProcessor.cgImage(PixelImage(width:40,height:20,pixels:pixels))
                            let url=FileManager.default.temporaryDirectory.appendingPathComponent("background-test.png")
                            try ImageProcessor.writePNG(image,to:url);model.open(url:url)
                        } catch { model.error=error.localizedDescription }
                    } else if ProcessInfo.processInfo.arguments.contains("--ui-fixture") {
                        do {
                            let pixels=(0..<16384).map { RGB(Double($0%128)/127,Double($0/128)/127,0.3) }
                            let image=try ImageProcessor.cgImage(PixelImage(width:128,height:128,pixels:pixels))
                            let url=FileManager.default.temporaryDirectory.appendingPathComponent("test-picture.png")
                            try ImageProcessor.writePNG(image,to:url);model.open(url:url)
                        } catch { model.error=error.localizedDescription }
                    }
                }
                #endif
        }
    }
}

@MainActor private func makeMobileModel()->AppModel {
    let model=AppModel()
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--background-weave-fixture") {
        model.settings.columns=40;model.settings.partitionSize=20;model.settings.threads=2
        model.settings.secondsPerPartition=40;model.settings.relativeGap=0;model.settings.grayscale=false
        model.settings.palette=[.black,.white,RGB(0.8,0.1,0.2),RGB(0.1,0.4,0.9)]
        model.settings.outputSize = .custom(try! CustomPictureSize(name:"Background test",width:256,height:128))
    } else if ProcessInfo.processInfo.arguments.contains("--ui-fixture") {
        model.settings.columns=8;model.settings.partitionSize=2;model.settings.threads=1
        model.settings.outputSize = .custom(try! CustomPictureSize(name:"Test",width:128,height:128))
    }
    #endif
    return model
}
