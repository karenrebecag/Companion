@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// The welcome's poll probes every second while Screen Recording is on and not
// capturing; the cause belongs in the log once, not once a second.

@Test func repeatFilterLogsAFailureOncePerChange() {
    let filter = RepeatFilter()
    expect(filter.isNew("denied"), "the first failure is logged")
    expect(!filter.isNew("denied"), "the same failure a second later is not")
    expect(filter.isNew("no displays"), "a different cause is logged")
    filter.reset()
    expect(filter.isNew("no displays"), "after a success, the next failure is logged again")
}
