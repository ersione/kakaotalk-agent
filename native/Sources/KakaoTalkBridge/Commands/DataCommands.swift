import ArgumentParser
import Foundation
import KakaoDBCore

private func openLocalDatabase(userId: Int) throws -> DatabaseReader {
    let connection = try DBConnectionResolver.resolve(userId: userId)
    let reader = DatabaseReader(databasePath: connection.databasePath)
    try reader.open(key: connection.key)
    return reader
}

private func chatType(_ code: Int64) -> String {
    switch code {
    case 0: "direct"
    case 1: "group"
    case 4: "open"
    default: "unknown"
    }
}

private func isoDate(_ value: Any) -> String? {
    guard let seconds = value as? Int64, seconds > 0 else { return nil }
    return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(seconds)))
}

private func printJSON(_ value: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
}

private func requiredUserId(_ value: Int?) throws -> Int {
    guard let value, value > 0 else { throw ValidationError("--user-id is required unless --ax is used.") }
    return value
}

struct ChatsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "chats", abstract: "List chat rooms from the local database, or use --ax for the visible UI")
    @Option(name: .long) var userId: Int?
    @Option(name: .shortAndLong) var limit = 50
    @Flag(name: .long) var ax = false
    @Flag(name: .long) var json = false
    @Flag(name: .shortAndLong) var verbose = false
    @Flag(name: .long) var traceAX = false
    @Flag(name: [.short, .long]) var keepWindow = false

    func run() throws {
        if ax {
            var args = ["--limit", String(limit)]
            if json { args.append("--json") }; if verbose { args.append("--verbose") }
            if traceAX { args.append("--trace-ax") }; if keepWindow { args.append("--keep-window") }
            let command = try AXChatsCommand.parse(args)
            try command.run(); return
        }
        let reader = try openLocalDatabase(userId: requiredUserId(userId)); defer { reader.close() }
        let rows = try reader.rawQuery("SELECT r.chatId,r.type,COALESCE(NULLIF(r.chatName,''),u.displayName,u.friendNickName,u.nickName,'(unknown)'),r.activeMembersCount,r.countOfNewMessage,r.lastUpdatedAt,r.lastSeenLogId,r.lastLogId,COALESCE(m.message,'') FROM NTChatRoom r LEFT JOIN NTUser u ON r.directChatMemberUserId=u.userId AND u.linkId=0 LEFT JOIN NTChatMessage m ON r.lastLogId=m.logId ORDER BY r.lastUpdatedAt DESC LIMIT \(max(1, min(limit, 500)))")
        let items = rows.map { row -> [String: Any] in
            let code = row[1] as? Int64 ?? -1
            var item: [String: Any] = ["chat_id": String(row[0] as? Int64 ?? 0), "chat_type": chatType(code), "chat_type_code": code, "chat_name": row[2], "member_count": row[3], "unread_count": row[4], "last_seen_log_id": String(row[6] as? Int64 ?? 0), "last_log_id": String(row[7] as? Int64 ?? 0)]
            if let date = isoDate(row[5]) { item["last_message_at"] = date }
            item["last_message"] = row[8]
            return item
        }
        if json { try printJSON(["count": items.count, "chats": items]); return }
        for item in items { print("[\(item["chat_id"]!)] \(item["chat_name"]!) type=\(item["chat_type"]!) unread=\(item["unread_count"]!)") }
    }
}

struct MessagesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "messages", abstract: "Read recent messages from the local database, or use --ax for an open chat window")
    @Option(name: .long) var userId: Int?
    @Option(name: .long) var chatId: String?
    @Option(name: .long) var chat: String?
    @Option(name: .shortAndLong) var limit = 20
    @Flag(name: .long) var ax = false
    @Flag(name: .long) var json = false
    @Flag(name: .long) var backgroundSafe = false

    func run() throws {
        if ax {
            var args = ["--limit", String(limit)]
            if let chatId { args += ["--chat-id", chatId] } else if let chat { args.append(chat) }
            if json { args.append("--json") }; if backgroundSafe { args.append("--background-safe") }
            let command = try ReadCommand.parse(args); try command.run(); return
        }
        let uid = try requiredUserId(userId)
        guard let id = chatId, Int64(id) != nil else { throw ValidationError("--chat-id is required for database messages.") }
        let reader = try openLocalDatabase(userId: uid); defer { reader.close() }
        let rows = try reader.rawQuery("SELECT m.logId,m.chatId,m.authorId,COALESCE(u.displayName,u.friendNickName,u.nickName,''),m.message,m.type,m.sentAt,m.readAt FROM NTChatMessage m LEFT JOIN NTUser u ON m.authorId=u.userId AND u.linkId=0 WHERE m.chatId=\(id) ORDER BY m.logId DESC LIMIT \(max(1, min(limit, 500)))")
        let items = rows.reversed().map(messageJSON)
        if json { try printJSON(["chat_id": id, "count": items.count, "messages": items]); return }
        for item in items { print("[\(item["timestamp"]!)] \(item["sender"]!): \(item["text"]!)") }
    }
}

private func messageJSON(_ row: [Any]) -> [String: Any] {
    ["log_id": String(row[0] as? Int64 ?? 0), "chat_id": String(row[1] as? Int64 ?? 0), "sender_id": String(row[2] as? Int64 ?? 0), "sender": row[3], "text": row[4], "message_type": row[5], "timestamp": isoDate(row[6]) ?? "", "read_at": isoDate(row[7]) ?? ""]
}

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: "Search local KakaoTalk messages")
    @Argument var query: String
    @Option(name: .long) var userId: Int
    @Option(name: .long) var chatId: String?
    @Option(name: .shortAndLong) var limit = 20
    @Flag(name: .long) var json = false
    func run() throws {
        let reader = try openLocalDatabase(userId: userId); defer { reader.close() }
        let escaped = query.replacingOccurrences(of: "'", with: "''")
        let room = chatId.flatMap(Int64.init).map { " AND m.chatId=\($0)" } ?? ""
        let rows = try reader.rawQuery("SELECT m.logId,m.chatId,m.authorId,COALESCE(u.displayName,u.friendNickName,u.nickName,''),m.message,m.type,m.sentAt,m.readAt FROM NTChatMessage m LEFT JOIN NTUser u ON m.authorId=u.userId AND u.linkId=0 WHERE m.message LIKE '%\(escaped)%'\(room) ORDER BY m.logId DESC LIMIT \(max(1, min(limit, 500)))")
        let items = rows.map(messageJSON)
        if json { try printJSON(["query": query, "count": items.count, "messages": items]); return }
        for item in items { print("[\(item["chat_id"]!)] \(item["sender"]!): \(item["text"]!)") }
    }
}

struct UnreadCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unread", abstract: "List unread rooms and locally available unread messages")
    @Option(name: .long) var userId: Int
    @Flag(name: .long) var json = false
    func run() throws {
        let reader = try openLocalDatabase(userId: userId); defer { reader.close() }
        let rows = try reader.rawQuery("SELECT r.chatId,r.type,COALESCE(NULLIF(r.chatName,''),u.displayName,u.friendNickName,u.nickName,'(unknown)'),r.countOfNewMessage,r.lastSeenLogId,r.lastLogId FROM NTChatRoom r LEFT JOIN NTUser u ON r.directChatMemberUserId=u.userId AND u.linkId=0 WHERE r.countOfNewMessage>0 ORDER BY r.lastUpdatedAt DESC")
        let rooms = try rows.map { row -> [String: Any] in
            let id = row[0] as? Int64 ?? 0, seen = row[4] as? Int64 ?? 0, code = row[1] as? Int64 ?? -1
            let messages = try reader.rawQuery("SELECT m.logId,m.chatId,m.authorId,COALESCE(u.displayName,u.friendNickName,u.nickName,''),m.message,m.type,m.sentAt,m.readAt FROM NTChatMessage m LEFT JOIN NTUser u ON m.authorId=u.userId AND u.linkId=0 WHERE m.chatId=\(id) AND m.logId>\(seen) ORDER BY m.logId ASC").map(messageJSON)
            return ["chat_id": String(id), "chat_type": chatType(code), "chat_type_code": code, "chat_name": row[2], "unread_count": row[3], "last_seen_log_id": String(seen), "last_log_id": String(row[5] as? Int64 ?? 0), "messages": messages]
        }
        if json { try printJSON(["count": rooms.count, "chats": rooms]); return }
        for room in rooms { print("[\(room["chat_id"]!)] \(room["chat_name"]!) unread=\(room["unread_count"]!)") }
    }
}

struct WatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "watch", abstract: "Watch database messages, or use --ax for one visible chat")
    @Option(name: .long) var userId: Int?
    @Option(name: .long) var chat: String?
    @Option(name: .long) var interval = 0.3
    @Option(name: .long) var sinceLogId: Int64?
    @Flag(name: .long) var ax = false
    @Flag(name: .long) var json = false
    func run() throws {
        if ax {
            guard let chat, !chat.isEmpty else { throw ValidationError("--chat is required with --ax.") }
            var args = [chat, "--poll-interval", String(interval)]
            if json { args.append("--json") }
            let command = try AXWatchCommand.parse(args)
            try command.run(); return
        }
        guard interval >= 0.1 else { throw ValidationError("Interval must be at least 0.1 seconds") }
        try DBWatchCommand.runWatch(userId: requiredUserId(userId), interval: interval, sinceLogId: sinceLogId)
    }
}
