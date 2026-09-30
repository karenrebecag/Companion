public enum Build: Sendable {
    /// Single source of truth: `scripts/bundle.sh` reads it for the plist and
    /// `UpdateChecker` compares it against the latest GitHub release. It is
    /// bumped as part of closing a release, never on its own.
    public static let version = "0.10.0"
}
