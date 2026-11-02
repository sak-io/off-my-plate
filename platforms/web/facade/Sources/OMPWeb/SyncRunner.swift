import Foundation

/// Runs the async services to completion without a run loop, for hosts that have no threads (the
/// WebAssembly module: JavaScript calls an export and expects the answer when it returns).
///
/// How: the work runs in a task whose *task executor preference* is `DrainExecutor`. Jobs of that
/// task, and of the default actors it hops to (the in-memory repositories and the service lock),
/// are queued on the executor instead of the global pool. The caller then runs the queued jobs one by
/// one, on its own stack, until the task has produced its result. Deterministic: one thread, FIFO.
///
/// If a job escapes to the global pool (it should not), the queue runs dry before the result exists:
/// on Wasm that is reported as `executor_stalled`; natively the caller waits for the other thread.
///
/// Known risk (documented in docs/windows/w03-report.md): the services serialise writes with an actor lock.
/// A call that is abandoned (stalled or runaway) may leave that lock held. `Facade.handleSync` therefore
/// rebuilds the services over the same repositories after a stall, so later calls are not blocked.
/// Today nothing awaits anything outside the facade's own actors, so a stall is not expected.
enum SyncRunner {
    /// - Parameters:
    ///   - maxIdleRounds: native only: how long to wait for a job that escaped to another thread.
    ///   - maxJobs: a runaway task that keeps re-queueing itself is abandoned after this many jobs.
    /// - Returns: the response; `stalled` is true when the call was abandoned (its task may still hold the
    ///   service lock, so the caller must recover the session, `FacadeSession.recoverAfterStall`).
    static func run(
        maxIdleRounds: Int = 30_000, maxJobs: Int = 5_000_000, _ work: @escaping @Sendable () async -> Data
    ) -> (data: Data, stalled: Bool) {
        let executor = DrainExecutor()
        let box = ResultBox()
        _ = Task(executorPreference: executor) {
            let data = await work()
            box.set(data)
        }
        var idleRounds = 0
        var jobs = 0
        while true {
            if let data = box.value { return (data, false) }
            if let job = executor.next() {
                idleRounds = 0
                jobs += 1
                if jobs > maxJobs {
                    return (Response.failure(FacadeError("executor_stalled", "The request did not finish.")), true)
                }
                job.runSynchronously(on: executor.asUnownedTaskExecutor())
                continue
            }
            #if os(WASI)
            return (
                Response.failure(FacadeError("executor_stalled", "The request could not run to completion on this host.")),
                true
            )
            #else
            idleRounds += 1
            if idleRounds > maxIdleRounds {
                return (Response.failure(FacadeError("executor_stalled", "The request did not complete.")), true)
            }
            usleep(1_000)
            #endif
        }
    }
}

private final class DrainExecutor: TaskExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [UnownedJob] = []

    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        lock.lock()
        jobs.append(unowned)
        lock.unlock()
    }

    func next() -> UnownedJob? {
        lock.lock()
        defer { lock.unlock() }
        return jobs.isEmpty ? nil : jobs.removeFirst()
    }
}

private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Data?

    var value: Data? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ data: Data) {
        lock.lock()
        stored = data
        lock.unlock()
    }
}
