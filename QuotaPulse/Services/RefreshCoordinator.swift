actor RefreshCoordinator {
    private let usageService: UsageService
    private var refreshTask: Task<[ProviderState], Never>?

    init(usageService: UsageService) {
        self.usageService = usageService
    }

    func refresh() async -> [ProviderState] {
        if let refreshTask {
            return await refreshTask.value
        }

        let usageService = usageService
        let task = Task {
            await usageService.refresh()
        }
        refreshTask = task

        let states = await task.value
        refreshTask = nil
        return states
    }

    func cancel() {
        refreshTask?.cancel()
    }
}
