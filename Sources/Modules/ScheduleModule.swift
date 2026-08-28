// ScheduleModule.swift — macotron.every / macotron.at wall-clock and interval jobs
import AppKit
import CQuickJS
import Foundation
import MacotronEngine
import os

private let logger = Logger(subsystem: "io.statico.macotron", category: "schedule")

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

        let ms = JSBridge.toInt32(ctx, spec)
        guard ms > 0 else {
            JS_FreeValue(ctx, protected)
            return QJS_ThrowTypeError(ctx, "every interval must be positive")
        }
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
            do {
                weekdays = try Self.parseWeekdays(opts?["weekdays"])
            } catch {
                return QJS_ThrowTypeError(ctx, "invalid weekdays")
            }
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
        }, "stop", 0, JS_CFUNC_generic_magic, Int32(jobID))
    }

    /// Time spent in interval callbacks, per plugin, logged once a minute.
    /// Idle CPU is nearly always a plugin ticking, and `sample` needs root, so
    /// the app has to be able to say which plugin on its own.
    private var spend: [String: TimeInterval] = [:]
    private var spendSince = CFAbsoluteTimeGetCurrent()

    private func account(_ file: String?, _ seconds: TimeInterval) {
        spend[file ?? "unknown", default: 0] += seconds
        let window = CFAbsoluteTimeGetCurrent() - spendSince
        guard window >= 60 else { return }
        let busy = spend.values.reduce(0, +)
        let worst = spend.sorted { $0.value > $1.value }.prefix(5)
            .map { "\($0.key) \(Int($0.value * 1000))ms" }
            .joined(separator: ", ")
        logger.notice(
            "timers used \(String(format: "%.2f", busy / window * 100), privacy: .public)% of a core over \(Int(window))s: \(worst, privacy: .public)"
        )
        spend.removeAll()
        spendSince = CFAbsoluteTimeGetCurrent()
    }

    fileprivate func invokeJob(_ job: ScheduleJob) {
        guard let engine, !job.cancelled else { return }
        let start = CFAbsoluteTimeGetCurrent()
        defer { account(job.pluginFile, CFAbsoluteTimeGetCurrent() - start) }
        // A job that stops itself -- poll until done, count down to zero -- runs
        // stop() from inside this call, and stop() releases the callback that is
        // still on the stack. Hold it for the duration.
        let fn = JS_DupValue(engine.context, job.callback)
        defer { JS_FreeValue(engine.context, fn) }
        engine.withEvaluatingFile(job.pluginFile) {
            if let result = engine.callJS(fn, label: "schedule job \(job.id)") {
                JS_FreeValue(engine.context, result)
            }
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

    private static func parseWeekdays(_ value: Any?) throws -> [Int]? {
        guard let arr = value as? [Any] else { return nil }
        guard !arr.isEmpty else { throw WeekdayError.invalid }
        var days: [Int] = []
        for item in arr {
            let day: Int?
            switch item {
            case let i as Int: day = i
            case let d as Double: day = Int(d)
            default: day = nil
            }
            guard let day, (0...6).contains(day) else { throw WeekdayError.invalid }
            days.append(day)
        }
        return days
    }

    fileprivate var isDryRun: Bool { engine?.dryRun == true }

    private enum WeekdayError: Error {
        case invalid
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
        guard module?.isDryRun != true else { return }
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
        guard module?.isDryRun != true else { return }
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
    Engine.module(ctx, "__scheduleModule")
}
