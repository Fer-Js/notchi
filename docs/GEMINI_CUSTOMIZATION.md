# Custom Gemini / Antigravity Integration Guide (For Future AI Maintainers)

This fork/build of **Notchi** adds first-class **Gemini** (`AgentProvider.gemini`) integration for [`agy-claude-tui`](../../agy-claude-tui) alongside upstream **Claude**, **Codex**, and **Devin**.

**Git layout:**
- `upstream`: `https://github.com/sk-ruban/notchi` (upstream `main`)
- `origin`: `https://github.com/Fer-Js/notchi` (fork)
- Custom branch: `feat/gemini-integration` (rebase onto `upstream/main` when updating)

**CRITICAL RULE WHEN UPDATING FROM UPSTREAM:**
When merging/rebasing upstream Notchi changes requested by the user:
1. **Preserve every file, symbol, and UI surface listed below** for `.gemini`.
2. **Keep Codex (`~/.codex/` and `CostHistoryStore.sharedCodex`) 100% native.** Never bridge Gemini into Codex files or filter `.codex` sessions to hide Gemini — Gemini uses its own `.gemini` provider, socket events, quota cache, and `~/.gemini/antigravity-cli/notchi-sessions/` cost rollouts.
3. **Keep Sparkle auto-update startup disabled** in `AppDelegate.swift` (`applicationDidFinishLaunching` must NOT auto-start Sparkle) so upstream binary releases do not overwrite the custom `/Applications/Notchi.app` bundle.

---

## 1. End-to-End Connection With `agy-claude-tui`

- **Socket transport:** `SocketServer.resolvedSocketPath` -> `~/Library/Application Support/Notchi/notchi.sock` (fallback `~/.notchi/notchi.sock` if path exceeds 103 UTF-8 bytes).
  - Client emitter lives in `agy-claude-tui/src/notchi.ts` and `agy-claude-tui/src/ui/App.tsx`.
- **Socket JSON contract (`provider: "gemini"`):**
  - Accepted events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PreCompact`, `Stop`, `SubagentStop`, `SessionEnd`.
  - Fields consumed by `AgentHookEnvelope` + `GeminiProviderAdapter`: `provider: "gemini"`, `session_id`, `transcript_path`, `cwd`, `event`, `status` (`"processing"`, `"waiting_for_input"`, `"ended"`), `permission_mode`, `interactive: true`, `gemini_process_id`, `model`, `tool`, `tool_input`, `tool_use_id`, `user_prompt`, `has_attachments`, `last_assistant_message`.
- **Quota bar source:** `GeminiUsageReader` / `GeminiUsageService` reads `~/.gemini/antigravity-cli/tui-quota-cache.json` (`gemini-5h`, `gemini-weekly`, `gemini-argon-wtu-weekly`, plus `3p-5h` / `3p-weekly` when active model starts with `claude` or `gpt`).
- **Token & cost rollout source:** `CostHistoryStore.sharedGemini` scans `[~/.gemini/antigravity-cli/notchi-sessions]` only, parsing `turn_context` and `token_count` JSONL records written by `syncNotchiGeminiUsage`.

---

## 2. Added and Modified Files (Repo Root)

### Added files
- `notchi/notchi/Assets.xcassets/gemini_*.imageset` (20 hue-shifted blue sprite sheets matching `claude_*.imageset`)
- `notchi/notchi/Resources/gemini-pricing-fallback.json`
- `notchi/notchi/Services/GeminiProviderAdapter.swift` (normalizes ACP tool names like `run_command`/`bash` -> `Bash`, `read_file` -> `Read`, `write_file` -> `Write`, `edit_file` -> `Edit`, `ask_question` -> `AskUserQuestion`, etc.)
- `notchi/notchi/Services/GeminiUsageReader.swift`
- `notchi/notchi/Services/GeminiUsageService.swift`
- `notchi/Tests/GeminiProviderTests.swift`, `notchi/Tests/GeminiUsageReaderTests.swift`, `notchi/Tests/GeminiUsageServiceTests.swift`

### Modified files
- **Models:** `AgentProvider.swift`, `NotchiState.swift`, `SpinnerVerbs.swift` (`"Geminizing"`), `CostUsageModels.swift`, `HookEvent.swift` (`NormalizedAgentEvent.geminiEvent`, `geminiProcessId`, `modelId`), `SessionData.swift` (`geminiProcessId`, `updateGeminiRuntime`).
- **Core / App:** `AppSettings.swift` (`NotchSlotContent.gemini`), `AppDelegate.swift` (`startUpdater()` disabled; `GeminiUsageService.shared.startPolling()` & `CostHistoryStore.sharedGemini` wired).
- **Services / Cost:** `IntegrationCoordinator.swift`, `ConversationParser.swift`, `SessionStore.swift`, `NotchiStateMachine.swift`, `ClaudeModelPricing.swift` (`normalizeGeminiModel`, `isGeminiModel`), `PricingCatalog.swift` (`ModelsDevKey.google`, `ProviderConfig.gemini`, `ModelsDev.google`), `CodexCostScanner.swift` (parameterized `normalizeModel`/`modelFilter` defaulting to native OpenAI), `CostHistoryStore.swift` (`.codex` untouched native scanner; `.gemini` scans `~/.gemini/antigravity-cli/notchi-sessions`).
- **Views / UI:** `TerminalColors.swift`, `ActivityRowView.swift`, `NotchContentView.swift`, `ExpandedPanelView.swift`, `UsageDetailView.swift`, `CostDashboardView.swift` (`en_US` compact token locale), `PanelSettingsView.swift` (`NotchContentViewTests.swift` picker test).

---

## 3. Update, Build, Test & Install Checklist

After merging or rebasing upstream Notchi commits:
1. Run full Xcode test suite (no Apple Developer team signing needed locally):
   ```bash
   CI=1 ./scripts/test.sh all
   ```
   Confirm `LocalizationCoverageTests` and all Gemini/Codex/Claude tests pass.
2. Build Release `.app`:
   ```bash
   xcodebuild -project notchi/notchi.xcodeproj -scheme notchi -configuration Release -derivedDataPath build/release CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
   ```
3. Temporarily unload any Notchi LaunchAgent watcher in `~/Library/LaunchAgents/` if loaded, quit Notchi, replace `/Applications/Notchi.app` from `build/release/Build/Products/Release/notchi.app`, ad-hoc sign & verify (`codesign --force --deep --sign - /Applications/Notchi.app && codesign --verify --deep --strict /Applications/Notchi.app`), relaunch, and reload the LaunchAgent.
4. Also verify `agy-claude-tui` still builds & passes (`npm run build && npm test`) and emits `provider: "gemini"` events to `~/Library/Application Support/Notchi/notchi.sock`.
