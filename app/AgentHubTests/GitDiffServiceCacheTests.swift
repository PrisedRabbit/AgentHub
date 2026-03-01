import Foundation
import Testing
@testable import AgentHubCore

@Suite("GitDiffService cache")
struct GitDiffServiceCacheTests {

  @Test("returns nil for empty cache")
  func emptyCache() async throws {
    let service = GitDiffService()
    let result = await service.getCachedState(repoPath: "/tmp/fake", mode: .unstaged)
    #expect(result == nil)
  }

  @Test("returns cached state after getChanges")
  func cachePopulatedAfterLoad() async throws {
    let fixture = try GitRepoFixture.create()
    defer { try? FileManager.default.removeItem(atPath: fixture.parentDir) }

    try "hello".write(toFile: fixture.repoPath + "/file.txt", atomically: true, encoding: .utf8)

    let service = GitDiffService()
    _ = try await service.getChanges(at: fixture.repoPath, mode: .unstaged)

    let gitRoot = try await service.findGitRoot(at: fixture.repoPath)
    let cached = await service.getCachedState(repoPath: gitRoot, mode: .unstaged)
    #expect(cached != nil)
  }

  @Test("invalidate clears cached state")
  func invalidateClearsCache() async throws {
    let fixture = try GitRepoFixture.create()
    defer { try? FileManager.default.removeItem(atPath: fixture.parentDir) }

    try "hello".write(toFile: fixture.repoPath + "/file.txt", atomically: true, encoding: .utf8)

    let service = GitDiffService()
    _ = try await service.getChanges(at: fixture.repoPath, mode: .unstaged)

    let gitRoot = try await service.findGitRoot(at: fixture.repoPath)
    await service.invalidate(repoPath: gitRoot)

    let cached = await service.getCachedState(repoPath: gitRoot, mode: .unstaged)
    #expect(cached == nil)
  }

  @Test("file diff is cached after first fetch")
  func fileDiffCached() async throws {
    let fixture = try GitRepoFixture.create()
    defer { try? FileManager.default.removeItem(atPath: fixture.parentDir) }

    try "hello\nworld".write(toFile: fixture.repoPath + "/file.txt", atomically: true, encoding: .utf8)

    let service = GitDiffService()
    let state = try await service.getChanges(at: fixture.repoPath, mode: .unstaged)
    guard let firstFile = state.files.first else { return }

    _ = try await service.getFileDiff(
      filePath: firstFile.filePath, at: fixture.repoPath, mode: .unstaged
    )

    let (_, new) = try await service.getFileDiff(
      filePath: firstFile.filePath, at: fixture.repoPath, mode: .unstaged
    )
    #expect(new.contains("hello"))
  }
}
