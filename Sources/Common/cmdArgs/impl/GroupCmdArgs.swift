public struct GroupCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .group,
        help: group_help_generated,
        flags: ["--window-id": windowIdSubArgParser()],
        posArgs: [newMandatoryPosArgParser(\.action, { .init(parseEnum($0.arg, Action.self), advanceBy: 1) }, placeholder: "<action>")],
    )
    public var action: Lateinit<Action> = .uninitialized
    public enum Action: String, CaseIterable, Sendable {
        case toggle, next, prev, remove
        case joinLeft = "join-left", joinDown = "join-down", joinUp = "join-up", joinRight = "join-right"
    }
}
