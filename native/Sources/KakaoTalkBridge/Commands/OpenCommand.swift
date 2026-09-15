import ArgumentParser
import Foundation

struct OpenCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open and keep a chat window without sending a message"
    )

    @Argument(help: "Exact chat room display name")
    var chat: String

    @Flag(name: .long, help: "Output a single JSON result")
    var json = false

    @Flag(name: .long, help: "Show accessibility diagnostics on stderr")
    var traceAX = false

    func validate() throws {
        guard !chat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("Chat name must not be empty.")
        }
    }

    func run() throws {
        do {
            guard AccessibilityPermission.ensureGranted() else {
                throw KakaoTalkError.actionFailed("Accessibility permission required")
            }
            let kakao = try KakaoTalkApp(autoLaunch: false)
            let result = try ChatWindowOpener(kakao: kakao, runner: AXActionRunner(traceEnabled: traceAX))
                .open(chat: chat)
            output(status: result, error: nil)
        } catch {
            output(status: "error", error: String(describing: error))
            throw ExitCode.failure
        }
    }

    private func output(status: String, error: String?) {
        if json {
            var result: [String: String] = ["action": "open", "chat": chat, "status": status]
            if let error { result["error"] = error }
            let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } else if let error {
            FileHandle.standardError.write(Data("Could not open '\(chat)': \(error)\n".utf8))
        } else {
            print("\(status): \(chat)")
        }
    }
}
