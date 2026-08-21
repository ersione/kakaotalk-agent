import CSQLCipher
import Foundation

/// Watches the KakaoTalk database for new messages by polling.
///
/// Uses `lastLogId` to track the high-water mark — only messages with
/// `logId > lastLogId` are emitted. Polling interval is configurable.
public final class DatabaseWatcher: @unchecked Sendable {
    private let databasePath: String
    private let key: String?
    private let pollInterval: TimeInterval
    private var lastLogId: Int64
    private let useLegacyLogCursor: Bool
    private var running = false
    private let overlapSeconds: Int64 = 300
    private var lastPollAt: Int64 = Int64(Date().timeIntervalSince1970)
    private var seen: [MessageIdentity: Int64] = [:]

    public init(databasePath: String, key: String?, pollInterval: TimeInterval = 2.0, startFromLogId: Int64? = nil) {
        self.databasePath = databasePath
        self.key = key
        self.pollInterval = pollInterval
        self.lastLogId = startFromLogId ?? 0
        self.useLegacyLogCursor = startFromLogId != nil
    }

    /// Start watching. Calls `onMessages` with each batch of new messages.
    /// Calls `onError` if a poll fails. Blocks the calling thread until `stop()` is called.
    public func watch(onMessages: @escaping ([SyncMessage]) -> Void, onError: @escaping (Error) -> Void) {
        running = true

        if useLegacyLogCursor {
            // Explicit --since-log-id preserves historical replay semantics.
        } else {
            do {
                let now = Int64(Date().timeIntervalSince1970)
                lastPollAt = now
                for message in try fetchMessages(since: now - overlapSeconds) {
                    seen[MessageIdentity(message)] = now
                }
            } catch {
                onError(error)
                return
            }
        }

        while running {
            do {
                let messages: [SyncMessage]
                if useLegacyLogCursor {
                    messages = try fetchNewMessages()
                } else {
                    let now = Int64(Date().timeIntervalSince1970)
                    let candidates = try fetchMessages(since: lastPollAt - overlapSeconds)
                    messages = candidates.filter { seen[MessageIdentity($0)] == nil }
                    for message in messages { seen[MessageIdentity(message)] = now }
                    seen = seen.filter { $0.value >= now - overlapSeconds * 2 }
                    lastPollAt = now
                }
                if !messages.isEmpty {
                    if useLegacyLogCursor, let maxId = messages.map(\.logId).max() {
                        lastLogId = maxId
                    }
                    onMessages(messages)
                }
            } catch {
                onError(error)
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    public func stop() {
        running = false
    }

    // MARK: - Private

    private func fetchMaxLogId() throws -> Int64 {
        let reader = DatabaseReader(databasePath: databasePath)
        try reader.open(key: key)
        defer { reader.close() }
        return try reader.maxLogId()
    }

    private func fetchNewMessages() throws -> [SyncMessage] {
        let reader = DatabaseReader(databasePath: databasePath)
        try reader.open(key: key)
        defer { reader.close() }
        let myUserId = try reader.myUserId()
        return try reader.messagesSince(logId: lastLogId, myUserId: myUserId)
    }

    private func fetchMessages(since timestamp: Int64) throws -> [SyncMessage] {
        let reader = DatabaseReader(databasePath: databasePath)
        try reader.open(key: key)
        defer { reader.close() }
        return try reader.messagesSince(sentAt: timestamp, myUserId: reader.myUserId())
    }
}

private struct MessageIdentity: Hashable {
    let chatId: Int64
    let logId: Int64
    init(_ message: SyncMessage) { chatId = message.chatId; logId = message.logId }
}

/// A message event emitted by the watcher, designed for JSON serialization.
public struct SyncMessage: Sendable, Encodable {
    public let type: String
    public let logId: Int64
    public let chatId: Int64
    public let chatName: String?
    public let chatTypeCode: Int
    public let senderId: Int64
    public let senderName: String?
    public let text: String?
    public let messageType: Int
    public let timestamp: String
    public let isFromMe: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case logId = "log_id"
        case chatId = "chat_id"
        case chatName = "chat_name"
        case chatTypeCode = "chat_type_code"
        case senderId = "sender_id"
        case senderName = "sender"
        case text
        case messageType = "message_type"
        case timestamp
        case isFromMe = "is_from_me"
    }
}
