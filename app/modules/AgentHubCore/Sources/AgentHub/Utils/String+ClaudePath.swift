//
//  String+ClaudePath.swift
//  AgentHub
//
//  Helper for encoding paths to match Claude CLI's project directory naming convention.
//

import Foundation

extension String {
  /// Encodes a file path for Claude's project directory naming convention.
  ///
  /// Claude CLI replaces "/", ".", and "_" with "-" when creating project directories.
  /// For example: `/Users/james/Desktop/git/new_hub` becomes `-Users-james-Desktop-git-new-hub`
  /// And: `/Users/james/repo/.claude/worktrees/feat` becomes `-Users-james-repo--claude-worktrees-feat`
  ///
  /// This must match the encoding used by Claude CLI to correctly locate session files.
  var claudeProjectPathEncoded: String {
    self
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ".", with: "-")
      .replacingOccurrences(of: "_", with: "-")
  }
}
