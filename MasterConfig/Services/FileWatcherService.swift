import Foundation

typealias WatchToken = Int

@Observable
@MainActor
final class FileWatcherService {
    private var watchers: [WatchToken: DispatchSourceFileSystemObject] = [:]
    private var nextToken: WatchToken = 0

    @discardableResult
    func watch(_ path: String, onChange: @escaping () -> Void) -> WatchToken {
        let expandedPath = (path as NSString).expandingTildeInPath
        let fd = open(expandedPath, O_EVTONLY)
        guard fd >= 0 else { return -1 }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: DispatchQueue.global(qos: .background)
        )

        let token = nextToken
        nextToken += 1

        source.setEventHandler {
            DispatchQueue.main.async {
                onChange()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        watchers[token] = source
        return token
    }

    func unwatch(_ token: WatchToken) {
        watchers[token]?.cancel()
        watchers.removeValue(forKey: token)
    }

    func unwatchAll() {
        for (_, source) in watchers { source.cancel() }
        watchers.removeAll()
    }
}
