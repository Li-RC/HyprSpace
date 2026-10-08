@testable import AppBundle
import Common
import XCTest

@MainActor
final class MessageDiagnosticsTest: XCTestCase {
    func testValidConfigHasNoMessageAndErrorsRemainVisibleUntilCorrected() async throws {
        setUpWorkspacesForTests()
        let previous = MessageModel.shared.message
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            MessageModel.shared.message = previous
            try? FileManager.default.removeItem(at: directory)
        }
        let invalid = directory.appendingPathComponent("invalid.toml")
        try "[invalid".write(to: invalid, atomically: true, encoding: .utf8)
        let args = ReloadConfigCmdArgs(rawArgs: []).copy(\.dryRun, true)

        let clean = await reloadConfig_nonCancellable(args: args, forceConfigUrl: defaultConfigUrl)
        XCTAssertTrue(clean.isOk)
        XCTAssertNil(MessageModel.shared.message)

        let broken = await reloadConfig_nonCancellable(args: args, forceConfigUrl: invalid)
        XCTAssertFalse(broken.isOk)
        XCTAssertFalse(MessageModel.shared.message?.body.isEmpty ?? true)
        XCTAssertTrue(MessageModel.shared.message?.body.contains(invalid.path) == true)

        let corrected = await reloadConfig_nonCancellable(args: args, forceConfigUrl: defaultConfigUrl)
        XCTAssertTrue(corrected.isOk)
        XCTAssertNil(MessageModel.shared.message)
    }
}
