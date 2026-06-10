//
//  HandTrackingManager.swift
//  AVP Telepresence
//
//  Created by Research on 6/9/26.
//
import ARKit
import RealityKit
import Observation

@Observable
class HandTrackingManager {
    
    // callbacks 0 ImmersiveView wires these up
    var onGestureDetected: ((ReactionGesture, SIMD3<Float>) -> Void)?
    
    private let arSession = ARKitSession()
    private let handProvider = HandTrackingProvider()
    
    // cooldown - prevents the same gesture firing 60 times per second
    private var lastGestureTime: [ReactionGesture: Date] = [:]
    private let gestureCooldown: TimeInterval = 1.5
    
    func start() async {
        guard HandTrackingProvider.isSupported else {
            print("Hand tracking not supported on this device")
            return
        }
        do {
            try await arSession.run([handProvider])
            await processHandUpdates()
        } catch {
            print("ARKit session failed: \(error)")
        }
    }
    
    private func processHandUpdates() async {
        for await update in handProvider.anchorUpdates {
            let anchor = update.anchor
            guard anchor.isTracked else { continue }
            checkGestures(anchor: anchor)
        }
    }
    
    private func checkGestures(anchor: HandAnchor) {
        guard let skeleton = anchor.handSkeleton else { return }
        
        // get the key joint positions in world space
        let originTransform = anchor.originFromAnchorTransform
        
        func worldPos(_ joint: HandSkeleton.JointName) -> SIMD3<Float> {
                    let t = skeleton.joint(joint).anchorFromJointTransform
                    return (originTransform * t).columns.3.xyz
                }

                let thumbTip  = worldPos(.thumbTip)
                let indexTip  = worldPos(.indexFingerTip)
                let middleTip = worldPos(.middleFingerTip)
                let ringTip   = worldPos(.ringFingerTip)
                let pinkyTip = worldPos(.littleFingerTip)
                let wrist     = worldPos(.wrist)
        
        // gesture detection
        // thumbs up - thumb till well above wrist, other fingers curled
        let thumbHeight = thumbTip.y - wrist.y
        let indexCurled = distance(indexTip, wrist) < 0.08
        let middleCurled = distance(middleTip, wrist) < 0.08
        
        if thumbHeight > 0.08 && indexCurled && middleCurled {
            fire(.thumbsUp, at: thumbTip)
            return
        }
        
        // peace sign - index + middle extended, others curled
        let indexExtended = distance(indexTip, wrist) > 0.10
        let middleExtended = distance(middleTip, wrist) > 0.10
        let ringCurled = distance(ringTip, wrist) < 0.08
        let littleCurled = distance(pinkyTip, wrist) < 0.08
        
        if indexExtended && middleExtended && ringCurled && littleCurled {
            fire(.peace, at: indexTip)
            return
        }
        
        // pinch - thumb tip and index tip very close together
        let pinchDist = distance(thumbTip, indexTip)
        if pinchDist < 0.02 {
            fire(.pinch, at: thumbTip)
            return
        }
    }
    
    private func fire (_ gesture: ReactionGesture, at position: SIMD3<Float>) {
        let now = Date()
        if let last = lastGestureTime[gesture], now.timeIntervalSince(last) < gestureCooldown {
            return
        }
        lastGestureTime[gesture] = now
        onGestureDetected?(gesture, position)
    }
}

// GESTURE TYPES
enum ReactionGesture: String, Codable, CaseIterable {
    case thumbsUp = "👍"
    case peace    = "✌️"
    case pinch    = "🤌"
    
    var emoji: String { rawValue }
}

// SIMD helper
extension SIMD4 {
    var xyz: SIMD3<Scalar> { SIMD3(x,y,z) }
}
