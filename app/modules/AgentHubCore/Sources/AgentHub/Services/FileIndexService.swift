//
//  FileIndexService.swift
//  AgentHub
//
//  Actor-based file index service with gitignore support and fuzzy search.
//

import Foundation

// MARK: - FileIndexService

/// Scans project directories, respects .gitignore, caches the index, and provides fuzzy search.
public actor FileIndexService {

  // MARK: - Shared Instance

  public static let shared = FileIndexService()

  // MARK: - Constants

  private static let cacheTTL: TimeInterval = 5 * 60  // 5 minutes
  private static let maxDepth = 20
  private static let maxSearchResults = 50

  /// Directories and files that are always excluded from the index.
  private static let hardExcludedNames: Set<String> = [
    ".git", "node_modules", ".build", "DerivedData", ".DS_Store",
    "__pycache__", ".pytest_cache", ".mypy_cache", "venv", ".venv",
    ".tox", "dist", "build", ".next", ".nuxt", "coverage"
  ]

  /// Hidden files/dirs (starting with `.`) that are still useful to index.
  /// Keep this list intentionally narrow to avoid surfacing secret-bearing dotfiles.
  private static let allowedHiddenNames: Set<String> = [
    ".gitignore", ".gitmodules", ".gitattributes",
    ".eslintrc", ".eslintrc.js", ".eslintrc.json", ".eslintrc.yml",
    ".prettierrc", ".prettierrc.js", ".prettierrc.json", ".prettierrc.yml",
    ".swiftlint.yml", ".swiftformat",
    ".editorconfig", ".nvmrc", ".node-version", ".ruby-version", ".python-version",
    ".babelrc", ".babelrc.json",
    ".dockerignore", ".docker",
    ".github", ".vscode", ".cursor"
  ]

  private struct IgnoreRule {
    let basePath: String
    let pattern: String
    let isNegated: Bool
    let directoryOnly: Bool
    let matchesRelativePath: Bool
  }

  // MARK: - Cache

  private struct CacheEntry {
    let nodes: [FileTreeNode]
    let date: Date
  }

  private var cache: [String: CacheEntry] = [:]
  private var recentPaths: [String] = []
  private static let maxRecentFiles = 20

  // MARK: - Initialization

  public init() {}

  // MARK: - Public API

  /// Records a file as recently opened (most recent first, deduped).
  public func addToRecent(_ path: String) {
    recentPaths.removeAll { $0 == path }
    recentPaths.insert(path, at: 0)
    if recentPaths.count > Self.maxRecentFiles {
      recentPaths = Array(recentPaths.prefix(Self.maxRecentFiles))
    }
  }

  /// Returns recently opened files that belong to `projectPath`, as `FileSearchResult` objects.
  public func recentFiles(in projectPath: String) -> [FileSearchResult] {
    recentPaths
      .compactMap { path in
        guard let relativePath = Self.relativePathIfContained(path, within: projectPath) else {
          return nil
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return FileSearchResult(
          id: path,
          name: name,
          relativePath: relativePath,
          absolutePath: path,
          score: 0
        )
      }
  }

  /// Returns the cached file tree for `projectPath`, or scans it fresh if the cache is stale.
  public func index(projectPath: String) async -> [FileTreeNode] {
    if let entry = cache[projectPath], !isCacheStale(entry.date) {
      return entry.nodes
    }
    let nodes = await scanDirectory(at: projectPath)
    cache[projectPath] = CacheEntry(nodes: nodes, date: Date())
    return nodes
  }

  /// Searches files using a strict 3-tier approach:
  /// 1. Filename starts with query → highest score
  /// 2. Filename contains query as substring → high score
  /// 3. Path contains query as substring → medium score
  /// All matching is case-insensitive substring, no fuzzy.
  public func search(query: String, in projectPath: String) async -> [FileSearchResult] {
    guard !query.isEmpty, query.count < 200 else { return [] }
    let nodes = await index(projectPath: projectPath)
    let allFiles = flattenFiles(nodes, projectPath: projectPath)
    let q = query.lowercased()

    var scored: [FileSearchResult] = []
    for file in allFiles {
      let nameLower = file.name.lowercased()
      let nameNoExt = (file.name as NSString).deletingPathExtension.lowercased()
      let pathLower = file.relativePath.lowercased()

      var score = 0
      if nameNoExt == q {
        // Exact match (without extension)
        score = 5000
      } else if nameNoExt.hasPrefix(q) {
        // Filename starts with query (without extension)
        score = 4000 + (100 - min(nameLower.count, 100))
      } else if nameLower.hasPrefix(q) {
        // Filename starts with query (with extension)
        score = 3500 + (100 - min(nameLower.count, 100))
      } else if nameLower.contains(q), let nameRange = nameLower.range(of: q) {
        // Filename contains query
        let pos = nameRange.lowerBound.utf16Offset(in: nameLower)
        score = 2000 + (200 - pos) + (100 - min(nameLower.count, 100))
      } else if pathLower.contains(q), let pathRange = pathLower.range(of: q) {
        // Path contains query
        let pos = pathRange.lowerBound.utf16Offset(in: pathLower)
        score = 1000 + (500 - min(pos, 500))
      }

      guard score > 0 else { continue }
      scored.append(FileSearchResult(
        id: file.id, name: file.name, relativePath: file.relativePath,
        absolutePath: file.absolutePath, score: score
      ))
    }

    scored.sort {
      if $0.score != $1.score { return $0.score > $1.score }
      return $0.name < $1.name
    }
    return Array(scored.prefix(Self.maxSearchResults))
  }

  /// Removes the cache entry for `projectPath`.
  public func invalidate(projectPath: String) {
    cache.removeValue(forKey: projectPath)
  }

  /// Reads a file at `path` as a UTF-8 string.
  /// `projectPath` is required so the read is validated to stay within the project root.
  public func readFile(at path: String, projectPath: String) throws -> String {
    let validatedURL = try validatePath(path, within: projectPath, forWrite: false)
    return try String(contentsOf: validatedURL, encoding: .utf8)
  }

  /// Writes `content` to the file at `path` atomically, then invalidates any matching project cache.
  /// `projectPath` is required so the write is validated to stay within the project root.
  public func writeFile(at path: String, content: String, projectPath: String) throws {
    let validatedURL = try validatePath(path, within: projectPath, forWrite: true)
    try content.write(to: validatedURL, atomically: true, encoding: .utf8)
    // Invalidate the cache for any project whose path is a prefix of the written file
    for key in cache.keys where Self.isPath(validatedURL.path, within: key) {
      cache.removeValue(forKey: key)
    }
  }

  // MARK: - Path Validation

  /// Throws if `path` does not reside inside `projectRoot` after resolving symlinks.
  private func validatePath(_ path: String, within projectRoot: String, forWrite: Bool) throws -> URL {
    let resolvedRootURL = Self.resolvedURL(for: projectRoot)
    let candidateURL = URL(fileURLWithPath: path).standardizedFileURL

    let resolvedCandidateURL: URL
    if forWrite {
      let resolvedParentURL = Self.resolvedURL(for: candidateURL.deletingLastPathComponent().path)
      resolvedCandidateURL = resolvedParentURL
        .appendingPathComponent(candidateURL.lastPathComponent)
        .standardizedFileURL
    } else {
      resolvedCandidateURL = Self.resolvedURL(for: candidateURL.path)
    }

    guard Self.isPath(resolvedCandidateURL.path, within: resolvedRootURL.path) else {
      throw CocoaError(.fileReadNoPermission, userInfo: [
        NSLocalizedDescriptionKey: "Access denied: path is outside the project directory."
      ])
    }

    return resolvedCandidateURL
  }

  // MARK: - Cache Helpers

  private func isCacheStale(_ date: Date) -> Bool {
    Date().timeIntervalSince(date) > Self.cacheTTL
  }

  // MARK: - Scanning

  private func scanDirectory(at path: String) async -> [FileTreeNode] {
    await Task.detached(priority: .utility) {
      let rootPatterns = FileIndexService.parseGitignore(at: path, relativeTo: path)
      return FileIndexService.scanDirectorySync(
        at: path, relativeTo: path, depth: 0, inheritedRules: rootPatterns
      )
    }.value
  }

  private static func scanDirectorySync(
    at path: String,
    relativeTo rootPath: String,
    depth: Int,
    inheritedRules: [IgnoreRule]
  ) -> [FileTreeNode] {
    guard depth < maxDepth else { return [] }

    let fm = FileManager.default

    guard let rawEntries = try? fm.contentsOfDirectory(atPath: path) else {
      return []
    }

    // Merge inherited rules with this directory's own .gitignore rules.
    let localRules = depth == 0 ? [] : parseGitignore(at: path, relativeTo: rootPath)
    let allRules = inheritedRules + localRules

    var nodes: [FileTreeNode] = []

    for name in rawEntries {
      // Hard-exclude check
      if hardExcludedNames.contains(name) { continue }

      // Hidden file filtering
      if name.hasPrefix(".") {
        guard allowedHiddenNames.contains(name) else { continue }
      }

      let fullPath = (path as NSString).appendingPathComponent(name)
      let relativePath = fullPath.hasPrefix(rootPath + "/")
        ? String(fullPath.dropFirst(rootPath.count + 1))
        : name

      // Skip symlinks to prevent traversal outside the project root
      if let attrs = try? fm.attributesOfItem(atPath: fullPath),
         attrs[.type] as? FileAttributeType == .typeSymbolicLink {
        continue
      }

      // Gitignore check
      var isDirectory: ObjCBool = false
      fm.fileExists(atPath: fullPath, isDirectory: &isDirectory)

      if isIgnored(relativePath: relativePath, isDirectory: isDirectory.boolValue, rules: allRules) {
        continue
      }

      if isDirectory.boolValue {
        let children = scanDirectorySync(
          at: fullPath, relativeTo: rootPath, depth: depth + 1,
          inheritedRules: allRules
        )
        let node = FileTreeNode(
          id: fullPath,
          name: name,
          path: fullPath,
          isDirectory: true,
          children: children
        )
        nodes.append(node)
      } else {
        let node = FileTreeNode(
          id: fullPath,
          name: name,
          path: fullPath,
          isDirectory: false
        )
        nodes.append(node)
      }
    }

    // Sort: directories first (alphabetical), then files (alphabetical)
    nodes.sort { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory {
        return lhs.isDirectory
      }
      return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    return nodes
  }

  // MARK: - Gitignore Parsing

  private static func parseGitignore(at directoryPath: String, relativeTo rootPath: String) -> [IgnoreRule] {
    let gitignorePath = (directoryPath as NSString).appendingPathComponent(".gitignore")
    guard let content = try? String(contentsOfFile: gitignorePath, encoding: .utf8) else {
      return []
    }

    let basePath = projectRelativePath(for: directoryPath, relativeTo: rootPath)
    return content
      .components(separatedBy: .newlines)
      .compactMap { parseIgnoreRule($0, basePath: basePath) }
  }

  private static func parseIgnoreRule(_ rawLine: String, basePath: String) -> IgnoreRule? {
    var line = rawLine.trimmingCharacters(in: .whitespaces)
    guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

    var isNegated = false
    if line.hasPrefix("!") {
      isNegated = true
      line.removeFirst()
    }

    guard !line.isEmpty else { return nil }

    let isAnchored = line.hasPrefix("/")
    if isAnchored {
      line.removeFirst()
    }

    let directoryOnly = line.hasSuffix("/")
    if directoryOnly {
      line.removeLast()
    }

    guard !line.isEmpty else { return nil }

    return IgnoreRule(
      basePath: basePath,
      pattern: line,
      isNegated: isNegated,
      directoryOnly: directoryOnly,
      matchesRelativePath: isAnchored || line.contains("/")
    )
  }

  private static func isIgnored(relativePath: String, isDirectory: Bool, rules: [IgnoreRule]) -> Bool {
    var ignored = false

    for rule in rules {
      if matchesRule(rule, relativePath: relativePath, isDirectory: isDirectory) {
        ignored = !rule.isNegated
      }
    }

    return ignored
  }

  private static func matchesRule(_ rule: IgnoreRule, relativePath: String, isDirectory: Bool) -> Bool {
    guard let scopedPath = applyBasePath(rule.basePath, to: relativePath), !scopedPath.isEmpty else {
      return false
    }

    if rule.matchesRelativePath {
      if rule.directoryOnly {
        return scopedPath == rule.pattern || scopedPath.hasPrefix(rule.pattern + "/")
      }

      return globMatch(pattern: rule.pattern, string: scopedPath)
    }

    let components = scopedPath.split(separator: "/")
    for (index, component) in components.enumerated() {
      guard globMatch(pattern: rule.pattern, string: String(component)) else { continue }

      if !rule.directoryOnly {
        return true
      }

      let isLastComponent = index == components.count - 1
      if !isLastComponent || isDirectory {
        return true
      }
    }

    return false
  }

  private static func applyBasePath(_ basePath: String, to relativePath: String) -> String? {
    guard !basePath.isEmpty else { return relativePath }
    guard relativePath.hasPrefix(basePath + "/") else { return nil }
    return String(relativePath.dropFirst(basePath.count + 1))
  }

  /// Lightweight glob match for gitignore-style matching.
  /// Supports `*`, `**`, and `?`, with `*` not crossing path separators.
  private static func globMatch(pattern: String, string: String) -> Bool {
    let regexMetaCharacters = CharacterSet(charactersIn: "\\.^$+()[]{}|")
    var regex = "^"
    var index = pattern.startIndex

    while index < pattern.endIndex {
      let character = pattern[index]

      if character == "*" {
        let nextIndex = pattern.index(after: index)
        if nextIndex < pattern.endIndex, pattern[nextIndex] == "*" {
          regex += ".*"
          index = pattern.index(after: nextIndex)
        } else {
          regex += "[^/]*"
          index = nextIndex
        }
        continue
      }

      if character == "?" {
        regex += "[^/]"
        index = pattern.index(after: index)
        continue
      }

      if String(character).rangeOfCharacter(from: regexMetaCharacters) != nil {
        regex += "\\"
      }

      regex.append(character)
      index = pattern.index(after: index)
    }

    regex += "$"
    return string.range(of: regex, options: .regularExpression) != nil
  }

  private static func projectRelativePath(for path: String, relativeTo rootPath: String) -> String {
    let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
    let standardizedRoot = URL(fileURLWithPath: rootPath).standardizedFileURL.path
    guard standardizedPath != standardizedRoot else { return "" }
    guard standardizedPath.hasPrefix(standardizedRoot + "/") else { return "" }
    return String(standardizedPath.dropFirst(standardizedRoot.count + 1))
  }

  private static func resolvedURL(for path: String) -> URL {
    URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
  }

  private static func isPath(_ path: String, within rootPath: String) -> Bool {
    path == rootPath || path.hasPrefix(rootPath + "/")
  }

  private static func relativePathIfContained(_ path: String, within projectPath: String) -> String? {
    let resolvedRootPath = resolvedURL(for: projectPath).path
    let resolvedPath = resolvedURL(for: path).path
    guard isPath(resolvedPath, within: resolvedRootPath), resolvedPath != resolvedRootPath else {
      return nil
    }

    return String(resolvedPath.dropFirst(resolvedRootPath.count + 1))
  }

  // MARK: - Search Helpers

  /// Recursively flattens all leaf file nodes into `FileSearchResult` objects.
  private func flattenFiles(_ nodes: [FileTreeNode], projectPath: String) -> [FileSearchResult] {
    var results: [FileSearchResult] = []
    flattenFilesInto(&results, nodes: nodes, projectPath: projectPath)
    return results
  }

  private func flattenFilesInto(
    _ results: inout [FileSearchResult],
    nodes: [FileTreeNode],
    projectPath: String
  ) {
    for node in nodes {
      if node.isDirectory {
        if let children = node.children {
          flattenFilesInto(&results, nodes: children, projectPath: projectPath)
        }
      } else {
        let relativePath = node.path.hasPrefix(projectPath + "/")
          ? String(node.path.dropFirst(projectPath.count + 1))
          : node.name
        results.append(FileSearchResult(
          id: node.path,
          name: node.name,
          relativePath: relativePath,
          absolutePath: node.path,
          score: 0
        ))
      }
    }
  }
}
