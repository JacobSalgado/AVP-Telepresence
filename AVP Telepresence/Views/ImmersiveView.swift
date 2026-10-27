//
//  ImmersiveView.swift
//  AVP Telepresence
//
//  Created by Research on 1/27/26.
//

import SwiftUI
import RealityKit
import RealityKitContent
import AVFoundation
import ARKit
import Combine

struct Viewpoint: Identifiable, Equatable {
    let id: String
    let videoName: String
    let position: SIMD3<Float>      // meters from viewPoint A, same axes as tablePosition
    let yaw: Float                  // radians;
    
    // found out this doesn't require exact folder path. Just needs video name
    static let all: [Viewpoint] = [
        .init(id: "a", videoName: "table-view1", position: [0,0,0], yaw: 0), // origin starting point
        .init(id: "b", videoName: "table-view2", position: [4,0,0], yaw: 0), // table view across from the origin start pos
        .init(id: "c", videoName: "sudoku1", position: [0,-1.0,-4.0], yaw: 0), // first sudoku that is the first one to the left of the origin starting point
        .init(id: "d", videoName: "sudoku2", position: [4, 0, -4.0], yaw: 0) // second sudoku board to the right when user first looks left
    ]
    
}

struct ImmersiveView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(SessionManager.self) private var sessionManager

    // Puzzle data
    @StateObject private var puzzleViewModel = PuzzleViewModel()
    @State private var hasLoadedPuzzle = false

    @State private var puzzleAnchor = Entity()
    // Shared across all pieces so their relative transparency draw order is
    // explicit and stable, instead of RealityKit's default per-entity
    // center-distance heuristic (which flickers when pieces' meshes overlap
    // heavily — see makePieceEntity).
    @State private var puzzleSortGroup = ModelSortGroup()
    @State private var interaction = PuzzleInteractionState()

    // Throttle for how often we broadcast live drag positions. 15-20x/sec
    // is plenty smooth without flooding the messenger.
    private let dragBroadcastInterval: TimeInterval = 0.06
    
    // Root Entity data for accurate placement of puzzles and whiteboard
    @State private var worldRoot = Entity()
    @State private var skyBox: ModelEntity?
    @State private var skyPlayer = AVPlayer()
    @State private var currentViewpoint = Viewpoint.all[0]
    @State private var isTraveling = false

    // MARK: - Placement tuning
    // Sudoku/whiteboard: vertical, in front of the user, roughly eye level.
    private let whiteboardPosition: SIMD3<Float> = [0, 2.3, -2.2]

    // JIGSAW TABLE: positioned off to the side so it doesn't overlap the
    // whiteboard, at typical table height.
    private let tableHeight: Float = 0.75
    private let tableRadius: Float = 2.0
    private let tablePosition = RoomLayout.tableCenter // XZ placement; Y is the floor, table sits on top; NEGATIVE values move it left, POSITIVE right
    private let tableThickness: Float = 0.04

    // Reference card: stands upright beside the table (not on top of it,
    // so it doesn't compete with tabletop space where pieces scatter).
    private let referenceCardWidth: Float = 0.6
    private let referenceCardSideMargin: Float = 0.10 // gap from the table's edge
    private let referenceCardLift: Float = 0.05         // gap between table height and the card's bottom edge
     
    @State private var anchorHead: SIMD3<Float> = [0, 1.5, 0]

    var body: some View {
        RealityView { content, attachments in
                // world root entities
                let sky = makeSkyBox(player: skyPlayer)
                skyBox = sky
                content.add(sky)
                content.add(makeAxes(0.5))
                content.add(worldRoot)
                
                // calibration panel goes on content, NOT worldRoot, so it stays put while the room moves
            if let panel = attachments.entity(for: "calibration") {
                panel.position = [0.45, 1.2, -0.8] // slightly right, chest height
                content.add(panel)
            }
            
                if let whiteboard = attachments.entity(for: "whiteboard") {
                    whiteboard.name = "whiteboard"
                    whiteboard.position = whiteboardPosition
                    whiteboard.scale = .one * 1.8
                    worldRoot.addChild(whiteboard)
                }
                worldRoot.addChild(makeTableEntity())
                worldRoot.addChild(makeReferenceCardEntity())
                
                puzzleAnchor.position = [tablePosition.x, tableHeight + 0.002, tablePosition.z]
                worldRoot.addChild(puzzleAnchor)
                
                // room origin
                worldRoot.addChild(makeAxes(0.5))
                
                // each capture's position and facing
                for vp in Viewpoint.all {
                    let a = makeAxes()
                    a.position = [vp.position.x, 0.02, vp.position.z]
                    a.orientation = simd_quatf(angle: vp.yaw, axis: [0,1,0])
                    worldRoot.addChild(a)
                }
                
                /**
                 * @brief This iterates through the 360-degree images list and selects which one to play
                 */
                for vp in Viewpoint.all {
                    let hotspot = makeHotspot(for: vp)
                    interaction.hotspotEntities[vp.id] = hotspot
                    worldRoot.addChild(hotspot)
                }
                
                // ground truth
                let truth = ModelEntity(mesh: .generateSphere(radius: 0.04), materials: [UnlitMaterial(color: .magenta)])
                truth.position = [1.20, 0.75, -2.10]
                worldRoot.addChild(truth)
                
                appModel.loadCalibration()
                await appModel.startTracking()
                anchorHead = await appModel.waitForHeadPosition()
                enterSeatIfShared()
                _ = loadVideo(currentViewpoint.videoName)
                skyPlayer.play()
                refreshView()
            
            if appModel.isShared { sessionManager.takeSeat(appModel.mySeat) }
            
            if let advance = attachments.entity(for: "advance") {
                advance.position = [tablePosition.x, tableHeight + 0.45, tablePosition.z]
                advance.components.set(BillboardComponent())
                advance.isEnabled = false
                worldRoot.addChild(advance)
            }
            
        }
        update: { content, attachments in
            for piece in puzzleViewModel.pieces {
                // Only create an entity for this piece the FIRST time we see
                // it. If one already exists, skip straight to the next piece.
                guard interaction.pieceEntities[piece.id] == nil else { continue }
                let entity = makePieceEntity(for: piece)
                puzzleAnchor.addChild(entity)
                interaction.pieceEntities[piece.id] = entity
            }
            attachments.entity(for: "advance")?.isEnabled = puzzleViewModel.isSolved && appModel.section == .jigsaw
        }
        attachments: {
            Attachment(id: "whiteboard") {
                WhiteboardView()
            }
                Attachment(id: "calibration") {
                    CalibrationPanel()
                }
            Attachment(id: "advance") {
                VStack(spacing: 12) {
                    Text("Puzzle complete!").font(.title2.bold())
                    Text("Continue together to the Sudoku boards.").font(.callout)
                    Button("Continue") { advanceToSudoku() }
                }
                .padding(24)
                .glassBackgroundEffect()
            }
            
        }
        .task {
            guard !hasLoadedPuzzle else { return }
            hasLoadedPuzzle = true
            puzzleViewModel.loadPuzzle()

            // Hand SessionManager a reference so it can push incoming
            // network updates straight into the model.
            sessionManager.puzzleViewModel = puzzleViewModel

            // Whenever a remote participant's drag updates our local model,
            // animate the affected entities smoothly rather than snapping.
            puzzleViewModel.remoteUpdates
                .sink { update in
                    for (id, position) in update.positions {
                        guard let entity = interaction.pieceEntities[id] else { continue }
                        var transform = entity.transform
                        transform.translation = position
                        entity.move(to: transform, relativeTo: entity.parent, duration: 0.08)

                        if let isPlaced = update.isPlaced {
                            // Drag ended (remotely) — restore full opacity
                            // and update grabbability to match placement.
                            setPieceOpacity(id: id, scale: 1.0)
                        } else {
                            // isPlaced == nil means someone else is still
                            // actively dragging this piece right now — show
                            // it semi-transparent here too, mirroring what
                            // they see locally on their own drag.
                            setPieceOpacity(id: id, scale: 0.55)
                        }
                    }
                }
                .store(in: &interaction.cancellables)
        }
        // this handles gesture when interacting with the whiteboard
        // or any puzzle pieces
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged{ value in
                    // move entities
                    if value.entity.name == "whiteboard" {
                        let newPosition = value.convert(value.gestureValue.location3D, from: .local, to: .scene)
                        //value.entity.position = newPosition
                        value.entity.setPosition(newPosition, relativeTo: nil)
                    } else if value.entity.name.hasPrefix("piece_"),
                              let piece = pieceForEntity(value.entity) {
                        let group = puzzleViewModel.piecesInGroup(of: piece)

                        if interaction.dragStartPositions[piece.id] == nil {
                            for member in group {
                                interaction.dragStartPositions[member.id] = member.currentPosition
                                // See through the piece(s) you're holding so
                                // you can judge alignment against whatever's
                                // underneath, instead of it just visually
                                // blocking the piece below.
                                setPieceOpacity(id: member.id, scale: 0.55)
                            }
                        }

                        let translation3D = value.convert(value.translation3D, from: .local, to: value.entity.parent!)

                        for member in group {
                            guard let start = interaction.dragStartPositions[member.id] else { continue }
                            let newPos = start + translation3D
                            member.currentPosition = newPos
                            interaction.pieceEntities[member.id]?.position = newPos
                        }

                        // Throttled broadcast so remote participants see this
                        // drag happening live, without flooding the messenger.
                        let now = Date()
                        if now.timeIntervalSince(interaction.lastDragBroadcast) >= dragBroadcastInterval {
                            interaction.lastDragBroadcast = now
                            sessionManager.sendPuzzleDragUpdate(pieces: group)
                        }
                    }
                }
                .onEnded { value in
                    guard value.entity.name.hasPrefix("piece_"),
                          let piece = pieceForEntity(value.entity) else {return}

                    let group = puzzleViewModel.piecesInGroup(of: piece)
                    for member in group {
                        interaction.dragStartPositions[member.id] = nil
                        setPieceOpacity(id: member.id, scale: 1.0)
                    }

                    puzzleViewModel.handleDragEnded(draggedPiece: piece)
                    let merged = puzzleViewModel.piecesInGroup(of: piece) // includes what is snapped to
                    
                    for member in merged {
                        interaction.pieceEntities[member.id]?.position = member.currentPosition
                    }
                    sessionManager.sendPuzzleDragEnded(pieces: merged)

                    for member in group {
                        interaction.pieceEntities[member.id]?.position = member.currentPosition
                    }

                    // Broadcast the final, settled state (position + placed)
                    // so remote clients land in exactly the same spot.
                    sessionManager.sendPuzzleDragEnded(pieces: group)
                }
        )
        .simultaneousGesture(
            RotateGesture3D()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard value.entity.name == "whiteboard" else {return}
                    let entity = value.entity
                    entity.orientation = simd_quatf(value.rotation) * entity.orientation
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard value.entity.name == "whiteboard" else {return}
                    let entity = value.entity
                    entity.scale = .one * Float(value.magnification)
                }
            )
        .simultaneousGesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard value.entity.name.hasPrefix("hotspot_") else {return}
                    let id = String(value.entity.name.dropFirst("hotspot_".count))
                    guard let vp = Viewpoint.all.first(where: {$0.id == id}) else {return}
                    Task {await travel (to: vp)}
                }
        )
        .onChange(of: appModel.calibration) {
            refreshView(log: false)         // slider moved: re-apply the pose
        }
        .onChange(of: appModel.isShared) {
            // SharePlay can finish configuring after the space is already open
            enterSeatIfShared()
            _ = loadVideo(currentViewpoint.videoName)
            skyPlayer.play()
            refreshView()
        }
        .onChange(of: appModel.ghostTable) {
            worldRoot.findEntity(named: "puzzleTable")?
                .components.set(OpacityComponent(opacity: appModel.ghostTable ? 0.35 : 1))
        }
        .onChange(of: appModel.section) {
            guard let vp = Viewpoint.all.first(where: { $0.id == appModel.mySeat }) else { return }
            Task { await travel(to: vp)}
        }
        .onAppear {appModel.immersiveSpaceState = .open}
        .onDisappear {
            appModel.immersiveSpaceState = .closed
            sessionManager.shouldBeImmersed = false
        }
        
    }

    /// A simple placeholder table: a flat tabletop slab plus four legs,
    /// positioned at `tablePosition` (XZ) with its top surface at
    /// `tableHeight`. Swap the materials for something nicer once you have
    /// real art, or replace this whole function with a loaded USDZ model.
    private func makeTableEntity() -> Entity {
        let table = Entity()
        table.name = "puzzleTable"
        table.position = [tablePosition.x, 0, tablePosition.z] // children are relative to the table center

        let woodMaterial = SimpleMaterial(color: .init(red: 0.85, green: 0.75, blue: 0.60, alpha: 1.0),
                                          roughness: 0.5, isMetallic: false)

        // Tabletop slab, centered so its TOP face sits at tableHeight.
        let topMesh = MeshResource.generateCylinder(height: tableThickness, radius: tableRadius)
        let top = ModelEntity(mesh: topMesh, materials: [woodMaterial])
        top.position = [0, tableHeight - tableThickness / 2, 0]
        table.addChild(top)

        // Four legs running from the underside of the tabletop down to the floor.
        let legHeight = tableHeight - tableThickness
        let legMesh = MeshResource.generateCylinder(height: legHeight, radius: 0.05)
        let pedestal = ModelEntity(mesh: legMesh, materials: [woodMaterial])
        pedestal.position = [0, legHeight / 2, 0]
        table.addChild(pedestal)

        return table
    }

    /// Adjusts how see-through a piece is at runtime. Used to make the
    /// piece(s) currently being dragged (locally or by a remote
    /// participant) partially transparent, so alignment against whatever's
    /// underneath is visible, then restored to full opacity on release.
    /// scale: 1.0 = fully opaque (normal), lower = more see-through.
    ///
    /// Skips the material reassignment entirely if this piece is already
    /// at the requested opacity — during a drag this gets called on every
    /// throttled update (~16x/sec), so without this check we'd be
    /// rebuilding and reassigning an identical material dozens of times
    /// for no visual change.
    private func setPieceOpacity(id: String, scale: Float) {
        guard interaction.currentOpacity[id] != scale else { return }
        guard let entity = interaction.pieceEntities[id],
              var material = entity.model?.materials.first as? UnlitMaterial else { return }
        material.blending = .transparent(opacity: .init(scale: scale))
        entity.model?.materials = [material]
        interaction.currentOpacity[id] = scale
    }

    /// A standing reference card showing the assembled puzzle image, placed
    /// just beside the table (not on its surface) so it doesn't compete
    /// with the tabletop space pieces scatter across. Add the preview
    /// image to your Asset Catalog as an image set named "puzzlePreview".
    private func makeReferenceCardEntity() -> Entity {
        let card = Entity()
        card.name = "referenceCard"

        // Match the card's aspect ratio to the preview image itself so it
        // doesn't look stretched. Falls back to the puzzle board's own
        // aspect if the texture can't be loaded for some reason.
        var aspect: Float = 1.62
        var material = UnlitMaterial()
        
        if let texture = try? TextureResource.load(named: "puzzlePreview") {
            aspect = Float(texture.width) / Float(texture.height)
            material.color = .init(texture: .init(texture))
        }
        material.blending = .opaque // reference image has no transparency to worry about
        let cardHeight = referenceCardWidth / aspect
        
        let image = ModelEntity(mesh: .generatePlane(width: referenceCardWidth, height: cardHeight), materials: [material])
        card.addChild(image)

        // "right of the table" as seen from viewpoint A
            let a = Viewpoint.all[0].position
            let toTable = simd_normalize(SIMD3<Float>(tablePosition.x - a.x, 0, tablePosition.z - a.z))
            let right = simd_normalize(simd_cross(toTable, [0, 1, 0]))

            let offset = tableRadius + referenceCardSideMargin + referenceCardWidth / 2
            card.position = [tablePosition.x + right.x * offset,
                             tableHeight + referenceCardLift + cardHeight / 2,
                             tablePosition.z + right.z * offset]

            // turns to face whoever is looking, so it's readable from both seats
            card.components.set(BillboardComponent())

            return card
    }

    private func makePieceEntity(for piece: PuzzlePiece) -> ModelEntity {
        print("Creating entity for piece \(piece.id)")
        // generatePlane(width:depth:) lies FLAT in the XZ-plane (normal +Y) —
        // this is the correct overload for "resting on a table." The other
        // overload, generatePlane(width:height:), stands upright instead.
        let mesh = MeshResource.generatePlane(width: piece.pieceSize.x, depth: piece.pieceSize.y)

        var material = UnlitMaterial()
        if let texture = try? TextureResource.load(named: piece.imageName) {
            material.color = .init(texture: .init(texture))
        }
        material.blending = .transparent(opacity: .init(scale: 1.0))

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "piece_\(piece.id)"
        entity.position = piece.currentPosition
        // Explicit, stable transparency draw order — same relative
        // ordering as the yBias in PuzzlePiece. This is what actually
        // fixes the angle-dependent flicker: RealityKit's default sort is
        // per-entity center-distance, which is unreliable when pieces'
        // (mostly-transparent) meshes overlap as heavily as these do.
        entity.components.set(ModelSortGroupComponent(group: puzzleSortGroup, order: piece.sortOrder))
        // generatePlane already lies flat (XZ-plane, normal +Y) — that's
        // exactly "resting on a table," so no rotation is applied here.
        entity.components.set(InputTargetComponent())
        entity.generateCollisionShapes(recursive: false)
        return entity
    }

    private func pieceForEntity(_ entity: Entity) -> PuzzlePiece? {
        guard entity.name.hasPrefix("piece_") else { return nil }
        let id = String(entity.name.dropFirst("piece_".count))
        return puzzleViewModel.pieces.first { $0.id == id }
    }
    
    private func makeSkyBox(player: AVPlayer) -> ModelEntity {
        let mesh = MeshResource.generateSphere(radius: 1000)
        let sky = ModelEntity(mesh: mesh, materials: [VideoMaterial(avPlayer: player)])
        sky.scale *= .init(x: -1, y: 1, z: 1)
        return sky
    }
    
    private func loadVideo(_ filename: String) -> AVPlayerItem? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "mp4") else {
            print("Missing video: \(filename)")
            return nil
        }
        let item = AVPlayerItem(url: url)
        skyPlayer.replaceCurrentItem(with: item)   // VideoMaterial keeps following the same player
        return item
    }
    
    // shift the room opposite to the camera so content stays pinned to the real room
    private func applyViewpoint(_ vp: Viewpoint, head: SIMD3<Float>, log: Bool = true) {
        let pose = appModel.pose(forID: vp.id)
        let worldFromHead = Transform(translation: [head.x, appModel.calibration.roomFloor + pose.floor, head.z]).matrix
            let roomFromCapture = Transform(rotation: simd_quatf(angle: pose.yawDegrees * .pi / 180, axis: [0, 1, 0]),
                                            translation: [pose.x, 0, pose.z]).matrix
            worldRoot.transform = Transform(matrix: worldFromHead * roomFromCapture.inverse)
            skyBox?.position = head
            skyBox?.orientation = simd_quatf()
            for (id, hotspot) in interaction.hotspotEntities { hotspot.isEnabled = (id != vp.id) }
    }
    
    /**
     @brief creates teleportation markers which allows users to navigate to different positions in the space
     */
    private func makeHotspot(for vp: Viewpoint) -> Entity {
        let root = Entity()
        root.name = "hotspot_\(vp.id)"
        root.position = [vp.position.x, 0.01, vp.position.z]
        
        var discMat = UnlitMaterial(color: .white)
        discMat.blending = .transparent(opacity: .init(scale: 0.5))
            root.addChild(ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.22),
                                      materials: [discMat]))

            let orb = ModelEntity(mesh: .generateSphere(radius: 0.05),
                                  materials: [UnlitMaterial(color: .cyan)])
            orb.position = [0, 0.25, 0]
            root.addChild(orb)

            root.components.set(InputTargetComponent())
            root.components.set(CollisionComponent(
                shapes: [.generateSphere(radius: 0.3).offsetBy(translation: [0, 0.15, 0])]))
            root.components.set(HoverEffectComponent())
            return root
        }
    private func fade(to target: Float, duration: Double = 0.25) async {
        let steps = 10
        let start = skyBox?.components[OpacityComponent.self]?.opacity ?? 1
        for i in 1...steps {
            let o = start + (target - start) * Float(i) / Float(steps)
            skyBox?.components.set(OpacityComponent(opacity: o))
            worldRoot.components.set(OpacityComponent(opacity: o))
            appModel.roomOpacity = o
            try? await Task.sleep(for: .seconds(duration / Double(steps)))
        }
    }

    
    private func makeAxes (_ len: Float = 0.3) -> Entity {
        let root = Entity()
        let t: Float = 0.01
        for (size, pos, color) in [
            (SIMD3<Float>(len, t, t), SIMD3<Float>(len/2, 0,0), UIColor.red), // +x
            (SIMD3<Float>(t, len, t), SIMD3<Float>(0, len/2, 0), UIColor.green), // +y
            (SIMD3<Float>(t, t, len), SIMD3<Float>(0, 0, -len/2), UIColor.blue) // +y
        ] {
            let e = ModelEntity(mesh: .generateBox(size: size), materials: [UnlitMaterial(color: color)])
            e.position = pos
            root.addChild(e)
        }
        return root
    }
    
    private func enterSeatIfShared() {
        guard appModel.isShared,
              let vp = Viewpoint.all.first(where: { $0.id == appModel.mySeat }) else { return }
        currentViewpoint = vp
    }

    private func refreshView(log: Bool = true) {
        appModel.currentViewpointID = currentViewpoint.id
        if appModel.isShared { applySeat(currentViewpoint, log: log) }
        else { applyViewpoint(currentViewpoint, head: anchorHead, log: log) }
        appModel.worldFromRoom = worldRoot.transform.matrix
    }

    /// SHARED: room is fixed and identical on every device; only the video differs
    private func applySeat(_ vp: Viewpoint, log: Bool) {
        let c = RoomLayout.tableCenter
        worldRoot.transform = Transform(translation: [-c.x, appModel.calibration.roomFloor, -c.z])   // table center lands on the template's .app

        let pose = appModel.pose(forID: vp.id)
        skyBox?.position = .zero   // with a 1000 m sphere, being a meter off-center is a ~0.06° error
        skyBox?.orientation = simd_quatf(angle: pose.yawDegrees * .pi / 180, axis: [0, 1, 0])

        for hotspot in interaction.hotspotEntities.values { hotspot.isEnabled = false }

        // the system needs a moment to move you into your seat
        if log { Task { try? await Task.sleep(for: .seconds(2)); seatLog(vp) } }
    }

    // The key realism check: is your head where the camera was?
    private func seatLog(_ vp: Viewpoint) {
        guard let head = appModel.headPosition() else { print("no head pose yet"); return }
        let h = worldRoot.convert(position: head, from: nil)   // head in room coordinates
        let p = appModel.pose(forID: vp.id)
        let off = simd_distance(SIMD2(h.x, h.z), SIMD2(p.x, p.z))
        print("seat \(vp.id): head (\(h.x), \(h.z)) vs capture (\(p.x), \(p.z)) → off by \(off) m, eye height \(h.y) m")
    }
    
    private func advanceToSudoku() {
        guard appModel.section == .jigsaw else { return }
        print("🧩 puzzle solved → advancing at \(Date())")   // study log
        appModel.section = .sudoku
        sessionManager.send(.advanceSection(StudySection.sudoku.rawValue))
    }
    
    @MainActor
    private func travel(to vp: Viewpoint) async {
        guard !isTraveling, vp.id != currentViewpoint.id else { return }
        isTraveling = true
        defer { isTraveling = false }

        await fade(to: 0)

        let resumeTime = skyPlayer.currentTime()
        if (loadVideo(vp.videoName)) != nil {
            _ = await skyPlayer.seek(to: resumeTime)
            skyPlayer.play()

            currentViewpoint = vp
            if appModel.isShared { sessionManager.takeSeat(vp.id) }
            anchorHead = appModel.headPosition() ?? anchorHead
            refreshView()
        }

        await fade(to: 1)
    }
}

final class PuzzleInteractionState {
    var pieceEntities: [String: ModelEntity] = [:]
    var dragStartPositions: [String: SIMD3<Float>] = [:]
    var lastDragBroadcast: Date = .distantPast
    var cancellables = Set<AnyCancellable>()
    var hotspotEntities: [String: Entity] = [:]
    /// Tracks each piece's last-applied opacity scale so setPieceOpacity
    /// can skip redundant material reassignment when nothing's changing.
    var currentOpacity: [String: Float] = [:]
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
        .environment(SessionManager())
}
