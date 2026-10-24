import Foundation
import Darwin

enum ConversionError: LocalizedError {
    case message(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .cancelled: return "已停止转换"
        }
    }
}

struct ConversionTools {
    let ncmdump: URL
    let ffmpeg: URL
    let ffprobe: URL

    static func locate() throws -> ConversionTools {
        let environment = ProcessInfo.processInfo.environment
        let executableFolder = Bundle.main.executableURL?.deletingLastPathComponent()
        let ncmCandidates = [
            environment["NCM2MP3_NCMDUMP"],
            Bundle.main.resourceURL?.appendingPathComponent("bin/ncmdump").path,
            executableFolder?.appendingPathComponent("../vendor/ncmdump/ncmdump").path,
        ].compactMap { $0 }
        let folders = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            + (environment["PATH"] ?? "").split(separator: ":").map(String.init)

        func find(_ name: String, candidates: [String]) throws -> URL {
            guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                let message = name == "ncmdump"
                    ? "找不到转换组件，请重新构建或重新获取此应用。"
                    : "找不到 \(name)。请先安装 FFmpeg（brew install ffmpeg），然后重新打开应用。"
                throw ConversionError.message(message)
            }
            return URL(fileURLWithPath: path).standardizedFileURL
        }

        return try ConversionTools(
            ncmdump: find("ncmdump", candidates: ncmCandidates),
            ffmpeg: find("ffmpeg", candidates: [environment["NCM2MP3_FFMPEG"]].compactMap { $0 } + folders.map { $0 + "/ffmpeg" }),
            ffprobe: find("ffprobe", candidates: [environment["NCM2MP3_FFPROBE"]].compactMap { $0 } + folders.map { $0 + "/ffprobe" })
        )
    }
}

final class ConversionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?

    func check() throws {
        lock.lock()
        let stopped = cancelled
        lock.unlock()
        if stopped { throw ConversionError.cancelled }
    }

    func attach(_ child: Process) {
        lock.lock()
        process = child
        let stopped = cancelled
        lock.unlock()
        if stopped { Self.stop(child) }
    }

    func detach(_ child: Process) {
        lock.lock()
        if process === child { process = nil }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let child = process
        lock.unlock()
        if let child { Self.stop(child) }
    }

    static func stop(_ child: Process) {
        if child.isRunning { child.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
}

struct ConversionResult {
    let url: URL
    let skipped: Bool
    let transcoded: Bool
}

struct AudioInfo {
    let codec: String
    let channels: Int
}

final class ConversionEngine {
    let tools: ConversionTools
    private let files = FileManager.default

    init(tools: ConversionTools) { self.tools = tools }

    func convert(
        source: URL,
        outputDirectory: URL? = nil,
        cancellation: ConversionCancellation = ConversionCancellation(),
        stage: (String) -> Void = { _ in }
    ) throws -> ConversionResult {
        try cancellation.check()
        guard source.isFileURL, source.pathExtension.lowercased() == "ncm" else {
            throw ConversionError.message("请选择 .ncm 文件。")
        }
        let source = source.standardizedFileURL
        let folder = (outputDirectory ?? source.deletingLastPathComponent()).standardizedFileURL
        let target = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension("mp3")
        if exists(target) {
            return ConversionResult(url: target, skipped: true, transcoded: false)
        }
        try validateContainer(source)
        var isDirectory: ObjCBool = false
        guard files.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ConversionError.message("输出文件夹不存在，请重新选择保存位置。")
        }

        let work = files.temporaryDirectory.appendingPathComponent("ncm2mp3-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }

        // Normalize the extension and keep the original file read-only. Each job has its own output directory.
        let input = work.appendingPathComponent("source.ncm")
        try files.createSymbolicLink(at: input, withDestinationURL: source)
        stage("正在还原音频")
        _ = try run(tools.ncmdump, [input.path, "-o", work.path], in: work, cancellation: cancellation)
        let decoded = ["source.mp3", "source.flac"].map { work.appendingPathComponent($0) }.first { exists($0) }
        guard let decoded else {
            throw ConversionError.message("无法还原此 NCM 文件，文件可能已损坏或使用了不支持的格式。")
        }
        let info = try probe(decoded, work: work, cancellation: cancellation)
        let ready = work.appendingPathComponent("ready.mp3")
        let transcoded = info.codec != "mp3"
        if transcoded {
            stage("正在转为 MP3")
            _ = try run(tools.ffmpeg, [
                "-nostdin", "-hide_banner", "-v", "error", "-xerror", "-i", decoded.path,
                "-map", "0:a:0", "-map", "0:v?", "-map_metadata", "0",
                "-c:a", "libmp3lame", "-b:a", "320k", "-ar", "44100", "-ac", String(min(info.channels, 2)),
                "-c:v", "copy", "-id3v2_version", "3", "-write_id3v1", "1", "-y", ready.path,
            ], in: work, cancellation: cancellation)
        } else {
            stage("正在保留原始 MP3")
            try files.copyItem(at: decoded, to: ready)
        }

        stage("正在检查音频")
        let resultInfo = try probe(ready, work: work, cancellation: cancellation)
        guard resultInfo.codec == "mp3" else {
            throw ConversionError.message("输出的音频格式校验失败，请重试。")
        }
        // A valid header alone does not establish that all audio frames can be played.
        _ = try run(tools.ffmpeg, [
            "-nostdin", "-hide_banner", "-v", "error", "-xerror", "-i", ready.path,
            "-map", "0:a:0", "-f", "null", "-",
        ], in: work, cancellation: cancellation)
        try cancellation.check()
        stage("正在保存")

        // Stage on the destination volume, then publish atomically without replacing an existing file.
        let staged = folder.appendingPathComponent(".ncm2mp3-" + UUID().uuidString + ".mp3")
        defer { try? files.removeItem(at: staged) }
        do {
            try files.copyItem(at: ready, to: staged)
            try cancellation.check()
            let code = staged.path.withCString { from in
                target.path.withCString { to in renamex_np(from, to, UInt32(RENAME_EXCL)) }
            }
            if code != 0 {
                let reason = errno
                if reason == EEXIST {
                    return ConversionResult(url: target, skipped: true, transcoded: false)
                }
                throw ConversionError.message("无法保存 MP3：\(String(cString: strerror(reason)))。请尝试更换保存位置。")
            }
        } catch let error as ConversionError {
            throw error
        } catch {
            throw ConversionError.message("无法写入输出文件夹，请更换保存位置。\n\(error.localizedDescription)")
        }
        return ConversionResult(url: target, skipped: false, transcoded: transcoded)
    }

    private func exists(_ url: URL) -> Bool {
        (try? files.attributesOfItem(atPath: url.path)) != nil
    }

    private func validateContainer(_ source: URL) throws {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: source) }
        catch { throw ConversionError.message("无法读取这个文件，请检查文件是否存在，以及是否有读取权限。") }
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size > 30 else { throw ConversionError.message("NCM 文件不完整或内容为空。") }
        try handle.seek(toOffset: 0)
        guard try handle.read(upToCount: 8) == Data("CTENFDAM".utf8) else {
            throw ConversionError.message("这不是有效的 NCM 文件，修改扩展名无法转换音频。")
        }
        var offset: UInt64 = 10
        func readLength() throws -> UInt64 {
            guard offset + 4 <= size else { throw ConversionError.message("NCM 文件已截断，无法读取。") }
            try handle.seek(toOffset: offset)
            guard let bytes = try handle.read(upToCount: 4), bytes.count == 4 else {
                throw ConversionError.message("NCM 文件已截断，无法读取。")
            }
            offset += 4
            return bytes.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
        }
        let keyLength = try readLength()
        guard keyLength >= 32, keyLength <= 65536, keyLength % 16 == 0, offset + keyLength <= size else {
            throw ConversionError.message("NCM 密钥数据已损坏。")
        }
        offset += keyLength
        let metaLength = try readLength()
        guard (metaLength == 0 || metaLength >= 46), metaLength <= 16 * 1024 * 1024, offset + metaLength <= size else {
            throw ConversionError.message("NCM 歌曲信息已损坏。")
        }
        offset += metaLength + 5
        let coverLength = try readLength()
        let imageLength = try readLength()
        guard imageLength <= coverLength, offset + coverLength < size else {
            throw ConversionError.message("NCM 封面或音频数据不完整。")
        }
    }

    private func probe(_ url: URL, work: URL, cancellation: ConversionCancellation) throws -> AudioInfo {
        let data = try run(tools.ffprobe, [
            "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name,channels",
            "-of", "json", url.path,
        ], in: work, cancellation: cancellation)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]], let audio = streams.first,
              let codec = audio["codec_name"] as? String,
              let channels = audio["channels"] as? Int, channels > 0 else {
            throw ConversionError.message("未能读取有效的音轨，NCM 文件可能已损坏。")
        }
        return AudioInfo(codec: codec, channels: channels)
    }

    @discardableResult
    private func run(_ executable: URL, _ arguments: [String], in work: URL, cancellation: ConversionCancellation) throws -> Data {
        try cancellation.check()
        let log = work.appendingPathComponent(UUID().uuidString + ".log")
        files.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? files.removeItem(at: log) }
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.currentDirectoryURL = work
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = handle
        child.standardError = handle
        do { try child.run() }
        catch { throw ConversionError.message("无法启动 \(executable.lastPathComponent)：\(error.localizedDescription)") }
        cancellation.attach(child)
        let deadline = DispatchWorkItem { ConversionCancellation.stop(child) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1800, execute: deadline)
        child.waitUntilExit()
        deadline.cancel()
        cancellation.detach(child)
        try cancellation.check()
        try handle.synchronize()
        let output = try Data(contentsOf: log)
        guard child.terminationReason == .exit, child.terminationStatus == 0 else {
            let details = String(decoding: output.suffix(1800), as: UTF8.self)
                .replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.message("\(executable.lastPathComponent) 未能完成处理。\(details.isEmpty ? "" : "\n" + details)")
        }
        return output
    }
}
