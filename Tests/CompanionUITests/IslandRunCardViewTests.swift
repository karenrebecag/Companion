import AppKit
import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// The run card drawn: a smoke render always, a PNG gallery only on demand.

@MainActor private func sampleJob() -> JobTimeline {
    var job = JobTimeline(goal: "Ordenar las capturas del escritorio")
    let t0 = job.startedAt
    job.steps = [
        JobStepInfo(tool: "Bash", label: "Bash: ls ~/Desktop", done: true, id: "a", startedAt: t0,
                    finishedAt: t0.addingTimeInterval(12)),
        JobStepInfo(tool: "Read", label: "Read: inventario.md", done: true, failed: true,
                    id: "b", startedAt: t0.addingTimeInterval(12), finishedAt: t0.addingTimeInterval(77)),
        JobStepInfo(tool: "Write", label: "Write: plan.md", id: "c", startedAt: t0.addingTimeInterval(77)),
    ]
    return job
}

@Test @MainActor func runCardRendersDoneFailedAndLiveRows() throws {
    let renderer = ImageRenderer(content: IslandRunCard(job: sampleJob())
        .frame(width: IslandGrid.openColumn)
        .environment(\.colorScheme, .dark))
    let image = try #require(renderer.nsImage)
    #expect(image.size.width == IslandGrid.openColumn)
    #expect(image.size.height > 0)
}

@Test @MainActor func runCardSnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
        let framed = IslandRunCard(job: sampleJob())
            .frame(width: IslandGrid.openColumn)
            .environment(\.colorScheme, scheme)
            .padding(40)
            .background(scheme == .dark ? Color.black : Color.white)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let tiff = try #require(renderer.nsImage?.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: out.appendingPathComponent("runcard-\(scheme == .dark ? "dark" : "light").png"))
    }
}

@MainActor private func jobWith(steps count: Int) -> JobTimeline {
    var job = JobTimeline(goal: "Tarea larga")
    let t0 = job.startedAt
    job.steps = (0..<count).map {
        JobStepInfo(tool: "Bash", label: "Bash: paso \($0)", done: $0 < count - 1, id: "s\($0)",
                    startedAt: t0, finishedAt: t0.addingTimeInterval(1))
    }
    return job
}

@MainActor private func height<V: View>(_ view: V) throws -> CGFloat {
    try #require(ImageRenderer(content: view.frame(width: IslandGrid.openColumn).environment(\.colorScheme, .dark)).nsImage).size.height
}

@Test @MainActor func moreStepsMakeATallerCard() throws {
    let one = try height(IslandRunCard(job: jobWith(steps: 1)))
    let nine = try height(IslandRunCard(job: jobWith(steps: 9)))
    #expect(nine > one)
}

@Test @MainActor func finishedRowsAreTheSameAtAnyTime() {
    let finished = Array(sampleJob().steps.prefix(2))
    let a = finished[0].startedAt.addingTimeInterval(100)
    let b = finished[0].startedAt.addingTimeInterval(5000)
    #expect(RunCardModel.rows(steps: finished, now: a) == RunCardModel.rows(steps: finished, now: b))
}

@Test @MainActor func aLiveRowChangesItsDurationWithTime() throws {
    let steps = [sampleJob().steps[2]]
    let early = RunCardModel.rows(steps: steps, now: steps[0].startedAt.addingTimeInterval(2))
    let late = RunCardModel.rows(steps: steps, now: steps[0].startedAt.addingTimeInterval(70))
    #expect(early[0].duration != late[0].duration)
}
