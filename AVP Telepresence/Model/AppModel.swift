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

struct BoardPlacement: Codable, Equatable {
    var x: Float = 1
    var y: Float = 2.1
    var z: Float = -1.2
    var yawDegrees: Float = 0
}

struct Calibration: Equatable, Codable {
    var poses: [String: ViewpointPose] = [:] // keyed by Viewpoint.id
    var roomFloor: Float = 0                 // global: lowers/raises ALL room content
    var sudokuBoard = BoardPlacement()      // sticky-note board, room coordinates
}

extension Calibration {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        poses       = try c.decodeIfPresent([String: ViewpointPose].self, forKey: .poses) ?? [:]
        roomFloor   = try c.decodeIfPresent(Float.self, forKey: .roomFloor) ?? 0
        sudokuBoard = try c.decodeIfPresent(BoardPlacement.self, forKey: .sudokuBoard) ?? BoardPlacement()
    }
}

// single source of truth for where things are in the room frame (origin = viewpoint A's floor point)
enum RoomLayout {
    static let tableCenter: SIMD3<Float> = [1.9, -1.0, 0] // TODO: measure real table's center from A's tripod spot
    static let sudokuArea: SIMD3<Float> = [0.5, 0, -2.2]
}

enum StudyRole: String { case host, guest }

enum StudySection: String, Codable {
    case jigsaw, sudoku
    func seat(for role: StudyRole) -> String {
        switch self {
        case .jigsaw: return role == .host ? "a" : "b"
        case .sudoku: return role == .host ? "c" : "d"
        }
    }
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
    
    var studyRole: StudyRole = .host
    var section: StudySection = .jigsaw
    var mySeat: String { section.seat(for: studyRole) }
    
    var isShared = false        // true once SharePlay has configured the group immersive space
    
    var worldFromRoom: simd_float4x4 = matrix_identity_float4x4 // mirrors worldRoot.transform
    var roomOpacity: Float = 1                                  // mirrors teleport fade
    
    var ghostTable = false
    
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
