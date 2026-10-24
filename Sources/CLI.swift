import Foundation
import Darwin

@main
enum ConverterCLI {
    static func main() {
        var sources: [String] = []
        var output: URL?
        var arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            if argument == "--output" {
                guard !arguments.isEmpty else { fputs("--output 需要一个文件夹路径\n", stderr); exit(2) }
                output = URL(fileURLWithPath: arguments.removeFirst(), isDirectory: true)
            } else {
                sources.append(argument)
            }
        }
        guard !sources.isEmpty else {
            print("用法：ncm2mp3 [--output 输出文件夹] 文件.ncm ...")
            exit(2)
        }
        var failed = false
        for source in sources {
            var result: [String: Any] = ["source": source]
            do {
                let engine = try ConversionEngine(tools: ConversionTools.locate())
                let converted = try engine.convert(source: URL(fileURLWithPath: source), outputDirectory: output)
                result["status"] = converted.skipped ? "skipped" : "completed"
                result["output"] = converted.url.path
                result["transcoded"] = converted.transcoded
            } catch {
                result["status"] = "failed"
                result["error"] = error.localizedDescription
                failed = true
            }
            if let json = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
               let line = String(data: json, encoding: .utf8) { print(line) }
        }
        exit(failed ? 1 : 0)
    }
}
