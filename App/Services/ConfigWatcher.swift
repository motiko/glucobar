import Foundation

/// Calls `onChange` (debounced) when the config file changes on disk.
///
/// Watches both the directory (editors that save by writing a temp file and renaming it
/// over the original, like GlucoBar itself) and the file (editors that write in place).
/// The file watch is re-armed after every event because a rename replaces the inode.
@MainActor
final class ConfigWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        directorySource = makeSource(path: url.deletingLastPathComponent().path, mask: .write)
        armFileSource()
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
    }

    private func armFileSource() {
        fileSource?.cancel()
        fileSource = makeSource(path: url.path, mask: [.write, .extend, .delete, .rename])
    }

    private func makeSource(path: String, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func changed() {
        armFileSource()
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
