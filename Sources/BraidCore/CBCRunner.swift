import Foundation
import Darwin

public enum CBCRunner {
    public static func discover() -> URL? {
        let fm=FileManager.default
        var candidates=[URL]()
        if let env=ProcessInfo.processInfo.environment["BRAIDART_CBC"] { candidates.append(URL(fileURLWithPath:env)) }
        if let resources=Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent("Solver/bin/cbc")) }
        candidates += [URL(fileURLWithPath:fm.currentDirectoryPath).appendingPathComponent(".build/solver-native/bin/cbc"),
                       URL(fileURLWithPath:"/opt/homebrew/bin/cbc"),URL(fileURLWithPath:"/usr/local/bin/cbc")]
        return candidates.first{fm.isExecutableFile(atPath:$0.path)}
    }
    public static func solve(problem: BlockProblem, executable: URL, settings: Settings) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath:executable.path) else { throw BraidError.invalid("Select a CBC executable or build the bundled solver with Scripts/build-solver.sh.") }
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent("BraidArt-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temp) }
        let input=temp.appendingPathComponent("partition.lp"),seed=temp.appendingPathComponent("seed.sol"),output=temp.appendingPathComponent("result.sol"),log=temp.appendingPathComponent("solver.log")
        try problem.lp.write(to:input,atomically:true,encoding:.utf8);try problem.warmStart.write(to:seed,atomically:true,encoding:.utf8)
        FileManager.default.createFile(atPath:log.path,contents:nil)
        let handle=try FileHandle(forWritingTo:log);defer{try? handle.close()}
        let process=Process();process.executableURL=executable;process.currentDirectoryURL=temp
        process.arguments=[input.path,"-randomSeed","1","-randomCbcSeed","1","-threads",String(settings.threads),
                           "-seconds",String(settings.secondsPerPartition),"-timeMode","elapsed","-ratioGap",String(settings.relativeGap),
                           "-mipstart",seed.path,"-solve","-printingOptions","normal","-solution",output.path,"-quit"]
        process.standardOutput=handle;process.standardError=handle
        try process.run()
        do {
            let deadline=Date().addingTimeInterval(settings.secondsPerPartition+20)
            while process.isRunning {
                try Task.checkCancellation()
                if Date()>deadline { throw BraidError.invalid("CBC exceeded its time limit. Reduce the partition size.") }
                try await Task.sleep(nanoseconds:50_000_000)
            }
        } catch {
            if process.isRunning { process.terminate() }
            // Escalate only this child process if it does not respond to SIGTERM.
            await Task.detached { try? await Task.sleep(nanoseconds:250_000_000) }.value
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            throw error
        }
        guard process.terminationStatus==0,FileManager.default.fileExists(atPath:output.path) else {
            let detail=(try? String(contentsOf:log,encoding:.utf8)) ?? "No diagnostic output."
            throw BraidError.invalid("CBC could not solve this partition.\n\(detail.suffix(2500))")
        }
        return try String(contentsOf:output,encoding:.utf8)
    }
}
