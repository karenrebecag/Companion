import CompanionCore
import Foundation

/// Standard executor provider: maintains list of available executors and selects one.
/// Supports detection of CLI executors and fallback to native if selected executor vanishes.
/// Uses thread-safe state management internally.
public final class ExecutorProvider: ExecutorProviderProtocol, @unchecked Sendable {
    private let nativeExecutor: any Executor
    private let cliProbe: CLIExecutorProbe
    private let stateQueue = DispatchQueue(label: "com.companion.executor-provider", attributes: .concurrent)
    private var _availableExecutors: [ExecutorDescriptor] = []
    private var _selectedExecutorId: ExecutorID?
    private var _cachedExecutors: [ExecutorID: any Executor] = [:]

    /// workdir/launcher/approvals are what a CLI executor needs to exist; a
    /// provider that cannot build one can only ever return the native path.
    public init(
        nativeExecutor: any Executor,
        cliProbe: CLIExecutorProbe,
        workdir: String? = nil,
        processLauncher: any ProcessLauncher = RealProcessLauncher(),
        approvals: (any ApprovalsProvider)? = nil
    ) {
        self.nativeExecutor = nativeExecutor
        self.cliProbe = cliProbe
        self.workdir = workdir
        self.processLauncher = processLauncher
        self.approvals = approvals
        self._selectedExecutorId = .native
    }

    private let workdir: String?
    private let processLauncher: any ProcessLauncher
    private let approvals: (any ApprovalsProvider)?

    /// Update the catalog of available executors (probe for CLI tools).
    public func refreshAvailableExecutors() async {
        let detected = await cliProbe.detectAvailable()
        let newExecutors = ExecutorCatalog.list(detected: detected)

        // Synchronous on purpose: callers await this refresh precisely to read
        // the result afterwards, and an async barrier would let them observe
        // the old selection.
        stateQueue.sync(flags: .barrier) {
            self._availableExecutors = newExecutors

            // The chosen executor may have been uninstalled since: degrade to
            // the native one instead of failing the next job.
            if let selected = self._selectedExecutorId, selected != .native {
                let available = newExecutors.map { $0.id }
                if !available.contains(selected) {
                    Log.app("executors: \(selected.rawValue) ya no está; uso el nativo")
                    self._selectedExecutorId = .native
                    self._cachedExecutors[selected] = nil
                }
            }
        }
    }

    /// Get the current list of available executors (include native).
    public func getAvailableExecutors() -> [ExecutorDescriptor] {
        var result: [ExecutorDescriptor] = []
        stateQueue.sync {
            result = _availableExecutors.isEmpty ? [ExecutorCatalog.native] : _availableExecutors
        }
        return result
    }

    /// Select an executor by ID. Returns false if ID not found (no change).
    public func selectExecutor(id: ExecutorID) -> Bool {
        var result = false
        stateQueue.sync {
            let available = _availableExecutors.isEmpty ? [ExecutorCatalog.native] : _availableExecutors
            if available.contains(where: { $0.id == id }) {
                result = true
            }
        }

        if result {
            stateQueue.async(flags: .barrier) {
                self._selectedExecutorId = id
            }
        }

        return result
    }

    private func currentCatalog() -> [ExecutorDescriptor] {
        stateQueue.sync { _availableExecutors }
    }

    /// Get the currently selected executor ID.
    public func getSelectedExecutorId() -> ExecutorID {
        var result: ExecutorID = .native
        stateQueue.sync {
            result = _selectedExecutorId ?? .native
        }
        return result
    }

    /// Implements ExecutorProviderProtocol: select executor for a handoff.
    public func selectExecutor(for _: Handoff) -> any Executor {
        var id: ExecutorID = .native
        var cached: (any Executor)? = nil

        stateQueue.sync {
            id = _selectedExecutorId ?? .native
            cached = _cachedExecutors[id]
        }

        // Check cache first
        if let cached = cached {
            return cached
        }

        // Build the chosen CLI executor; fall back to the native one when it
        // cannot be built (no workdir, no approvals, unknown id).
        var executor: any Executor = nativeExecutor
        if id != .native,
           let workdir,
           let approvals,
           let descriptor = currentCatalog().first(where: { $0.id == id }),
           let path = cliProbe.executablePath(for: id),
           let built = ExecutorFactory.createExecutor(
               descriptor: descriptor,
               workdir: workdir,
               executablePath: path,
               processLauncher: processLauncher,
               approvals: approvals) {
            executor = built
        }

        stateQueue.async(flags: .barrier) {
            self._cachedExecutors[id] = executor
        }

        return executor
    }
}
