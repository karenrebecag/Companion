import CompanionCore
@testable import CompanionServices
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// A mic that moved to another input built a new engine. The realtime player
// was attached to the old one at open, so without a re-attach the agent goes
// mute for the rest of the session.
