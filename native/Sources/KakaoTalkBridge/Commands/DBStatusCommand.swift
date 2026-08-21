import ArgumentParser
import Foundation
import KakaoDBCore

struct DBStatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "db-status",
        abstract: "Verify and cache the local KakaoTalk database connection"
    )

    @Argument(help: "Numeric KakaoTalk user ID")
    var userId: Int

    @Flag(name: .long, help: "Ignore cached credentials and derive them again")
    var refresh = false

    @Flag(name: .long, help: "Output JSON")
    var json = false

    func run() throws {
        let connection = try DBConnectionResolver.resolve(userId: userId, refresh: refresh)
        let reader = DatabaseReader(databasePath: connection.databasePath)
        try reader.open(key: connection.key)
        defer { reader.close() }
        let maxLogId = try reader.maxLogId()
        if json {
            let filename = URL(fileURLWithPath: connection.databasePath).lastPathComponent
            print("{\"status\":\"ready\",\"user_id\":\(userId),\"database\":\"\(filename)\",\"max_log_id\":\(maxLogId)}")
        } else {
            print("Database: ready")
            print("User ID: \(userId)")
            print("Credentials cached with mode 0600")
        }
    }
}
