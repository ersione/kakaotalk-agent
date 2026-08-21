import ArgumentParser
import Foundation
import KakaoDBCore

struct DBDiscoverCommand: ParsableCommand {
    private struct Account: Encodable {
        let userId: Int
        let verified: Bool
        let database: String?

        enum CodingKeys: String, CodingKey {
            case verified, database
            case userId = "user_id"
        }
    }

    private struct Result: Encodable {
        let accounts: [Account]
        let databaseCount: Int

        enum CodingKeys: String, CodingKey {
            case accounts
            case databaseCount = "database_count"
        }
    }

    static let configuration = CommandConfiguration(
        commandName: "db-discover",
        abstract: "Discover local KakaoTalk account IDs and verify their encrypted databases"
    )

    @Flag(name: .long, help: "Output JSON")
    var json = false

    func run() throws {
        let cachedIds = DBConnectionResolver.cachedUserIds()
        var ids = Array(Set(DeviceInfo.candidateUserIds() + cachedIds))
        // SHA-512 pre-image recovery is the slow fallback for first setup.
        // Once a verified account cache exists, do not repeat it every run.
        if cachedIds.isEmpty, let active = try? DeviceInfo.userId(), !ids.contains(active) {
            ids.append(active)
        }
        ids.sort()

        let accounts = ids.map { userId -> Account in
            guard let connection = try? DBConnectionResolver.resolve(userId: userId) else {
                return Account(userId: userId, verified: false, database: nil)
            }
            return Account(
                userId: userId,
                verified: true,
                database: URL(fileURLWithPath: connection.databasePath).lastPathComponent
            )
        }
        let result = Result(accounts: accounts, databaseCount: DeviceInfo.countDatabaseFiles())

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(result)
            print(String(decoding: data, as: UTF8.self))
        } else {
            print("Encrypted databases: \(result.databaseCount)")
            if accounts.isEmpty {
                print("No KakaoTalk account IDs were discovered.")
            }
            for account in accounts {
                let state = account.verified ? "verified" : "unverified"
                print("User ID \(account.userId): \(state)")
            }
        }
    }
}
