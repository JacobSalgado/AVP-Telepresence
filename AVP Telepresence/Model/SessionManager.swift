//
//  SessionManager.swift
//  AVP Telepresence
//
//  Created by Research on 3/11/26.
//

import GroupActivities
import Observation
import Combine
import RealityKit
import Foundation

@Observable
class SessionManager {
    var appModel: AppModel?
    var session: GroupSession<CollabActivity>?
    var messenger : GroupSessionMessenger?
    var participants: Set<Participant> = []
    var shouldBeImmersed: Bool = false
    
    var activationState: String = "Idle"
    
    private var subscriptions = Set<AnyCancellable>()
    private var tasks = Set<Task<Void, Never>>()
    
    func configureSession(_ session: GroupSession<CollabActivity>){
        self.session = session
        
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger
        
        Task {
            guard let coordinator = await session.systemCoordinator else {return}
            
            var config = SystemCoordinator.Configuration()
            
            // show personas when immersive space is open
            config.supportsGroupImmersiveSpace = true
            
            // put participants across from each other
            // alt. options: .none, .sidebyside, .surround
            config.spatialTemplatePreference = .sideBySide
            
            coordinator.configuration = config
            
            //
        }
        
        // track all the participants
        session.$activeParticipants
            .sink { [weak self] in self?.participants = $0}
            .store(in: &subscriptions)
        
        // receive messages from other participant
        let receiveTask = Task {
            for await (message, context) in messenger.messages(of: SceneMessage.self) {
                await self.handle(message, from:context.source)
            }
        }
        tasks.insert(receiveTask)
        session.join()
    }
    
    func startSharePlay() {
        Task {
            activationState = "preparing..."
            let activity = CollabActivity()
            
            let prep = await activity.prepareForActivation()
            
            switch prep {
            case .activationPreferred:
                activationState = "activating..."
                do {
                    let result = try await activity.activate()
                    activationState = "activated: \(result)"
                } catch {
                    activationState = "activate() threw: \(error)"
                }
            case .activationDisabled:
                activationState = "Disabled - not eligible right now"
            case .cancelled:
                activationState = "cancelled"
            @unknown default:
                activationState = "unknown case"
                break
            }
        }
    }
    
    func requestImmersion(){
        send(.enterImmersiveSpace)
        shouldBeImmersed = true;
    }
    
    func requestExitImmersion(){
        send(.exitImmersiveSpace)
        shouldBeImmersed = false;
    }
    
    func send(_ message: SceneMessage){
        Task{
            try? await messenger?.send(message)
        }
    }
    
    @MainActor
    private func handle(_ message: SceneMessage, from participant: Participant){
        // apply synced state updates here
        switch message {
        case .objectMoved(let id, let transform):
            // reality kit updates
            appModel?.cards[id]?.transform = transform
        case .cardGrouped(let cardID, let groupID):
            appModel?.cardGroups[groupID, default: []].insert(cardID)
        case .groupLabelled(let groupID, let label):
            appModel?.groupLabels[groupID] = label
        case .enterImmersiveSpace:
            shouldBeImmersed = true
        case .exitImmersiveSpace:
            shouldBeImmersed = false
        case .whiteboardStroke(let stroke):
            appModel?.whiteboardStrokes.append(stroke)
        case .whiteboardCleared:
            appModel?.whiteboardStrokes.removeAll()
        }
    }
}

struct CodableTransform: Codable {
    let matrix: simd_float4x4
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        let cols = [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
        for col in cols {
            try container.encode(col.x)
            try container.encode(col.y)
            try container.encode(col.z)
            try container.encode(col.w)
        }
    }
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let values = try (0..<16).map { _ in try container.decode(Float.self) }
        matrix = simd_float4x4(columns: (
            SIMD4(values[0],  values[1],  values[2],  values[3]),
            SIMD4(values[4],  values[5],  values[6],  values[7]),
            SIMD4(values[8],  values[9],  values[10], values[11]),
            SIMD4(values[12], values[13], values[14], values[15])
        ))
    }
    
    init(_ matrix: simd_float4x4) { self.matrix = matrix }
}


// message type
enum SceneMessage: Codable {
    case objectMoved(id: UUID, transform: CodableTransform)
    case cardGrouped(cardID: UUID, groupID: UUID)
    case groupLabelled(groupID: UUID, label: String)
    case enterImmersiveSpace
    case exitImmersiveSpace
    case whiteboardStroke(WhiteboardStroke)
    case whiteboardCleared
    
    private enum CodingKeys: String, CodingKey {
        case type, id, transform, cardID, groupID, label, stroke
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .objectMoved(let id, let transform):
            try container.encode("objectMoved", forKey: .type)
            try container.encode(id,            forKey: .id)
            try container.encode(transform,     forKey: .transform)
        case .cardGrouped(let cardID, let groupID):
            try container.encode("cardGrouped", forKey: .type)
            try container.encode(cardID,        forKey: .cardID)
            try container.encode(groupID,       forKey: .groupID)
        case .groupLabelled(let groupID, let label):
            try container.encode("groupLabelled", forKey: .type)
            try container.encode(groupID,         forKey: .groupID)
            try container.encode(label,           forKey: .label)
        case .enterImmersiveSpace:
            try container.encode("enterImmersiveSpace", forKey: .type)
        case .exitImmersiveSpace:
            try container.encode("exitImmersiveSpace", forKey: .type)
        case .whiteboardStroke(let stroke):
            try container.encode("whiteboardStroke", forKey: .type)
            try container.encode(stroke, forKey: .stroke)
        case .whiteboardCleared:
            try container.encode("whiteboardCleared", forKey: .type)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "objectMoved":
            let id        = try container.decode(UUID.self,             forKey: .id)
            let transform = try container.decode(CodableTransform.self, forKey: .transform)
            self = .objectMoved(id: id, transform: transform)
        case "cardGrouped":
            let cardID = try container.decode(UUID.self, forKey: .cardID)
            let groupID = try container.decode(UUID.self, forKey: .groupID)
            self = .cardGrouped(cardID: cardID, groupID: groupID)
        case "groupLabelled":
            let groupID = try container.decode(UUID.self, forKey: .groupID)
            let label = try container.decode(String.self, forKey: .label)
            self = .groupLabelled(groupID: groupID, label: label)
        case "enterImmersiveSpace":
            self = .enterImmersiveSpace
        case "exitImmersiveSpace":
            self = .exitImmersiveSpace
        case "whiteboardStroke":
            let stroke = try container.decode(WhiteboardStroke.self, forKey: .stroke)
            self = .whiteboardStroke(stroke)
        case "whiteboardCleared":
            self = .whiteboardCleared
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown SceneMessage type: \(type)"
            )
        }
    }
}
