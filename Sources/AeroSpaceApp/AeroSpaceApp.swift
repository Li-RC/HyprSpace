import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@main
struct AeroSpaceApp: App {
    @NSApplicationDelegateAdaptor(WorkspaceStatusAppDelegate.self) var appDelegate
    @StateObject var messageModel = MessageModel.shared
    @Environment(\.openWindow) var openWindow: OpenWindowAction

    init() {
        initAppBundle()
    }

    var body: some Scene {
        getMessageWindow(messageModel: messageModel)
            .onChange(of: messageModel.message) { message in
                if message != nil {
                    openWindow(id: messageWindowId)
                }
            }
    }
}
