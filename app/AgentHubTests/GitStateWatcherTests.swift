import Foundation
import Testing
@testable import AgentHubCore

@Suite("GitStateWatcher")
struct GitStateWatcherTests {

  @Test("emits event when git index changes")
  func emitsOnIndexChange() async throws {
    let fixture = try GitRepoFixture.create()
    defer { try? FileManager.default.removeItem(atPath: fixture.parentDir) }

    let gitRoot = fixture.repoPath
    let watcher = GitStateWatcher()
    await watcher.watch(gitRoot: gitRoot)

    // Start collecting events BEFORE triggering the change
    let eventTask = Task {
      for await _ in watcher.changes { return true }
      return false
    }

    // Trigger a change: stage a new file
    try "hello".write(toFile: gitRoot + "/test.txt", atomically: true, encoding: .utf8)
    try fixture.runGit("add", "test.txt")

    // Wait up to 3 seconds for an event
    let received = await withTaskGroup(of: Bool.self) { group in
      group.addTask { await eventTask.value }
      group.addTask {
        try? await Task.sleep(for: .seconds(3))
        eventTask.cancel()
        return false
      }
      let result = await group.next() ?? false
      group.cancelAll()
      return result
    }

    #expect(received == true)
    await watcher.stop()
  }

  @Test("stops emitting after stop() is called")
  func stopsAfterStop() async throws {
    let fixture = try GitRepoFixture.create()
    defer { try? FileManager.default.removeItem(atPath: fixture.parentDir) }

    let watcher = GitStateWatcher()
    await watcher.watch(gitRoot: fixture.repoPath)
    await watcher.stop()

    // After stop(), the changes stream is finished — consuming it yields nothing
    var eventCount = 0
    for await _ in watcher.changes {
      eventCount += 1
    }
    // The stream ended (finish() was called in stop()), so this completes without hanging
    #expect(eventCount == 0)
  }
}
