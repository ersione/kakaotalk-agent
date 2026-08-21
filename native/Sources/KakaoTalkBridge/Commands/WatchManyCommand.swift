import ArgumentParser
import Foundation

private final class MultiWatchSession {
    let query: String
    var window: UIElement
    var title: String
    var autoOpenedWindow: UIElement?
    var context: MessageTranscriptContext?
    var state = WatchPollingState()

    init(query: String, resolution: ChatWindowResolution) {
        self.query = query
        self.window = resolution.window
        self.title = resolution.window.title ?? query
        self.autoOpenedWindow = resolution.openedTransiently ? resolution.window : nil
    }
}

struct WatchManyCommand: ParsableCommand {
    private struct Event: Encodable {
        let chat: String
        let event: String
        let detectedAt: String
        let message: TranscriptMessage?

        enum CodingKeys: String, CodingKey {
            case chat, event, message
            case detectedAt = "detected_at"
        }
    }

    static let configuration = CommandConfiguration(
        commandName: "watch-many",
        abstract: "Watch multiple open chats through one serialized AX owner"
    )

    @Argument(help: "Names of chats to watch")
    var chats: [String] = []

    @Option(name: .long, help: "Delay between complete scan rounds in seconds")
    var pollInterval: Double = 0.3

    @Flag(name: .long, help: "Output NDJSON events")
    var json = false

    @Flag(name: .long, help: "Show AX traversal and retry details")
    var traceAX = false

    func validate() throws {
        guard !chats.isEmpty else { throw ValidationError("At least one chat is required") }
    }

    func run() throws {
        guard AccessibilityPermission.ensureGranted() else {
            AccessibilityPermission.printInstructions()
            throw ExitCode.failure
        }

        let runner = AXActionRunner(traceEnabled: traceAX)
        let kakao = try AuthBootstrap.requireAuthenticated(traceAX: traceAX)
        let resolver = ChatWindowResolver(kakao: kakao, runner: runner)
        let contextResolver = MessageContextResolver(kakao: kakao, runner: runner)
        let reader = KakaoTalkTranscriptReader(kakao: kakao, runner: runner)
        var helper = WatchCommand()
        helper.pollInterval = pollInterval
        helper.traceAX = traceAX
        helper.keepWindow = true
        helper.json = json
        helper.deepRecovery = false
        helper.includeSystem = false

        var sessions: [MultiWatchSession] = []
        for query in chats {
            helper.chat = query
            let resolution = try resolver.resolve(query: query)
            let session = MultiWatchSession(query: query, resolution: resolution)
            let baseline = try helper.stabilizeBaseline(
                transcriptReader: reader,
                messageContextResolver: contextResolver,
                currentWindow: session.window,
                currentChatTitle: session.title,
                snapshotLimit: 12,
                interval: max(0.2, pollInterval),
                phase: "startup",
                cachedContext: &session.context
            )
            session.title = query
            session.state.replaceBaseline(with: baseline.messages)
            sessions.append(session)
            try emit(chat: session.title, event: "ready", detectedAt: baseline.fetchedAt, message: nil)
        }

        while true {
            for session in sessions {
                helper.chat = session.query
                do {
                    let snapshot = try helper.readNextSnapshot(
                        transcriptReader: reader,
                        messageContextResolver: contextResolver,
                        chatWindowResolver: resolver,
                        currentWindow: &session.window,
                        currentChatTitle: &session.title,
                        autoOpenedWindow: &session.autoOpenedWindow,
                        snapshotLimit: 12,
                        interval: max(0.2, pollInterval),
                        cachedContext: &session.context
                    )
                    session.title = session.query
                    for message in session.state.consume(snapshotMessages: snapshot.messages) {
                        try emit(
                            chat: session.title,
                            event: message.isSystem ? "system" : "message",
                            detectedAt: snapshot.fetchedAt,
                            message: message
                        )
                    }
                } catch {
                    FileHandle.standardError.write(Data("watch-many \(session.query): \(error)\n".utf8))
                }
            }
            Thread.sleep(forTimeInterval: max(0.2, min(pollInterval, 10)))
        }
    }

    private func emit(chat: String, event: String, detectedAt: Date, message: TranscriptMessage?) throws {
        if !json {
            if let message { print("[\(chat)] \(message.author ?? "(me)"): \(message.body)") }
            else { print("[\(chat)] ready") }
            return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        FileHandle.standardOutput.write(try encoder.encode(Event(
            chat: chat, event: event, detectedAt: formatter.string(from: detectedAt), message: message
        )))
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
