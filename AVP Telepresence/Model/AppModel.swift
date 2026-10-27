//
//  AppModel.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//

import SwiftUI
import RealityKit
import Foundation
import ARKit

let arSession = ARKitSession()
let worldTracking = WorldTrackingProvider()

struct ViewpointPose: Codable, Equatable {
    var x: Float
    var z: Float
    var yawDegrees: Float
    var floor: Float = 0
}

struct Calibration: Equatable, Codable {
    var poses: [String: ViewpointPose] = [:] // keyed by Viewpoint.id
}

// single source of truth for where things are in the room frame (origin = viewpoint A's floor point)
enum RoomLayout {
    static let tableCenter: SIMD3<Float> = [1.2, 0, -0.4] // TODO: measure real table's center from A's tripod spot
}

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "VideoImmersiveView"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    
    var whiteboardStrokes: [WhiteboardStroke] = []
    
    var calibration = Calibration()
    
    private let key = "calibration"
    
    var mySeat = "a"            // set per headset before joining: "a" = host, "b" = guest
    var isShared = false        // true once SharePlay has configured the group immersive space
    
    var worldFromRoom: simd_float4x4 = matrix_identity_float4x4 // mirrors worldRoot.transform
    var roomOpacity: Float = 1                                  // mirrors teleport fade
    
    func saveCalibration() {
        if let data = try? JSONEncoder().encode(calibration) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    func loadCalibration() {
        if let data = UserDefaults.standard.data(forKey: key),
           let cal = try? JSONDecoder().decode(Calibration.self, from: data) {
            calibration = cal
        }
    }
    func headPosition() -> SIMD3<Float>? {
        guard let d = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return nil }
        let c = d.originFromAnchorTransform.columns.3
        return [c.x, c.y, c.z]
    }

    /// tracking takes a moment after run(); wait for the first real pose
    func waitForHeadPosition() async -> SIMD3<Float> {
        for _ in 0..<40 {
            if let p = headPosition() { return p }
            try? await Task.sleep(for: .milliseconds(50))
        }
        print("⚠️ No device anchor — using fallback head position")
        return [0, 1.5, 0]
    }
    func startTracking() async {
        guard WorldTrackingProvider.isSupported else {
            print("World tracking unsupported (simulator?)"); return
        }
        do {try await arSession.run([worldTracking])}
        catch {print("ARKit failed to start: \(error)")}
    }
    
    var currentViewpointID = "a" // which viewpoint the calibration panel edits
    
    func pose(forID id: String) -> ViewpointPose {
        if let p = calibration.poses[id] { return p }
        let vp = Viewpoint.all.first {$0.id == id } ?? Viewpoint.all[0]
        return ViewpointPose(x: vp.position.x, z: vp.position.z, yawDegrees: vp.yaw * 180 / .pi)
    }
    func printPoses() {
        for vp in Viewpoint.all {
            let p = pose(forID: vp.id)
            print(#".init(id: "\#(vp.id)", videoName: "\#(vp.videoName)", position: [\#(p.x), 0, \#(p.z)], yaw: \#(p.yawDegrees) * .pi / 180),  // floor \#(p.floor)"#)
        }
    }
}
