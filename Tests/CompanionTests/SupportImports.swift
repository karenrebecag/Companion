// Transitional: makes the support modules visible to every file of this
// target so PR 2 adds no import line to ~390 files. PR 3 writes explicit
// imports as files move and deletes this one.
@_exported import CompanionTestKit
@_exported import CompanionCoreTestSupport
@_exported import CompanionServicesTestSupport
@_exported import CompanionUITestSupport
