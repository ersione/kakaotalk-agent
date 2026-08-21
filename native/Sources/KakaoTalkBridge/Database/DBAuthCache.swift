import Foundation
import KakaoDBCore

struct DBConnection {
    let databasePath: String
    let key: String
    let userId: Int
}

private struct CachedDBAccount: Codable {
    let userId: Int
    let deviceUUID: String
    let databasePath: String
    let key: String
    let verifiedAt: Date
}

private struct DBAuthCacheDocument: Codable {
    var accounts: [String: CachedDBAccount] = [:]
}

enum DBConnectionResolver {
    private static var cacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/kakaotalk-agent/db-auth.json")
    }

    static func resolve(userId: Int, refresh: Bool = false) throws -> DBConnection {
        let uuid = try DeviceInfo.platformUUID()
        if !refresh,
           let cached = load().accounts[String(userId)],
           cached.deviceUUID == uuid,
           verify(path: cached.databasePath, key: cached.key)
        {
            return DBConnection(databasePath: cached.databasePath, key: cached.key, userId: userId)
        }

        let databaseName = KeyDerivation.databaseName(userId: userId, uuid: uuid)
        let candidates = [
            "\(DeviceInfo.containerPath)/\(databaseName)",
            "\(DeviceInfo.containerPath)/\(databaseName).db",
        ]
        guard let path = candidates.first(where: FileManager.default.fileExists(atPath:)) else {
            throw KakaoTalkError.elementNotFound("No database matched userId \(userId)")
        }
        let key = KeyDerivation.secureKey(userId: userId, uuid: uuid)
        guard verify(path: path, key: key) else {
            throw KakaoTalkError.actionFailed("SQLCipher key verification failed for userId \(userId)")
        }

        var document = load()
        document.accounts[String(userId)] = CachedDBAccount(
            userId: userId,
            deviceUUID: uuid,
            databasePath: path,
            key: key,
            verifiedAt: Date()
        )
        try save(document)
        return DBConnection(databasePath: path, key: key, userId: userId)
    }

    static func cachedUserIds() -> [Int] {
        load().accounts.keys.compactMap(Int.init).sorted()
    }

    private static func verify(path: String, key: String) -> Bool {
        let reader = DatabaseReader(databasePath: path)
        defer { reader.close() }
        return reader.tryOpen(key: key)
    }

    private static func load() -> DBAuthCacheDocument {
        guard let data = try? Data(contentsOf: cacheURL) else {
            return DBAuthCacheDocument()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(DBAuthCacheDocument.self, from: data)) ?? DBAuthCacheDocument()
    }

    private static func save(_ document: DBAuthCacheDocument) throws {
        let directory = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: cacheURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    }
}
