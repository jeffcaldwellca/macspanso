// macspanso/Store/FileWatcher.swift
import Foundation

/// Watches a directory (and individual files) for changes using DispatchSource.
/// Fires `onChange(url)` on the main queue when a watched path is modified.
final class FileWatcher {
    var onChange: ((URL) -> Void)?

    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "com.macspanso.filewatcher", qos: .utility)

    func watch(url: URL) {
        let path = url.path
        guard sources[path] == nil else { return }

        let fd = open(path, O_EVTONLY)
        guard fd != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async { self?.onChange?(url) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        sources[path] = source
    }

    func stopWatching(url: URL) {
        let path = url.path
        sources[path]?.cancel()
        sources.removeValue(forKey: path)
    }

    func stopAll() {
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
    }

    deinit { stopAll() }
}
