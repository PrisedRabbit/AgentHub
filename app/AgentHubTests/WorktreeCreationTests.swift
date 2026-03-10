import Combine
import Foundation
import Testing
@testable import AgentHubCore

// MARK: - Minimal mocks for CLISessionsViewModel dependencies

private final class MockMonitorService: SessionMonitorServiceProtocol, @unchecked Sendable {
  private let subject = PassthroughSubject<[SelectedRepository], Never>()
  var repositoriesPublisher: AnyPublisher<[SelectedRepository], Never> { subject.eraseToAnyPublisher() }
  func addRepository(_ path: String) async -> SelectedRepository? { nil }
  func removeRepository(_ path: String) async {}
  func getSelectedRepositories() async -> [SelectedRepository] { [] }
  func setSelectedRepositories(_ repositories: [SelectedRepository]) async {}
  func refreshSessions(skipWorktreeRedetection: Bool) async {}
}

private final class MockFileWatcher: SessionFileWatcherProtocol, @unchecked Sendable {
  private let subject = PassthroughSubject<SessionFileWatcher.StateUpdate, Never>()
  var statePublisher: AnyPublisher<SessionFileWatcher.StateUpdate, Never> { subject.eraseToAnyPublisher() }
  func startMonitoring(sessionId: String, projectPath: String, sessionFilePath: String?) async {}
  func stopMonitoring(sessionId: String) async {}
  func getState(sessionId: String) async -> SessionMonitorState? { nil }
  func refreshState(sessionId: String) async {}
  func setApprovalTimeout(_ seconds: Int) async {}
}

@MainActor
private func makeViewModel() -> MultiSessionLaunchViewModel {
  let claudeVM = CLISessionsViewModel(
    monitorService: MockMonitorService(),
    fileWatcher: MockFileWatcher(),
    searchService: nil,
    cliConfiguration: .claudeDefault,
    providerKind: .claude
  )
  let codexVM = CLISessionsViewModel(
    monitorService: MockMonitorService(),
    fileWatcher: MockFileWatcher(),
    searchService: nil,
    cliConfiguration: .codexDefault,
    providerKind: .codex
  )
  return MultiSessionLaunchViewModel(claudeViewModel: claudeVM, codexViewModel: codexVM)
}

// MARK: - CLICommandConfiguration --worktree flag tests

@Suite("CLICommandConfiguration.argumentsForSession — worktree flag")
struct CLICommandConfigurationWorktreeTests {

  private let config = CLICommandConfiguration.claudeDefault

  @Test("No --worktree flag when worktreeName is nil")
  func noWorktreeFlagWhenNil() {
    let args = config.argumentsForSession(sessionId: nil, prompt: nil, worktreeName: nil)
    #expect(!args.contains("--worktree"))
  }

  @Test("Emits bare --worktree when name is empty")
  func bareWorktreeFlagForEmptyName() {
    let args = config.argumentsForSession(sessionId: nil, prompt: nil, worktreeName: "")
    #expect(args.contains("--worktree"))
    // No branch-name value should follow
    if let idx = args.firstIndex(of: "--worktree") {
      let next = args.index(after: idx)
      if next < args.endIndex {
        #expect(args[next].hasPrefix("-"), "Expected no branch-name argument after bare --worktree")
      }
    }
  }

  @Test("Bare --worktree appears before prompt")
  func bareWorktreeFlagBeforePrompt() {
    let args = config.argumentsForSession(sessionId: nil, prompt: "do something", worktreeName: "")
    #expect(args.contains("--worktree"))
    #expect(args.last == "do something")
  }

  @Test("Emits --worktree <name> for non-empty name")
  func namedWorktreeFlag() {
    let args = config.argumentsForSession(sessionId: nil, prompt: nil, worktreeName: "my-branch")
    guard let idx = args.firstIndex(of: "--worktree") else {
      Issue.record("Expected --worktree flag")
      return
    }
    let nameIdx = args.index(after: idx)
    #expect(nameIdx < args.endIndex)
    #expect(args[nameIdx] == "my-branch")
  }

  @Test("--worktree <name> appears before prompt")
  func namedWorktreeFlagBeforePrompt() {
    let args = config.argumentsForSession(sessionId: nil, prompt: "run tests", worktreeName: "feat-login")
    guard let idx = args.firstIndex(of: "--worktree") else {
      Issue.record("Expected --worktree flag")
      return
    }
    #expect(args[idx + 1] == "feat-login")
    #expect(args.last == "run tests")
  }

  @Test("--worktree not appended when resuming a real session")
  func noWorktreeFlagOnResume() {
    let args = config.argumentsForSession(
      sessionId: "abc-123",
      prompt: nil,
      worktreeName: "feat-login"
    )
    #expect(!args.contains("--worktree"))
    #expect(args.contains("-r"))
    #expect(args.contains("abc-123"))
  }

  @Test("--worktree not appended when resuming with prompt")
  func noWorktreeFlagOnResumeWithPrompt() {
    let args = config.argumentsForSession(
      sessionId: "real-session-id",
      prompt: "continue",
      worktreeName: "some-branch"
    )
    #expect(!args.contains("--worktree"))
  }

  @Test("--worktree appended for pending- session IDs (treated as new)")
  func worktreeFlagForPendingSession() {
    let args = config.argumentsForSession(
      sessionId: "pending-42",
      prompt: nil,
      worktreeName: "feat-x"
    )
    #expect(args.contains("--worktree"))
  }

  @Test("--worktree appended when sessionId is empty string")
  func worktreeFlagForEmptySessionId() {
    let args = config.argumentsForSession(
      sessionId: "",
      prompt: nil,
      worktreeName: "feat-x"
    )
    #expect(args.contains("--worktree"))
  }

  @Test("Both --dangerously-skip-permissions and --worktree emitted for new session")
  func dangerouslyAndWorktreeTogether() {
    let args = config.argumentsForSession(
      sessionId: nil,
      prompt: nil,
      dangerouslySkipPermissions: true,
      worktreeName: "safe-branch"
    )
    #expect(args.contains("--dangerously-skip-permissions"))
    #expect(args.contains("--worktree"))
    if let idx = args.firstIndex(of: "--worktree") {
      #expect(args[idx + 1] == "safe-branch")
    }
  }

  @Test("Codex mode never emits --worktree")
  func codexIgnoresWorktreeName() {
    let codex = CLICommandConfiguration.codexDefault
    let args = codex.argumentsForSession(sessionId: nil, prompt: nil, worktreeName: "some-branch")
    #expect(!args.contains("--worktree"))
  }
}

// MARK: - MultiSessionLaunchViewModel claudeWorktreeOption tests

@Suite("MultiSessionLaunchViewModel — claudeWorktreeOption")
struct MultiSessionLaunchViewModelWorktreeOptionTests {

  @Test("Returns nil when Claude is disabled")
  @MainActor
  func nilWhenClaudeDisabled() {
    let vm = makeViewModel()
    vm.claudeMode = .disabled
    vm.claudeUseWorktree = true
    vm.claudeWorktreeName = "branch"
    #expect(vm.claudeWorktreeOption == nil)
  }

  @Test("Returns nil when claudeUseWorktree is false")
  @MainActor
  func nilWhenFlagOff() {
    let vm = makeViewModel()
    vm.claudeMode = .enabled
    vm.claudeUseWorktree = false
    vm.claudeWorktreeName = "branch"
    #expect(vm.claudeWorktreeOption == nil)
  }

  @Test("Returns empty string for auto-generated name")
  @MainActor
  func emptyStringForAutoName() {
    let vm = makeViewModel()
    vm.claudeMode = .enabled
    vm.claudeUseWorktree = true
    vm.claudeWorktreeName = ""
    #expect(vm.claudeWorktreeOption == "")
  }

  @Test("Returns branch name when set")
  @MainActor
  func returnsBranchName() {
    let vm = makeViewModel()
    vm.claudeMode = .enabled
    vm.claudeUseWorktree = true
    vm.claudeWorktreeName = "feat-new-ui"
    #expect(vm.claudeWorktreeOption == "feat-new-ui")
  }

  @Test("Returns non-nil for enabledDangerously mode")
  @MainActor
  func worksWithDangerousMode() {
    let vm = makeViewModel()
    vm.claudeMode = .enabledDangerously
    vm.claudeUseWorktree = true
    vm.claudeWorktreeName = "hotfix"
    #expect(vm.claudeWorktreeOption == "hotfix")
  }
}

// MARK: - MultiSessionLaunchViewModel reset() tests

@Suite("MultiSessionLaunchViewModel — reset clears worktree state")
struct MultiSessionLaunchViewModelResetTests {

  @Test("reset() sets claudeUseWorktree to false")
  @MainActor
  func resetClearsUseWorktree() {
    let vm = makeViewModel()
    vm.claudeMode = .enabled
    vm.claudeUseWorktree = true
    vm.reset()
    #expect(vm.claudeUseWorktree == false)
  }

  @Test("reset() clears claudeWorktreeName")
  @MainActor
  func resetClearsWorktreeName() {
    let vm = makeViewModel()
    vm.claudeUseWorktree = true
    vm.claudeWorktreeName = "some-branch"
    vm.reset()
    #expect(vm.claudeWorktreeName == "")
  }

  @Test("reset() leaves claudeWorktreeOption as nil")
  @MainActor
  func resetLeavesOptionNil() {
    let vm = makeViewModel()
    vm.claudeMode = .enabled
    vm.claudeUseWorktree = true
    vm.claudeWorktreeName = "branch"
    vm.reset()
    #expect(vm.claudeWorktreeOption == nil)
  }
}

// MARK: - worktreeRow visibility condition (logic mirroring the View)

@Suite("worktreeRow visibility condition")
struct WorktreeRowVisibilityTests {

  /// Mirrors the condition in MultiSessionLaunchView:
  ///   selectedRepository != nil && isClaudeSelected && !isCodexSelected && workMode == .local
  @MainActor
  private func isWorktreeRowVisible(_ vm: MultiSessionLaunchViewModel) -> Bool {
    vm.selectedRepository != nil
      && vm.isClaudeSelected
      && !vm.isCodexSelected
      && vm.workMode == .local
  }

  @Test("Hidden when no repository selected")
  @MainActor
  func hiddenWithoutRepo() {
    let vm = makeViewModel()
    vm.claudeMode = .enabled
    vm.isCodexSelected = false
    vm.workMode = .local
    vm.selectedRepository = nil
    #expect(isWorktreeRowVisible(vm) == false)
  }

  @Test("Hidden when Claude is not selected")
  @MainActor
  func hiddenWhenClaudeDisabled() {
    let vm = makeViewModel()
    vm.claudeMode = .disabled
    vm.isCodexSelected = false
    vm.workMode = .local
    vm.selectedRepository = SelectedRepository(path: "/repo", name: "repo")
    #expect(isWorktreeRowVisible(vm) == false)
  }

  @Test("Hidden when Codex is also selected")
  @MainActor
  func hiddenWhenCodexAlsoSelected() {
    let vm = makeViewModel()
    vm.claudeMode = .enabled
    vm.isCodexSelected = true
    vm.workMode = .local
    vm.selectedRepository = SelectedRepository(path: "/repo", name: "repo")
    #expect(isWorktreeRowVisible(vm) == false)
  }

  @Test("Hidden when workMode is .worktree")
  @MainActor
  func hiddenInWorktreeMode() {
    let vm = makeViewModel()
    vm.claudeMode = .enabled
    vm.isCodexSelected = false
    vm.workMode = .worktree
    vm.selectedRepository = SelectedRepository(path: "/repo", name: "repo")
    #expect(isWorktreeRowVisible(vm) == false)
  }

  @Test("Visible when repo selected, Claude only, local mode")
  @MainActor
  func visibleForValidCondition() {
    let vm = makeViewModel()
    vm.claudeMode = .enabled
    vm.isCodexSelected = false
    vm.workMode = .local
    vm.selectedRepository = SelectedRepository(path: "/repo", name: "repo")
    #expect(isWorktreeRowVisible(vm) == true)
  }
}

// MARK: - CLICommandConfiguration plan mode tests

@Suite("CLICommandConfiguration.argumentsForSession — plan mode")
struct CLICommandConfigurationPlanModeTests {

  private let claude = CLICommandConfiguration.claudeDefault
  private let codex  = CLICommandConfiguration.codexDefault

  // MARK: Claude

  @Test("Claude emits --permission-mode plan when permissionModePlan is true")
  func claudePlanModeFlag() {
    let args = claude.argumentsForSession(sessionId: nil, prompt: nil, permissionModePlan: true)
    guard let idx = args.firstIndex(of: "--permission-mode") else {
      Issue.record("Expected --permission-mode flag")
      return
    }
    let valueIdx = args.index(after: idx)
    #expect(valueIdx < args.endIndex)
    #expect(args[valueIdx] == "plan")
  }

  @Test("Claude plan mode takes precedence over dangerouslySkipPermissions")
  func claudePlanModePrecedence() {
    let args = claude.argumentsForSession(
      sessionId: nil,
      prompt: nil,
      dangerouslySkipPermissions: true,
      permissionModePlan: true
    )
    #expect(args.contains("--permission-mode"))
    #expect(!args.contains("--dangerously-skip-permissions"))
  }

  @Test("Claude does not emit --permission-mode when plan mode is off")
  func claudeNoPlanModeByDefault() {
    let args = claude.argumentsForSession(sessionId: nil, prompt: nil, permissionModePlan: false)
    #expect(!args.contains("--permission-mode"))
  }

  @Test("Claude plan mode flag appears before prompt")
  func claudePlanModeFlagBeforePrompt() {
    let args = claude.argumentsForSession(sessionId: nil, prompt: "fix bug", permissionModePlan: true)
    #expect(args.last == "fix bug")
    #expect(args.contains("--permission-mode"))
  }

  // MARK: Codex

  @Test("Codex emits no --ask-for-approval flag when permissionModePlan is true")
  func codexNoApprovalFlagInPlanMode() {
    let args = codex.argumentsForSession(sessionId: nil, prompt: nil, permissionModePlan: true)
    #expect(!args.contains("--ask-for-approval"))
  }

  @Test("Codex with plan mode true and a prompt emits only the prompt")
  func codexPlanModeWithPrompt() {
    let args = codex.argumentsForSession(sessionId: nil, prompt: "do work", permissionModePlan: true)
    #expect(args == ["do work"])
  }

  @Test("Codex with plan mode true and no prompt emits empty args")
  func codexPlanModeNoPrompt() {
    let args = codex.argumentsForSession(sessionId: nil, prompt: nil, permissionModePlan: true)
    #expect(args.isEmpty)
  }

  @Test("Codex resume ignores permissionModePlan")
  func codexResumeIgnoresPlanMode() {
    let args = codex.argumentsForSession(
      sessionId: "abc-123",
      prompt: nil,
      permissionModePlan: true
    )
    #expect(args.contains("resume"))
    #expect(args.contains("abc-123"))
    #expect(!args.contains("--ask-for-approval"))
  }
}

// MARK: - MultiSessionLaunchViewModel plan mode tests

@Suite("MultiSessionLaunchViewModel — plan mode")
struct MultiSessionLaunchViewModelPlanModeTests {

  /// Mirrors the condition in MultiSessionLaunchView:
  ///   disabled: viewModel.isPlanModeEnabled
  @MainActor
  private func isCodexPillDisabled(_ vm: MultiSessionLaunchViewModel) -> Bool {
    vm.isPlanModeEnabled
  }

  @Test("isPlanModeEnabled defaults to false")
  @MainActor
  func defaultsToFalse() {
    let vm = makeViewModel()
    #expect(vm.isPlanModeEnabled == false)
  }

  @Test("reset() clears isPlanModeEnabled")
  @MainActor
  func resetClearsPlanMode() {
    let vm = makeViewModel()
    vm.isPlanModeEnabled = true
    vm.reset()
    #expect(vm.isPlanModeEnabled == false)
  }

  @Test("Codex pill is not disabled when plan mode is off")
  @MainActor
  func codexPillEnabledByDefault() {
    let vm = makeViewModel()
    #expect(isCodexPillDisabled(vm) == false)
  }

  @Test("Codex pill is disabled when plan mode is on")
  @MainActor
  func codexPillDisabledInPlanMode() {
    let vm = makeViewModel()
    vm.isPlanModeEnabled = true
    #expect(isCodexPillDisabled(vm) == true)
  }

  @Test("selectedProviders excludes Codex when Codex is deselected in plan mode")
  @MainActor
  func selectedProvidersExcludesCodexInPlanMode() {
    let vm = makeViewModel()
    vm.isPlanModeEnabled = true
    vm.isCodexSelected = false   // UI enforces this via .onChange
    vm.claudeMode = .enabled
    #expect(!vm.selectedProviders.contains(.codex))
    #expect(vm.selectedProviders.contains(.claude))
  }
}
