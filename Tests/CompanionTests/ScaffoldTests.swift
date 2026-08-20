import CompanionCore

@MainActor func scaffoldTests() {
    expect(!Build.version.isEmpty, "el paquete enlaza y el harness corre")
}
