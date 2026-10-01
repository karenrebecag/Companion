// Transitional: makes the support modules visible to every file of this
// target so PR 2 adds no import line to ~390 files. PR 3 wrote explicit
// imports in every moved file; the voice files left here still lean on this
// one, so PR 4 deletes it when it moves them.
@_exported import CompanionTestKit
@_exported import CompanionCoreTestSupport
@_exported import CompanionServicesTestSupport
@_exported import CompanionUITestSupport
