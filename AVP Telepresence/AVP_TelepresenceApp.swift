//
//  AVP_TelepresenceApp.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//

import SwiftUI

@main
struct AVP_TelepresenceApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .background(.black.opacity(0.1))
        }
        
        // Instructions Screen
        WindowGroup (id: "Instructions") {
            InstructionsView()
                .environment(appModel)
                
        }
        
        // Video Player Environment
        WindowGroup (id: "VideoPlayer") {
            InstructionsView()
                .environment(appModel)
                
        }
        
        // 360 DEGREE VIDEO
        ImmersiveSpace(id: "VideoImmersiveView") {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.full), in: .full)
    }
}
