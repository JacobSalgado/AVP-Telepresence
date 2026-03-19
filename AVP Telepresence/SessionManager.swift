//
//  SessionManager.swift
//  AVP Telepresence
//
//  Created by Research on 3/11/26.
//

import GroupActivities
import Observation

@Observable
final class SessionManager{
    
    var sessionState : SessionState = .idle
    var partnerJoined: Bool = false
    
    private var groupSession: GroupSession<CollabActivity>?
    
    enum SessionState {
        case idle           // not started
        case waiting        // activity has started, waiting for partner to join
        case connected      // partner joined the session
        case failed(Error)
    }
    
    // Start the activity
    func startSession() {
        Task {
            let activity = CollabActivity()
            
            switch await activity.prepareForActivation() {
            case .activationPreferred:
                do {
                    _ = try await activity.activate()
                    
                    sessionState = .waiting
                } catch {
                    sessionState = .failed(error)
                }
            case.activationDisabled:
                print("GroupActivities not available on this device")
            case .cancelled:
                sessionState = .idle
            
            @unknown default:
                break;
            }
        }
    }
    
    // arriving session
    func configureSession(_ session: GroupSession<CollabActivity>){
        self.groupSession = session
        
        // watch for partner joining session
        Task {
            for await activeParticipants in session.$activeParticipants.values {
                // more than 1 participant means a partner has joined
                partnerJoined = activeParticipants.count > 1
                if partnerJoined {
                    sessionState = .connected
                }
            }
        }
        
        // join the session
        session.join()
    }
    
    func endSession(){
        groupSession?.leave()
        groupSession = nil
        sessionState = .idle
        partnerJoined = false
    }
}
