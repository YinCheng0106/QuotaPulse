actor RefreshCoordinator {
    private let usageService: UsageService
    private var refreshTask: Task<[ProviderState], Never>?

    init(usageService: UsageService) {
        self.usageService = usageService
    }

    func refresh(eligibleProviderIDs: Set<ProviderID>? = nil) async -> [ProviderState] {
        if let refreshTask {
            return await refreshTask.value
        }

        let usageService = usageService
        let task = Task {
            await usageService.refresh(eligibleProviderIDs: eligibleProviderIDs)
        }
        refreshTask = task

        let states = await task.value
        refreshTask = nil
        return states
    }

    func providerDiagnostics() async -> [ProviderDiagnosticContext] {
        await usageService.providerDiagnostics()
    }

    func cancel() {
        refreshTask?.cancel()
    }
}
