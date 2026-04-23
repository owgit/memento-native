import Foundation

enum DirectAutoStartRegistration {
    static let label = "com.memento.capture"
    private static let defaultExecutableName = "memento-capture"

    static func launchAgentURL(homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    static func executableURL(bundle: Bundle = .main) -> URL {
        if let executableURL = bundle.executableURL {
            return executableURL
        }

        let executableName = bundle.executablePath.flatMap(URL.init(fileURLWithPath:))?.lastPathComponent
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)

        return executableURL(bundleURL: bundle.bundleURL, executableName: executableName)
    }

    static func executableURL(bundleURL: URL, executableName: String?) -> URL {
        let resolvedExecutableName = executableName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? defaultExecutableName

        return bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(resolvedExecutableName, isDirectory: false)
    }

    static func plist(executableURL: URL) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            "KeepAlive": false,
        ]
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
