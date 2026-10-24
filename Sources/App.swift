import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum JobState {
    case waiting, working, completed, skipped, failed, cancelled
}

struct ConversionJob: Identifiable {
    let id = UUID()
    let source: URL
    var state = JobState.waiting
    var detail = "等待转换"
    var output: URL?
}

@MainActor
final class ConversionStore: ObservableObject {
    @Published var jobs: [ConversionJob] = []
    @Published var isConverting = false
    @Published var notice: String?
    @Published var outputFolder: URL?
    private var cancellation: ConversionCancellation?

    init() {
        if let path = UserDefaults.standard.string(forKey: "outputFolder") {
            outputFolder = URL(fileURLWithPath: path, isDirectory: true)
        }
        do { _ = try ConversionTools.locate() }
        catch { notice = error.localizedDescription }
    }

    var completed: Int { jobs.filter { $0.state == .completed }.count }
    var skipped: Int { jobs.filter { $0.state == .skipped }.count }
    var failed: Int { jobs.filter { $0.state == .failed }.count }
    var waiting: Int { jobs.filter { $0.state == .waiting }.count }
    var canRetry: Bool { jobs.contains { $0.state == .failed || $0.state == .cancelled } }

    func add(_ urls: [URL]) {
        var invalid = 0
        for url in urls {
            guard url.isFileURL, url.pathExtension.lowercased() == "ncm",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                invalid += 1
                continue
            }
            let source = url.standardizedFileURL
            if let index = jobs.firstIndex(where: { $0.source == source }) {
                if jobs[index].state == .working || jobs[index].state == .waiting { continue }
                jobs[index] = ConversionJob(source: source)
            } else {
                jobs.append(ConversionJob(source: source))
            }
        }
        notice = invalid > 0 ? "已忽略 \(invalid) 个非 NCM 文件；请直接拖入 .ncm 文件。" : nil
        startNext()
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择 NCM 文件"
        panel.prompt = "添加并转换"
        panel.allowedContentTypes = [UTType(filenameExtension: "ncm") ?? .data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择 MP3 保存位置"
        panel.prompt = "保存到这里"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if let outputFolder { panel.directoryURL = outputFolder }
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url
            UserDefaults.standard.set(url.path, forKey: "outputFolder")
        }
    }

    func useSourceFolder() {
        outputFolder = nil
        UserDefaults.standard.removeObject(forKey: "outputFolder")
    }

    func stop() {
        for index in jobs.indices where jobs[index].state == .waiting {
            jobs[index].state = .cancelled
            jobs[index].detail = "已停止"
        }
        cancellation?.cancel()
    }

    func retry(_ id: UUID? = nil) {
        for index in jobs.indices where (id == nil || jobs[index].id == id)
            && (jobs[index].state == .failed || jobs[index].state == .cancelled) {
            jobs[index].state = .waiting
            jobs[index].detail = "等待转换"
        }
        notice = nil
        startNext()
    }

    func clearFinished() {
        jobs.removeAll { $0.state != .working && $0.state != .waiting }
    }

    private func startNext() {
        guard !isConverting, let index = jobs.firstIndex(where: { $0.state == .waiting }) else { return }
        let tools: ConversionTools
        do { tools = try ConversionTools.locate() }
        catch {
            notice = error.localizedDescription
            for index in jobs.indices where jobs[index].state == .waiting {
                jobs[index].state = .failed
                jobs[index].detail = error.localizedDescription
            }
            return
        }
        let id = jobs[index].id
        let source = jobs[index].source
        let folder = outputFolder
        let token = ConversionCancellation()
        cancellation = token
        isConverting = true
        jobs[index].state = .working
        jobs[index].detail = "正在准备"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try ConversionEngine(tools: tools).convert(source: source, outputDirectory: folder, cancellation: token) { message in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let row = self.jobs.firstIndex(where: { $0.id == id }) else { return }
                        self.jobs[row].detail = message
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                self?.finish(id, result: result)
            }
        }
    }

    private func finish(_ id: UUID, result: Result<ConversionResult, Error>) {
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            switch result {
            case .success(let value):
                jobs[index].state = value.skipped ? .skipped : .completed
                jobs[index].output = value.url
                jobs[index].detail = value.skipped ? "已存在，已跳过" : "已完成"
            case .failure(let error):
                if case ConversionError.cancelled = error {
                    jobs[index].state = .cancelled
                    jobs[index].detail = "已停止"
                } else {
                    jobs[index].state = .failed
                    jobs[index].detail = error.localizedDescription
                }
            }
        }
        cancellation = nil
        isConverting = false
        startNext()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: ConversionStore?
    private var pending: [URL] = []

    func attach(_ store: ConversionStore) {
        self.store = store
        if let window = NSApplication.shared.windows.first(where: { $0.title == "NCM 转 MP3" }) {
            window.styleMask.remove(.resizable)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.remove(.fullScreenAuxiliary)
            window.collectionBehavior.insert(.fullScreenNone)
        }
        if !pending.isEmpty { store.add(pending); pending.removeAll() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let store { store.add(urls) } else { pending.append(contentsOf: urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.isConverting == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "还有文件正在转换"
        alert.informativeText = "退出将停止剩余转换，原始 NCM 文件会保留。"
        alert.addButton(withTitle: "继续转换")
        alert.addButton(withTitle: "停止并退出")
        if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        store?.stop()
        return .terminateNow
    }
}

private let accent = Color(red: 0.48, green: 0.35, blue: 0.88)
private let ink = Color(red: 0.10, green: 0.10, blue: 0.12)
private let canvas = Color(red: 0.965, green: 0.965, blue: 0.976)

struct PressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 19).padding(.vertical, 10)
            .background(ink, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct FileStack: View {
    let expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func card(_ symbol: String, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.white)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.09)))
            .overlay(Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(color))
            .frame(width: 53, height: 67)
            .shadow(color: .black.opacity(0.05), radius: 9, y: 4)
    }

    var body: some View {
        ZStack {
            card("waveform", color: .secondary)
                .rotationEffect(.degrees(expanded ? -19 : -10))
                .offset(x: expanded ? -37 : -22, y: expanded ? 0 : 5)
            card("music.note", color: .secondary)
                .rotationEffect(.degrees(expanded ? 19 : 10))
                .offset(x: expanded ? 37 : 22, y: expanded ? 0 : 5)
            card(expanded ? "arrow.down" : "music.note", color: accent)
                .offset(y: expanded ? -8 : -3)
        }
        .frame(width: 150, height: 84)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.68), value: expanded)
        .accessibilityHidden(true)
    }
}

struct ContentView: View {
    @ObservedObject var store: ConversionStore
    @State private var dropTargeted = false
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(red: 0.75, green: 0.65, blue: 1))
                    .frame(width: 36, height: 36)
                    .background(ink, in: RoundedRectangle(cornerRadius: 10))
                Text("NCM → MP3").font(.system(size: 23, weight: .semibold)).foregroundStyle(ink)
                Spacer()
            }

            VStack(spacing: 15) {
                FileStack(expanded: hovered || dropTargeted)
                Text(dropTargeted ? "松开转换" : "拖入 NCM 文件")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(ink)
                Button(action: store.chooseFiles) {
                    Label("选择文件", systemImage: "plus").font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(PressButtonStyle())
            }
            .frame(maxWidth: .infinity).padding(.vertical, 21)
            .background(dropTargeted ? accent.opacity(0.06) : .white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(dropTargeted || hovered ? accent.opacity(0.55) : Color.black.opacity(0.10), lineWidth: dropTargeted ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: dropTargeted)

            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(store.outputFolder?.path ?? "原文件夹")
                    .font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    .help(store.outputFolder?.path ?? "保存到原 NCM 文件所在的文件夹")
                Spacer(minLength: 8)
                Menu {
                    Button("选择文件夹…", action: store.chooseFolder)
                    Button("原文件夹", action: store.useSourceFolder)
                } label: { Text("更改") }
                .fixedSize().disabled(store.isConverting)
            }
            .padding(.horizontal, 13).frame(height: 43)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))

            if let notice = store.notice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(notice).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { store.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("关闭提示")
                }
                .font(.system(size: 12)).foregroundStyle(Color.brown).padding(11)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(store.jobs.isEmpty ? "文件" : "文件 · \(store.jobs.count)")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if store.completed > 0 {
                        Text("已完成 \(store.completed)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if store.isConverting {
                        Button("停止", action: store.stop).font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
                    } else if store.canRetry {
                        Button("重试") { store.retry() }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(accent)
                    }
                    if store.jobs.contains(where: { $0.state != .waiting && $0.state != .working }) {
                        Button("清空", action: store.clearFinished).font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                if store.jobs.isEmpty {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 26, weight: .light)).foregroundStyle(ink.opacity(0.16))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .accessibilityLabel("暂无文件")
                } else {
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(store.jobs) { job in JobRow(job: job) { store.retry(job.id) }.id(job.id) }
                            }
                        }
                        .onChange(of: store.jobs.last?.id) { id in
                            if let id { reader.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .background(canvas)
        .frame(width: 560, height: 600)
        .preferredColorScheme(.light)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            guard !providers.isEmpty else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    let url: URL? = await withCheckedContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                            continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
                        }
                    }
                    if let url { urls.append(url) }
                }
                if urls.isEmpty { store.notice = "未能读取拖入的文件，请使用“选择 NCM 文件”添加。" }
                else { store.add(urls) }
            }
            return true
        }
    }
}

struct JobRow: View {
    let job: ConversionJob
    let retry: () -> Void

    private var color: Color {
        switch job.state {
        case .completed: return accent
        case .failed: return .red.opacity(0.8)
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.07)).frame(width: 38, height: 42)
                if job.state == .working { ProgressView().controlSize(.small).tint(accent) }
                else {
                    Image(systemName: job.state == .completed ? "checkmark" : (job.state == .failed ? "exclamationmark" : "music.note"))
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(color)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(job.source.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ink).lineLimit(1).truncationMode(.middle)
                    .help(job.source.path)
                Text(job.detail).font(.system(size: 12)).foregroundStyle(color).lineLimit(2).help(job.detail)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 4)
            if let output = job.output {
                Button { NSWorkspace.shared.activateFileViewerSelecting([output]) } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("在 Finder 中显示 MP3").accessibilityLabel("在 Finder 中显示 MP3")
            } else if job.state == .failed || job.state == .cancelled {
                Button(action: retry) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("重试此文件").accessibilityLabel("重试此文件")
            }
        }
        .padding(.vertical, 9).padding(.horizontal, 3)
    }
}

@main
struct NCMConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = ConversionStore()

    var body: some Scene {
        Window("NCM 转 MP3", id: "converter") {
            ContentView(store: store).onAppear { delegate.attach(store) }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加 NCM 文件…", action: store.chooseFiles).keyboardShortcut("o")
            }
        }
    }
}
