import Foundation
import CoreServices

/// Recursive folder watcher built on FSEvents. Reports changed paths (debounced) on the main queue.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let callback: ([String]) -> Void
    private var pending = Set<String>()
    private var timer: DispatchWorkItem?
    private let latency: TimeInterval

    init(url: URL, latency: TimeInterval = 0.12, callback: @escaping ([String]) -> Void) {
        self.callback = callback
        self.latency = latency
        start(path: url.path)
    }

    deinit { stop() }

    private func start(path: String) {
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            watcher.receive(Array(array.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, cb, &context, [path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
        stream = s
    }

    private func receive(_ paths: [String]) {
        for p in paths { pending.insert(p) }
        timer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let batch = Array(self.pending)
            self.pending.removeAll()
            self.callback(batch)
        }
        timer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func stop() {
        timer?.cancel()
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
    }
}
