import ArgumentParser
import Darwin
import Foundation
import KakaoDBCore

struct DBWatchCommand: ParsableCommand {
    private struct Event: Encodable {
        let type: String
        let logId: String
        let chatId: String
        let chatName: String?
        let senderId: String
        let sender: String?
        let text: String?
        let messageType: Int
        let timestamp: String
        let isFromMe: Bool

        enum CodingKeys: String, CodingKey {
            case type, text, timestamp, sender
            case logId = "log_id"
            case chatId = "chat_id"
            case chatName = "chat_name"
            case senderId = "sender_id"
            case messageType = "message_type"
            case isFromMe = "is_from_me"
        }

        init(_ message: SyncMessage) {
            type = message.type
            logId = String(message.logId)
            chatId = String(message.chatId)
            chatName = message.chatName
            senderId = String(message.senderId)
            sender = message.senderName
            text = message.text
            messageType = message.messageType
            timestamp = message.timestamp
            isFromMe = message.isFromMe
        }
    }
    static let configuration = CommandConfiguration(
        commandName: "db-watch",
        abstract: "Stream new KakaoTalk messages from the local SQLCipher database"
    )

    @Argument(help: "Numeric KakaoTalk user ID")
    var userId: Int

    @Option(name: .long, help: "Polling interval in seconds")
    var interval: Double = 0.3

    @Option(name: .long, help: "Start after this log ID (default: current maximum)")
    var sinceLogId: Int64?

    @Flag(name: .long, help: "Ignore cached credentials and derive them again")
    var refreshAuth = false

    func validate() throws {
        guard interval >= 0.1 else { throw ValidationError("Interval must be at least 0.1 seconds") }
    }

    func run() throws {
        let connection = try DBConnectionResolver.resolve(userId: userId, refresh: refreshAuth)
        let watcher = DatabaseWatcher(
            databasePath: connection.databasePath,
            key: connection.key,
            pollInterval: interval,
            startFromLogId: sinceLogId
        )
        signal(SIGINT) { _ in Darwin.exit(0) }
        signal(SIGTERM) { _ in Darwin.exit(0) }
        FileHandle.standardError.write(Data("DB watch ready (interval \(interval)s)\n".utf8))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        watcher.watch(onMessages: { messages in
            for message in messages {
                guard let data = try? encoder.encode(Event(message)) else { continue }
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([0x0A]))
            }
        }, onError: { error in
            FileHandle.standardError.write(Data("DB watch error: \(error)\n".utf8))
        })
    }
}
