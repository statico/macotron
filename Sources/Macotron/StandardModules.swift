// StandardModules.swift — the built-in modules that need no host wiring
import MacotronEngine
import Modules

/// Every built-in module that is constructed the same way everywhere.
///
/// Four modules are deliberately absent because they need something only the
/// caller has: `KeyboardModule` (host command callback), `MenuBarModule`
/// (delegate), `LauncherModule` (live-update callback) and
/// `LocalStorageModule` (config dir). The app wires those up itself; the
/// `--check` dry run adds plain instances. Everything else lives here once so
/// the two lists cannot drift apart.
@MainActor
func registerStandardModules(in engine: Engine) {
    engine.addModule(ShellModule())
    engine.addModule(FileSystemModule())
    engine.addModule(NotifyModule())
    engine.addModule(DialogModule())
    engine.addModule(ClipboardModule())
    engine.addModule(SnippetsModule())
    engine.addModule(EventModule())
    engine.addModule(WindowModule())
    engine.addModule(AppModule())
    engine.addModule(ScreenModule())
    engine.addModule(SystemModule())
    engine.addModule(DisplayModule())
    engine.addModule(HTTPModule())
    engine.addModule(KeychainModule())
    engine.addModule(URLSchemeModule())
    engine.addModule(SpotlightModule())
    engine.addModule(AIModule())
    engine.addModule(PanelModule())
    engine.addModule(CalendarModule())
    engine.addModule(ContactsModule())
    engine.addModule(OCRModule())
    engine.addModule(NotesModule())
    engine.addModule(RemindersModule())
    engine.addModule(HomeKitModule())
    engine.addModule(DockModule())
    engine.addModule(MediaModule())
    engine.addModule(PowerModule())
    engine.addModule(NetworkModule())
    engine.addModule(BonjourModule())
    engine.addModule(UDPModule())
    engine.addModule(AppleTVModule())
    engine.addModule(AudioModule())
    engine.addModule(IdleModule())
    engine.addModule(SpacesModule())
    engine.addModule(USBModule())
    engine.addModule(HIDModule())
    engine.addModule(QRModule())
    engine.addModule(AXModule())
    engine.addModule(CameraModule())
    engine.addModule(ShareModule())
    engine.addModule(ShortcutsModule())
    engine.addModule(ScheduleModule())
}
