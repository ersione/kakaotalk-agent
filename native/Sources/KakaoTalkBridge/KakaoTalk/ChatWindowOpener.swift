import AppKit
import ApplicationServices
import Foundation

/// Foreground-only window opening. Never reads or writes the message composer.
/// Uses the shallow chat list rather than the resolver's expensive full-text search scan.
struct ChatWindowOpener {
    let kakao: KakaoTalkApp
    let runner: AXActionRunner

    func open(chat: String) throws -> String {
        let deadline = Date().addingTimeInterval(15)
        guard let app = NSRunningApplication(processIdentifier: kakao.processIdentifier) else {
            throw KakaoTalkError.actionFailed("KakaoTalk is not running")
        }
        app.unhide()
        app.activate(options: [.activateAllWindows])
        guard runner.waitUntil(label: "KakaoTalk foreground", timeout: 2, condition: {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == kakao.processIdentifier
        }) else {
            throw KakaoTalkError.actionFailed("Could not activate KakaoTalk")
        }

        if let window = try existing(chat: chat) {
            try expose(window)
            return "already_open"
        }
        // Identify the main navigation window, not a detached conversation whose title
        // happens to contain '채팅'. Do not fall back to a message composer.
        let windows = kakao.windows
        guard let root = windows.first(where: { window in
            window.children.contains { $0.identifier == "chatrooms" }
        }) ?? windows.first(where: { ["카카오톡", "KakaoTalk"].contains($0.title ?? "") }) else {
            throw KakaoTalkError.windowNotFound("Open the KakaoTalk main window first")
        }
        try expose(root)
        if let tab = root.children.first(where: { $0.identifier == "chatrooms" }) {
            try tab.press()
            Thread.sleep(forTimeInterval: 0.15)
        }

        if let label = try matchingLabel(chat: chat, root: root, deadline: deadline) {
            try click(label, in: root)
        } else {
            runner.log("open: room absent from list; searching exact name")
            let controls = try shallowControls(root, deadline: deadline)
            var field = controls.first { $0.role == kAXTextFieldRole }
            if field == nil {
                guard let button = controls.first(where: {
                    $0.role == kAXButtonRole && ["검색", "Search"].contains($0.axDescription ?? $0.title ?? "")
                }) else { throw KakaoTalkError.elementNotFound("Chat search button not found") }
                try button.press()
                Thread.sleep(forTimeInterval: 0.15)
                field = try shallowControls(root, deadline: deadline).first { $0.role == kAXTextFieldRole }
            }
            guard let field else { throw KakaoTalkError.elementNotFound("Chat search field not found") }
            // AXValue only: no keyboard fallback that could type into a conversation.
            try field.setAttribute(kAXValueAttribute, value: chat as CFString)
            guard field.stringValue == chat else {
                throw KakaoTalkError.actionFailed("Search text was not reflected")
            }
            var label: UIElement?
            let searchDeadline = min(deadline, Date().addingTimeInterval(3))
            repeat {
                Thread.sleep(forTimeInterval: 0.15)
                label = try matchingLabel(chat: chat, root: root, deadline: deadline)
            } while label == nil && Date() < searchDeadline
            guard let label else { throw KakaoTalkError.elementNotFound("No exact chat name matched '\(chat)'") }
            try click(label, in: root)
        }

        repeat {
            if let window = try existing(chat: chat) {
                try expose(window)
                return "opened"
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw KakaoTalkError.windowNotFound("Chat window did not open within 15 seconds")
    }

    private func existing(chat: String) throws -> UIElement? {
        let matches = kakao.windows.filter { $0.title == chat }
        guard matches.count < 2 else { throw KakaoTalkError.actionFailed("Ambiguous chat name: \(chat)") }
        return matches.first
    }

    private func expose(_ window: UIElement) throws {
        try requireForeground()
        if window.attributeOptional(kAXMinimizedAttribute) as Bool? == true {
            try window.setAttribute(kAXMinimizedAttribute, value: kCFBooleanFalse)
        }
        try window.performAction(kAXRaiseAction)
    }

    /// Search only window controls, stopping at tables and transcript scroll areas.
    private func shallowControls(_ root: UIElement, deadline: Date) throws -> [UIElement] {
        var result: [UIElement] = []
        var queue = root.children.map { ($0, 0) }
        var index = 0
        while index < queue.count {
            try check(deadline)
            guard index < 200 else { throw KakaoTalkError.actionFailed("Chat control scan limit exceeded") }
            let (element, depth) = queue[index]; index += 1
            result.append(element)
            let role = element.role
            if depth < 2 && role != kAXTableRole && role != kAXTextAreaRole {
                queue += element.children.map { ($0, depth + 1) }
            }
        }
        return result
    }

    private func matchingLabel(chat: String, root: UIElement, deadline: Date) throws -> UIElement? {
        let tables = try shallowControls(root, deadline: deadline).filter { $0.role == kAXTableRole }
        var matches: [UIElement] = []
        for table in tables {
            guard let viewport = table.parent?.frame ?? root.frame else { continue }
            let rows = table.children
            guard rows.count <= 500 else { throw KakaoTalkError.actionFailed("Chat list scan limit exceeded") }
            for row in rows {
                try check(deadline)
                guard row.role == kAXRowRole else { continue }
                // Offscreen historical rows can be numerous and AX calls on them slow.
                // Search will bring an offscreen target into view if needed.
                guard let rowFrame = row.frame, rowFrame.width > 0, rowFrame.height > 0,
                      viewport.intersects(rowFrame) else { continue }
                // The first direct static label in a chat cell is its title. Never
                // match a preview, timestamp or member count elsewhere in the row.
                for cell in row.children where cell.role == kAXCellRole {
                    if let title = cell.children.first(where: { $0.role == kAXStaticTextRole }),
                       title.stringValue == chat {
                        matches.append(title)
                    }
                }
            }
        }
        guard matches.count < 2 else { throw KakaoTalkError.actionFailed("Ambiguous chat name: \(chat)") }
        return matches.first
    }

    private func click(_ label: UIElement, in root: UIElement) throws {
        try expose(root)
        guard let frame = label.frame, let rootFrame = root.frame,
              frame.width > 0, frame.height > 0,
              frame.minX.isFinite, frame.minY.isFinite,
              rootFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) else {
            throw KakaoTalkError.actionFailed("Chat name is not visible; scroll it into view first")
        }
        try requireForeground()
        runner.mouseDoubleClick(at: CGPoint(x: frame.midX, y: frame.midY), label: "open chat")
    }

    private func requireForeground() throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == kakao.processIdentifier else {
            throw KakaoTalkError.actionFailed("KakaoTalk lost foreground focus")
        }
    }

    private func check(_ deadline: Date) throws {
        guard Date() < deadline else { throw KakaoTalkError.actionFailed("Chat lookup timed out after 15 seconds") }
    }
}
