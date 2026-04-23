import AppKit
import Foundation

@MainActor
enum AppRelauncher {
    @discardableResult
    static func relaunch(appPath: String, failureMessage: String) -> Bool {
        let fileManager = FileManager.default
        let scriptURL = fileManager.temporaryDirectory.appendingPathComponent("memento-relaunch-\(UUID().uuidString).sh")
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/bash
        set -euo pipefail

        APP_PATH=\(shellQuote(appPath))
        OLD_PID=\(currentPID)
        SELF_PATH=\(shellQuote(scriptURL.path))

        cleanup() {
            /bin/rm -f "$SELF_PATH"
        }
        trap cleanup EXIT

        for _ in $(/usr/bin/seq 1 100); do
            if ! /bin/kill -0 "$OLD_PID" >/dev/null 2>&1; then
                break
            fi
            /bin/sleep 0.2
        done

        /usr/bin/open -n "$APP_PATH" >/dev/null 2>&1 || {
            /bin/sleep 2
            /usr/bin/open "$APP_PATH" >/dev/null 2>&1
        }
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
            process.arguments = ["/bin/bash", scriptURL.path]
            process.standardOutput = nil
            process.standardError = nil
            try process.run()

            NSApp.terminate(nil)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = L.errorTitle
            alert.informativeText = failureMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: L.ok)
            alert.runModal()
            return false
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
