import CompanionCore
import Testing

@Test @MainActor func scaffoldTests() {
    expect(!Build.version.isEmpty, "el paquete enlaza y el harness corre")
}
