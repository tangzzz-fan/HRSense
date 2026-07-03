/// Lifecycle state tracked by the root store for foreground/background/restore flows.
public enum AppLifecycleState: Equatable, Sendable {
    case active
    case background
    case restoring
}
