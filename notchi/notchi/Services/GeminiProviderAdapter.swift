import Foundation

struct GeminiProviderAdapter: AgentProviderAdapter {
    nonisolated let provider: AgentProvider = .gemini
    private let directoryExists: @Sendable () -> Bool
    private let hooksEnabled: @Sendable () -> Bool

    nonisolated init(
        directoryExists: @escaping @Sendable () -> Bool = { GeminiProviderAdapter.defaultGeminiDirectoryExists() },
        hooksEnabled: @escaping @Sendable () -> Bool = { AppSettings.areHooksEnabled(for: .gemini) }
    ) {
        self.directoryExists = directoryExists
        self.hooksEnabled = hooksEnabled
    }

    nonisolated static var geminiDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
    }

    nonisolated static func defaultGeminiDirectoryExists() -> Bool {
        FileManager.default.fileExists(atPath: geminiDirectoryURL.path)
    }

    nonisolated private static let notchiToolNamesByGeminiToolName: [String: String] = [
        "run_command": "Bash",
        "command_status": "Bash",
        "send_command_input": "Bash",
        "bash": "Bash",
        "shell": "Bash",
        "read_file": "Read",
        "view_file": "Read",
        "view_file_outline": "Read",
        "view_code_item": "Read",
        "write_file": "Write",
        "write_to_file": "Write",
        "edit_file": "Edit",
        "replace_file_content": "Edit",
        "multi_replace_file_content": "Edit",
        "find_by_name": "Glob",
        "list_dir": "Glob",
        "glob": "Glob",
        "grep_search": "Grep",
        "grep": "Grep",
        "search_web": "WebSearch",
        "web_search": "WebSearch",
        "read_url_content": "WebFetch",
        "webfetch": "WebFetch",
        "invoke_subagent": "Task",
        "subagent": "Task",
        "task": "Task",
        "ask_question": "AskUserQuestion",
        "ask_user_question": "AskUserQuestion",
        "todo_write": "TodoWrite",
        "write_todos": "TodoWrite",
    ]

    @discardableResult
    nonisolated func installIfNeeded() -> Bool {
        isProviderAvailable()
    }

    nonisolated func uninstall() {}

    nonisolated func isProviderAvailable() -> Bool {
        directoryExists()
    }

    nonisolated func isInstalled() -> Bool {
        isProviderAvailable() && hooksEnabled()
    }

    nonisolated func configureForLaunch() {}

    nonisolated func normalize(_ envelope: AgentHookEnvelope) -> HookEvent? {
        guard let event = NormalizedAgentEvent.geminiEvent(named: envelope.event) else {
            return nil
        }

        let prompt = UserPromptContentParser.parse(
            envelope.userPrompt,
            reportedHasAttachments: envelope.hasAttachments == true
        )

        let normalizedTool = envelope.tool.map { toolName in
            Self.notchiToolNamesByGeminiToolName[toolName]
                ?? Self.notchiToolNamesByGeminiToolName[toolName.lowercased()]
                ?? toolName
        }

        return HookEvent(
            provider: provider,
            rawSessionId: envelope.sessionId,
            transcriptPath: nil,
            cwd: envelope.cwd,
            event: event,
            status: envelope.status,
            tool: normalizedTool,
            toolInput: envelope.toolInput,
            toolUseId: envelope.toolUseId,
            userPrompt: prompt.text,
            userPromptHasAttachments: prompt.hasAttachments,
            userPromptImageAttachments: prompt.imageAttachments,
            userPromptHasOtherAttachments: prompt.hasOtherAttachments,
            permissionMode: envelope.permissionMode,
            permissionSuggestions: envelope.permissionSuggestions,
            interactive: envelope.interactive,
            geminiProcessId: envelope.geminiProcessId,
            modelId: envelope.modelId,
            lastAssistantMessage: envelope.lastAssistantMessage
        )
    }
}
