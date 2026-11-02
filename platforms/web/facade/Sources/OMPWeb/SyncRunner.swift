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
enum SyncRunner {
    static func run(_ work: @escaping @Sendable () async -> Data) -> Data {
        let executor = DrainExecutor()
        let box = ResultBox()
        _ = Task(executorPreference: executor) {
            let data = await work()
            box.set(data)
        }
        var idleRounds = 0
        while true {
            if let data = box.value { return data }
            if let job = executor.next() {
                idleRounds = 0
                job.runSynchronously(on: executor.asUnownedTaskExecutor())
                continue
            }
            #if os(WASI)
            return Response.failure(
                FacadeError("executor_stalled", "The request could not run to completion on this host."))
            #else
            idleRounds += 1
            if idleRounds > 30_000 {
                return Response.failure(FacadeError("executor_stalled", "The request did not complete."))
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
