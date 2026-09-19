import Combine
import Foundation

struct ReadingResult: Codable, Equatable {
    let source: String
    var words: [AccentWord]
    let originalWords: [AccentWord]
    var past: [[AccentWord]] = []
    var future: [[AccentWord]] = []

    var hasEdits: Bool { words != originalWords }

    mutating func commit(_ updated: [AccentWord]) {
        guard updated != words else { return }
        past.append(words)
        past = Array(past.suffix(50))
        future = []
        words = updated
    }
}

/// The draft and its last completed analysis travel together. Partial responses
/// are transient and never replace a saved result or its correction history.
@MainActor
final class ReadingSession: ObservableObject {
    enum Phase { case idle, loading, streaming, failed }
    typealias Analyzer = (String, @escaping @MainActor ([AccentWord]) -> Void) async throws -> [AccentWord]

    @Published var draft: String {
        didSet {
            if isBusy { cancelAnalysis() }
            persist()
        }
    }
    @Published var showsResult: Bool { didSet { persist() } }
    @Published private(set) var result: ReadingResult? { didSet { persist() } }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var streamedWords: [AccentWord] = []

    private let defaults: UserDefaults
    private let analyze: Analyzer
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private static let storageKey = "readingSession.v1"

    private struct Saved: Codable {
        var draft: String
        var result: ReadingResult?
        var showsResult: Bool
    }

    init(defaults: UserDefaults = .standard, analyzer: @escaping Analyzer = MarkAccentAPI.analyze) {
        self.defaults = defaults
        self.analyze = analyzer
        let saved = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
        draft = saved?.draft ?? defaults.string(forKey: "draftParagraph") ?? ""
        result = saved?.result
        showsResult = saved?.showsResult == true && saved?.result != nil
    }

    #if DEBUG
    static func screenshotSession(scene: String) -> ReadingSession {
        let suite = "dev.sessatakuma.akuma.screenshots"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let session = ReadingSession(defaults: defaults, analyzer: { _, _ in
            throw URLError(.notConnectedToInternet)
        })
        if scene != "input" {
            func word(_ surface: String, _ reading: String, _ accent: Int) -> AccentWord {
                var value = AccentWord(surface: surface, units: [])
                value.apply(reading: reading, accentPosition: accent)
                return value
            }
            let words = [
                word("今日", "きょう", 1), word("は", "は", -1),
                word("いい", "いい", 1), word("天気", "てんき", 1),
                word("です", "です", -1), word("。", "", -1),
                AccentWord(surface: "", units: [], isLineBreak: true),
                word("猫", "ねこ", 1), word("と", "と", -1),
                word("一緒", "いっしょ", 0), word("に", "に", -1),
                word("散歩", "さんぽ", 0), word("します", "します", 2),
                word("。", "", -1)
            ]
            session.draft = "今日はいい天気です。\n猫と一緒に散歩します。"
            session.result = ReadingResult(source: session.draft, words: words, originalWords: words)
            session.showsResult = true
        }
        return session
    }
    #endif

    var isBusy: Bool { phase == .loading || phase == .streaming }
    var needsReplacementConfirmation: Bool {
        result?.hasEdits == true && result?.source != draft
    }

    func openSavedResult() {
        guard result != nil else { return }
        stopRequest()
        phase = .idle
        showsResult = true
    }

    func editDraft() {
        if isBusy { cancelAnalysis() }
        showsResult = false
    }

    func beginAnalysis() {
        guard !isBusy, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if result?.source == draft {
            openSavedResult()
            return
        }
        stopRequest()
        let id = requestID
        let source = draft
        phase = .loading
        showsResult = true
        task = Task {
            do {
                let words = try await analyze(source) { [weak self] words in
                    guard let self, self.requestID == id, !Task.isCancelled else { return }
                    self.streamedWords = words
                    self.phase = .streaming
                }
                guard requestID == id, !Task.isCancelled else { return }
                guard !words.isEmpty else { throw URLError(.cannotParseResponse) }
                result = ReadingResult(source: source, words: words, originalWords: words)
                streamedWords = []
                phase = .idle
                task = nil
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                streamedWords = []
                phase = .failed
                task = nil
            }
        }
    }

    func cancelAnalysis() {
        stopRequest()
        phase = .idle
        showsResult = false
    }

    private func stopRequest() {
        requestID = UUID()
        task?.cancel()
        task = nil
        streamedWords = []
    }

    func updateWord(index: Int, reading: String, accentPosition: Int) {
        guard !isBusy, var updated = result, updated.words.indices.contains(index) else { return }
        var words = updated.words
        words[index].apply(reading: reading, accentPosition: accentPosition)
        updated.commit(words)
        result = updated
    }

    func undo() {
        guard !isBusy, var updated = result, let previous = updated.past.popLast() else { return }
        updated.future.append(updated.words)
        updated.words = previous
        result = updated
    }

    func redo() {
        guard !isBusy, var updated = result, let next = updated.future.popLast() else { return }
        updated.past.append(updated.words)
        updated.words = next
        result = updated
    }

    func restore() {
        guard !isBusy, var updated = result else { return }
        updated.commit(updated.originalWords)
        result = updated
    }

    func persist() {
        let saved = Saved(draft: draft, result: result, showsResult: showsResult)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
