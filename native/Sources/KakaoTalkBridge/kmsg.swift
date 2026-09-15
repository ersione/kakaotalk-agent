import ArgumentParser
import Foundation

private func invokedCommandName() -> String {
    let executable = CommandLine.arguments.first ?? "kakaotalk-agent"
    let name = URL(fileURLWithPath: executable).lastPathComponent
    return name.isEmpty ? "kakaotalk-agent" : name
}

@main
struct KakaoTalkBridge: ParsableCommand {
    private static let commandName = invokedCommandName()

    static let configuration = CommandConfiguration(
        commandName: commandName,
        abstract: "Native KakaoTalk event/read/send bridge for macOS",
        discussion: """
            \(commandName) uses macOS Accessibility APIs to interact with KakaoTalk.

            Before using \(commandName), make sure:
            1. KakaoTalk is installed and running
            2. Accessibility permission is granted (System Settings > Privacy & Security > Accessibility)

            Run '\(commandName) status' to check if everything is set up correctly.

            Examples:
              \(commandName) status
              \(commandName) auth login
              \(commandName) chats --user-id 123456789 --json
              \(commandName) messages --user-id 123456789 --chat-id 12345678901234567 --json
              \(commandName) search --user-id 123456789 "keyword" --json
              \(commandName) unread --user-id 123456789 --json
              \(commandName) watch --user-id 123456789
              \(commandName) chats --ax --json
              \(commandName) open "채팅방" --json
              \(commandName) send "채팅방" "메시지"
              \(commandName) send-image "채팅방" "/path/to/image.png"
              \(commandName) watch --ax --chat "채팅방" --json

            Tip:
              \(commandName) -v
            """,
        version: BuildVersion.current,
        subcommands: [
            AuthCommand.self,
            StatusCommand.self,
            InspectCommand.self,
            ChatsCommand.self,
            OpenCommand.self,
            SendCommand.self,
            SendImageCommand.self,
            MessagesCommand.self,
            SearchCommand.self,
            UnreadCommand.self,
            WatchCommand.self,
            DBDiscoverCommand.self,
            DBStatusCommand.self,
            CacheCommand.self,
        ],
        defaultSubcommand: StatusCommand.self
    )

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 1, arguments[0] == "-v" {
            print(BuildVersion.current)
            return
        }
        self.main(arguments)
    }
}
