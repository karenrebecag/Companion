import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func attachmentSerializationTests() {
}

private func fakeResolve(_ ref: AttachmentRef) -> AttachmentPayload? {
    switch AttachmentPolicy.delivery(for: ref) {
    case .imageDataURL: return .imageDataURL("data:image/png;base64,abc")
    case .inlineText: return .text("hola archivo")
    case .pathOnly: return .path(ref.path)
    }
}

private func json(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: s.data(using: .utf8)!)) as? [String: Any] ?? [:]
}
