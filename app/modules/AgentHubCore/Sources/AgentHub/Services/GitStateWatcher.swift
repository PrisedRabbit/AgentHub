import Foundation

/// Watches a git repository's state files for changes using kqueue.
///
/// Monitors `.git/index` (covers staged changes and commits) and `.git/HEAD`
/// (branch switches, resets). Emits `Void` via `changes` stream on any event.
public actor GitStateWatcher {

  private var sources: [DispatchSourceFileSystemObject] = []
  private nonisolated let _continuation: AsyncStream<Void>.Continuation

  /// Emits `Void` whenever `.git/index` or `.git/HEAD` changes.
  public nonisolated let changes: AsyncStream<Void>

  public init() {
    (changes, _continuation) = AsyncStream.makeStream(of: Void.self)
  }

  /// Start watching the git repository at `gitRoot`.
  /// - Parameter gitRoot: Absolute path to the git repository root.
  public func watch(gitRoot: String) {
    let gitDir = gitRoot + "/.git"
    let watchPaths = [gitDir + "/index", gitDir + "/HEAD"]

    for path in watchPaths {
      let fd = open(path, O_EVTONLY)
      guard fd >= 0 else {
        AppLogger.git.warning("GitStateWatcher: could not open \(path) for watching")
        continue
      }

      let continuation = _continuation  // capture by value, not through self
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: [.write, .extend, .rename, .delete],
        queue: DispatchQueue.global(qos: .utility)
      )

      source.setEventHandler { continuation.yield() }
      source.setCancelHandler { close(fd) }
      source.resume()
      sources.append(source)
    }
  }

  /// Cancel all watchers and finish the `changes` stream.
  public func stop() {
    sources.forEach { $0.cancel() }
    sources = []
    _continuation.finish()
  }

  deinit {
    sources.forEach { $0.cancel() }
    _continuation.finish()
  }
}
