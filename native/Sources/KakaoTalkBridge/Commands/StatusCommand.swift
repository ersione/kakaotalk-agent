import ArgumentParser
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check KakaoTalk and accessibility status"
    )

    @Flag(name: .long, help: "Show detailed information")
    var verbose: Bool = false

    func run() throws {
        print("kakaotalk-agent - KakaoTalk local agent/CLI\n")

        // Check accessibility permission
        let hasPermission = AccessibilityPermission.ensureGranted()
        print("Accessibility Permission: \(hasPermission ? "✓ Granted" : "✗ Not Granted")")

        if !hasPermission {
            print("")
            AccessibilityPermission.printInstructions()
            return
        }

        // Check KakaoTalk status - launch if not running
        var isRunning = KakaoTalkApp.isRunning
        if !isRunning {
            print("KakaoTalk: Not running, launching...")
            if KakaoTalkApp.launch() != nil {
                isRunning = true
                print("KakaoTalk: ✓ Launched")
            } else {
                print("KakaoTalk: ✗ Failed to launch")
                return
            }
        } else {
            print("KakaoTalk: ✓ Running")
        }

        do {
            _ = try AuthBootstrap.requireAuthenticated(traceAX: false)
            print("Authentication: ✓ Ready")
        } catch {
            print("Authentication: ✗ \(error.localizedDescription)")
            throw ExitCode.failure
        }

        // Get detailed info if verbose
        if verbose {
            print("")
            do {
                let kakao = try AuthBootstrap.requireAuthenticated(traceAX: false)
                let windows = kakao.windows

                print("Windows (\(windows.count)):")
                for (index, window) in windows.enumerated() {
                    let title = window.title ?? "(untitled)"
                    let frame = window.frame.map { "(\(Int($0.origin.x)), \(Int($0.origin.y))) \(Int($0.size.width))x\(Int($0.size.height))" } ?? "unknown"
                    print("  [\(index)] \(title) - \(frame)")
                }
            } catch {
                print("Error accessing KakaoTalk: \(error)")
            }
        }

        print("\n✓ Ready to use kakaotalk-agent commands\n")
        printUsage()
    }

    private func printUsage() {
        print("""
        USAGE: kakaotalk-agent <command> [options]

        COMMANDS:
          status    Check KakaoTalk and accessibility status
          auth      Log in and manage stored credentials
          chats     List chat rooms from DB (or --ax)
          messages  Read messages from DB (or --ax)
          search    Search messages in the local DB
          unread    List unread rooms and messages
          watch     Stream new DB messages (or --ax)
          send      Send a message to a chat room
          send-image Send an image to a chat
          cache     Manage AX path cache
          inspect   Inspect KakaoTalk UI hierarchy (debug)

        OPTIONS:
          --help    Show help for any command
          -v, --version Show version

        EXAMPLES:
          kakaotalk-agent -v
          kakaotalk-agent chats --user-id 123456789 --json
          kakaotalk-agent messages --user-id 123456789 --chat-id "<id>" --json
          kakaotalk-agent search --user-id 123456789 "검색어" --json
          kakaotalk-agent unread --user-id 123456789 --json
          kakaotalk-agent watch --user-id 123456789
          kakaotalk-agent send "채팅방" "안녕!" --background-safe --json
        """)
    }
}
