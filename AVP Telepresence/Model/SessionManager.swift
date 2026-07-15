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

    /// Set this once your puzzle view model exists (e.g. from ImmersiveView's
    /// .task, right after puzzleViewModel.loadPuzzle()). Weak to avoid a
    /// retain cycle, since PuzzleViewModel doesn't need to know about this.
    weak var puzzleViewModel: PuzzleViewModel?

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

    // MARK: - Puzzle sync

    /// Call from onChanged, throttled (e.g. ~15-20x/sec, not every frame).
    /// Broadcasts the live positions of every piece in the dragged group so
    /// remote clients see the drag happening smoothly, not just on release.
    func sendPuzzleDragUpdate(pieces: [PuzzlePiece]) {
        let payload = Dictionary(uniqueKeysWithValues:
            pieces.map { ($0.id, CodableVector3($0.currentPosition)) })
        send(.puzzlePieceDragging(groupPositions: payload))
    }

    /// Call once from onEnded. Broadcasts the final, settled state of the
    /// dragged group (including whether it snapped/placed).
    func sendPuzzleDragEnded(pieces: [PuzzlePiece]) {
        let payload = Dictionary(uniqueKeysWithValues:
            pieces.map { ($0.id, CodableVector3($0.currentPosition)) })
        let isPlaced = pieces.first?.isPlaced ?? false
        send(.puzzlePieceDragEnded(groupPositions: payload, isPlaced: isPlaced))
    }

    @MainActor
    private func handle(_ message: SceneMessage, from participant: Participant){
        // apply synced state updates here
        switch message {
        case .objectMoved(let id, let transform):
            // reality kit updates
            _ = id
            _ = transform
        case .enterImmersiveSpace:
            shouldBeImmersed = true
        case .exitImmersiveSpace:
            shouldBeImmersed = false
        case .whiteboardStroke(let stroke):
            appModel?.whiteboardStrokes.append(stroke)
        case .whiteboardCleared:
            appModel?.whiteboardStrokes.removeAll()
        case .puzzlePieceDragging(let groupPositions):
            let positions = groupPositions.mapValues { $0.simd }
            puzzleViewModel?.applyRemoteDragUpdate(groupPositions: positions)
        case .puzzlePieceDragEnded(let groupPositions, let isPlaced):
            let positions = groupPositions.mapValues { $0.simd }
            puzzleViewModel?.applyRemoteDragEnded(groupPositions: positions, isPlaced: isPlaced)
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

/// Lightweight Codable wrapper for SIMD3<Float>, used for puzzle piece
/// positions over the network (much smaller/simpler than a full transform).
struct CodableVector3: Codable {
    var x: Float
    var y: Float
    var z: Float

    var simd: SIMD3<Float> { SIMD3<Float>(x, y, z) }

    init(_ v: SIMD3<Float>) {
        x = v.x; y = v.y; z = v.z
    }
}


// message type
enum SceneMessage: Codable {
    case objectMoved(id: UUID, transform: CodableTransform)
    case enterImmersiveSpace
    case exitImmersiveSpace
    case whiteboardStroke(WhiteboardStroke)
    case whiteboardCleared
    case puzzlePieceDragging(groupPositions: [Int: CodableVector3])
    case puzzlePieceDragEnded(groupPositions: [Int: CodableVector3], isPlaced: Bool)
    
    private enum CodingKeys: String, CodingKey {
        case type, id, transform, cardID, groupID, label, stroke, groupPositions, isPlaced
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .objectMoved(let id, let transform):
            try container.encode("objectMoved", forKey: .type)
            try container.encode(id,            forKey: .id)
            try container.encode(transform,     forKey: .transform)
        case .enterImmersiveSpace:
            try container.encode("enterImmersiveSpace", forKey: .type)
        case .exitImmersiveSpace:
            try container.encode("exitImmersiveSpace", forKey: .type)
        case .whiteboardStroke(let stroke):
            try container.encode("whiteboardStroke", forKey: .type)
            try container.encode(stroke, forKey: .stroke)
        case .whiteboardCleared:
            try container.encode("whiteboardCleared", forKey: .type)
        case .puzzlePieceDragging(let groupPositions):
            try container.encode("puzzlePieceDragging", forKey: .type)
            try container.encode(groupPositions, forKey: .groupPositions)
        case .puzzlePieceDragEnded(let groupPositions, let isPlaced):
            try container.encode("puzzlePieceDragEnded", forKey: .type)
            try container.encode(groupPositions, forKey: .groupPositions)
            try container.encode(isPlaced, forKey: .isPlaced)
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
        case "enterImmersiveSpace":
            self = .enterImmersiveSpace
        case "exitImmersiveSpace":
            self = .exitImmersiveSpace
        case "whiteboardStroke":
            let stroke = try container.decode(WhiteboardStroke.self, forKey: .stroke)
            self = .whiteboardStroke(stroke)
        case "whiteboardCleared":
            self = .whiteboardCleared
        case "puzzlePieceDragging":
            let groupPositions = try container.decode([Int: CodableVector3].self, forKey: .groupPositions)
            self = .puzzlePieceDragging(groupPositions: groupPositions)
        case "puzzlePieceDragEnded":
            let groupPositions = try container.decode([Int: CodableVector3].self, forKey: .groupPositions)
            let isPlaced = try container.decode(Bool.self, forKey: .isPlaced)
            self = .puzzlePieceDragEnded(groupPositions: groupPositions, isPlaced: isPlaced)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown SceneMessage type: \(type)"
            )
        }
    }
}
