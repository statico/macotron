// ScheduleModule.swift — macotron.every / macotron.at wall-clock and interval jobs
import AppKit
import CQuickJS
import Foundation
import MacotronEngine

@MainActor
public final class ScheduleModule: NativeModule {
    public let name = "schedule"

    private weak var engine: Engine?
    private var jobs: [UInt64: ScheduleJob] = [:]
    private var nextJobID: UInt64 = 1
    private var observerTokens: [NSObjectProtocol] = []

    var activeJobCount: Int { jobs.count }

    public init() {}

    public func register(in engine: Engine, options: [String: Any]) {
        self.engine = engine
        engine.configStore["__scheduleModule"] = self

        let ctx = engine.context!
        let global = JS_GetGlobalObject(ctx)
        let macotron = JSBridge.getProperty(ctx, global, "macotron")

        JS_SetPropertyStr(ctx, macotron, "every", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2 else {
                return QJS_ThrowTypeError(ctx, "every(msOrDuration, callback)")
            }
            guard JS_IsFunction(ctx, argv[1]) else {
                return QJS_ThrowTypeError(ctx, "every requires a callback")
            }
            guard let module = scheduleModule(ctx) else { return QJS_Undefined() }
            return module.registerEvery(ctx: ctx, spec: argv[0], callback: argv[1])
        }, "every", 2))

        JS_SetPropertyStr(ctx, macotron, "at", JS_NewCFunction(ctx, { ctx, _, argc, argv in
            guard let ctx, let argv, argc >= 2 else {
                return QJS_ThrowTypeError(ctx, "at(time, callback | opts, callback?)")
            }
            guard let module = scheduleModule(ctx) else { return QJS_Undefined() }
            return module.registerAt(ctx: ctx, argc: argc, argv: argv)
        }, "at", 3))

        JS_FreeValue(ctx, macotron)
        JS_FreeValue(ctx, global)

        guard !engine.dryRun else { return }
        startObservers()
    }

    public func cleanup() {
        for (_, job) in jobs {
            job.cancel(engine: engine)
        }
        jobs.removeAll()
        stopObservers()
        engine = nil
    }

    func cancelJob(_ id: UInt64) {
        guard let job = jobs.removeValue(forKey: id) else { return }
        job.cancel(engine: engine)
    }

    private func registerEvery(ctx: OpaquePointer, spec: JSValue, callback: JSValue) -> JSValue {
        guard let engine else { return QJS_Undefined() }

        let pluginFile = engine.currentEvaluatingFile
        let protected = JS_DupValue(ctx, callback)

        if JS_IsString(spec) {
            guard let raw = JSBridge.toString(ctx, spec) else {
                JS_FreeValue(ctx, protected)
                return QJS_ThrowTypeError(ctx, "invalid schedule")
            }
            let schedule: PluginSchedule
            do {
                schedule = try PluginSchedule.parseEvery(raw)
            } catch {
                JS_FreeValue(ctx, protected)
                return QJS_ThrowTypeError(ctx, "invalid schedule: \(raw)")
            }
            engine.recordPluginEvent("schedule:every \(raw)")
            let id = addWallClockJob(ctx: ctx, schedule: schedule, callback: protected, pluginFile: pluginFile)
            return makeStopFunction(ctx: ctx, jobID: id)
        }

        let ms = Int32(JSBridge.toDouble(ctx, spec))
        guard ms > 0 else {
            JS_FreeValue(ctx, protected)
            return QJS_ThrowTypeError(ctx, "every interval must be positive")
        }
        engine.recordPluginEvent("schedule:every \(ms)")
        let id = addIntervalJob(ctx: ctx, ms: ms, callback: protected, pluginFile: pluginFile)
        return makeStopFunction(ctx: ctx, jobID: id)
    }

    private func registerAt(ctx: OpaquePointer, argc: Int32, argv: UnsafePointer<JSValue>) -> JSValue {
        guard let engine else { return QJS_Undefined() }

        guard let time = JSBridge.toString(ctx, argv[0]) else {
            return QJS_ThrowTypeError(ctx, "at requires a time string")
        }

        let callback: JSValue
        let weekdays: [Int]?
        if JS_IsFunction(ctx, argv[1]) {
            callback = argv[1]
            weekdays = nil
        } else if argc >= 3, JS_IsFunction(ctx, argv[2]) {
            let opts = JSBridge.jsToSwift(ctx, argv[1]) as? [String: Any]
            weekdays = Self.parseWeekdays(opts?["weekdays"])
            callback = argv[2]
        } else {
            return QJS_ThrowTypeError(ctx, "at requires a callback")
        }

        let schedule: PluginSchedule
        do {
            schedule = try PluginSchedule.parseAt(time, weekdays: weekdays)
        } catch {
            return QJS_ThrowTypeError(ctx, "invalid time: \(time)")
        }

        engine.recordPluginEvent("schedule:at \(time)")
        let protected = JS_DupValue(ctx, callback)
        let id = addWallClockJob(
            ctx: ctx,
            schedule: schedule,
            callback: protected,
            pluginFile: engine.currentEvaluatingFile
        )
        return makeStopFunction(ctx: ctx, jobID: id)
    }

    private func addIntervalJob(ctx: OpaquePointer, ms: Int32, callback: JSValue, pluginFile: String?) -> UInt64 {
        let id = nextJobID
        nextJobID += 1
        let job = ScheduleJob(id: id, callback: callback, pluginFile: pluginFile, module: self)
        jobs[id] = job
        job.startInterval(ms: ms)
        return id
    }

    private func addWallClockJob(
        ctx: OpaquePointer,
        schedule: PluginSchedule,
        callback: JSValue,
        pluginFile: String?
    ) -> UInt64 {
        let id = nextJobID
        nextJobID += 1
        let job = ScheduleJob(id: id, callback: callback, pluginFile: pluginFile, module: self)
        job.schedule = schedule
        jobs[id] = job
        job.scheduleNextWallClock()
        return id
    }

    private func makeStopFunction(ctx: OpaquePointer, jobID: UInt64) -> JSValue {
        JS_NewCFunctionMagic(ctx, { ctx, _, _, _, magic in
            guard let ctx else { return QJS_Undefined() }
            scheduleModule(ctx)?.cancelJob(UInt64(magic))
            return QJS_Undefined()
        }, "stop", 0, JS_CFUNC_generic, Int32(jobID))
    }

    fileprivate func invokeJob(_ job: ScheduleJob) {
        guard let engine, !job.cancelled else { return }
        engine.withEvaluatingFile(job.pluginFile) {
            _ = JS_Call(engine.context, job.callback, QJS_Undefined(), 0, nil)
            engine.drainJobQueue()
        }
    }

    private func handleWakeOrClockChange() {
        let now = Date()
        let calendar = Calendar.current
        for job in jobs.values where !job.cancelled && job.schedule != nil {
            guard let nextFire = job.nextFire else { continue }
            guard PluginSchedule.shouldFireMissed(scheduled: nextFire, now: now) else { continue }
            invokeJob(job)
            job.nextFire = job.schedule!.nextDate(after: now, calendar: calendar)
            job.scheduleWallClockTimer()
        }
    }

    private func startObservers() {
        stopObservers()
        let workspace = NSWorkspace.shared.notificationCenter
        observerTokens.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWakeOrClockChange() }
        })
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWakeOrClockChange() }
        })
    }

    private func stopObservers() {
        for token in observerTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens = []
    }

    private static func parseWeekdays(_ value: Any?) -> [Int]? {
        guard let arr = value as? [Any] else { return nil }
        let days = arr.compactMap { item -> Int? in
            switch item {
            case let i as Int: return i
            case let d as Double: return Int(d)
            default: return nil
            }
        }
        return days.isEmpty ? nil : days
    }
}

@MainActor
private final class ScheduleJob {
    let id: UInt64
    let callback: JSValue
    let pluginFile: String?
    private weak var module: ScheduleModule?

    var schedule: PluginSchedule?
    var nextFire: Date?
    var timer: Timer?
    var cancelled = false

    init(id: UInt64, callback: JSValue, pluginFile: String?, module: ScheduleModule) {
        self.id = id
        self.callback = callback
        self.pluginFile = pluginFile
        self.module = module
    }

    func startInterval(ms: Int32) {
        timer?.invalidate()
        let interval = TimeInterval(max(ms, 1)) / 1000
        timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let module = self.module, !self.cancelled else { return }
                module.invokeJob(self)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func scheduleNextWallClock() {
        guard let schedule else { return }
        nextFire = schedule.nextDate(after: Date(), calendar: .current)
        scheduleWallClockTimer()
    }

    func scheduleWallClockTimer() {
        timer?.invalidate()
        guard let fireDate = nextFire, !cancelled else { return }
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.wallClockFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func wallClockFired() {
        guard let module, !cancelled, let schedule else { return }
        module.invokeJob(self)
        let now = Date()
        nextFire = schedule.nextDate(after: now, calendar: .current)
        scheduleWallClockTimer()
    }

    func cancel(engine: Engine?) {
        cancelled = true
        timer?.invalidate()
        timer = nil
        if let ctx = engine?.context {
            JS_FreeValue(ctx, callback)
        }
    }
}

@MainActor
private func scheduleModule(_ ctx: OpaquePointer) -> ScheduleModule? {
    guard let opaque = JS_GetContextOpaque(ctx) else { return nil }
    let engine = Unmanaged<Engine>.fromOpaque(opaque).takeUnretainedValue()
    return engine.configStore["__scheduleModule"] as? ScheduleModule
}
