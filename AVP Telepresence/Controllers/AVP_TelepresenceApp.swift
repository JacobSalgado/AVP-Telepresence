//
//  AVP_TelepresenceApp.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//

import SwiftUI
import GroupActivities

@main
struct AVP_TelepresenceApp: App {

    @State private var appModel = AppModel()
    @State private var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .environment(sessionManager)
                .background(.black.opacity(0.1))
                .task {
                    // loop catches sessions initiated by either user
                    for await session in CollabActivity.sessions() {
                        sessionManager.appModel = appModel
                        sessionManager.configureSession(session)
                    }
                }
        }
        //.windowStyle(.volumetric)
        //.defaultSize(width: 0.5, height: 0.5, depth: 0.5, in: .meters)
        
        /// This opens up the instructions window that can be viewed prior to entering the immersive space
        WindowGroup (id: "Instructions") {
            InstructionsView()
                .environment(appModel)
                
        }
        
        /// This contains the immersiveSpace  for the main scene where the Sudoku and Puzzle Pieces are
        ImmersiveSpace(id: AppModel.immersiveSpaceID) {
            ZStack {
                ImmersiveView()
                TileSudokuView()
            }
            .environment(appModel)
            .environment(sessionManager)
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
