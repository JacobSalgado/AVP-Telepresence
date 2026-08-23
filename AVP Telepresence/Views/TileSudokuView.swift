//
//  TileSudokuView.swift
//  AVP Telepresence
//
//  Created by Research on 8/6/26.
//

import SwiftUI
import RealityKit
import Combine

struct TileSudokuView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionManager.self) private var sessionManager

    @StateObject private var model = TileSudokuModel()
    @State private var hasSetup = false

    // Root anchors
    @State private var boardRoot = Entity()   // board plane + grid + clues + placed tiles + highlight
    @State private var trayRoot = Entity()    // the 1-9 source tiles

    @State private var interaction = TileInteractionState()

    // MARK: Placement in the immersive space
    // Placed to the LEFT of the drawing whiteboard (which is at x=0),
    // so both boards are visible side by side. Adjust freely.
    private let boardPosition: SIMD3<Float> = [1.0, 1.3, -1.7]

    // MARK: Visual constants
    private let tileDepth: Float = 0.006
    private var boardSize: Float { model.boardSize }
    private var cellSize: Float { model.cellSize }
    private var tileSize: Float { cellSize * 0.82 }   // slightly smaller than a cell
    private let tileZLift: Float = 0.012              // how far tiles sit in front of the board face
    private let trayGap: Float = 0.10                 // gap below the board where the tray sits

    var body: some View {
        RealityView { content in
            boardRoot.position = boardPosition
            content.add(boardRoot)

            buildBoard()
            buildTray()
            buildHighlight()
        }
        update: { _ in
            // Reconcile placed-tile entities against the model (covers both
            // local edits and remote updates funneled through the model).
            reconcilePlacedTiles()
        }
        .task {
            guard !hasSetup else { return }
            hasSetup = true
            sessionManager.tileSudokuModel = model

            model.remoteUpdates
                .sink { _ in
                    // update: closure handles the actual entity reconcile;
                    // this just guarantees a SwiftUI/RealityView tick.
                    interaction.remoteTick &+= 1
                }
                .store(in: &interaction.cancellables)
        }
        .gesture(dragGesture)
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard value.entity.name.hasPrefix("tile_") else { return }

                // First movement this drag: decide what we're carrying.
                if interaction.carried == nil {
                    beginDrag(on: value.entity)
                }
                guard let carried = interaction.carried else { return }

                // Move the carried entity to the fingertip, projected onto
                // the board's plane at the tile's lift depth.
                let scenePoint = value.convert(value.gestureValue.location3D,
                                               from: .local, to: .scene)
                carried.setPosition(scenePoint, relativeTo: nil)

                // Where is that on the board, in board-local XY?
                let local = boardRoot.convert(position: scenePoint, from: nil)
                let target = model.nearestEditableCell(toLocal: SIMD2(local.x, local.y))
                updateHighlight(target)
                interaction.pendingCell = target
            }
            .onEnded { value in
                guard let carried = interaction.carried else { return }
                defer { endDragCleanup() }

                if let cell = interaction.pendingCell {
                    commitPlacement(value: interaction.carriedValue,
                                    row: cell.row, col: cell.col)
                }
                // Whether placed or not, the transient carried entity goes
                // away — placed cells are re-rendered by reconcilePlacedTiles,
                // and an invalid drop just vanishes.
                carried.removeFromParent()
            }
    }

    /// Decide what the user is picking up on first drag movement.
    private func beginDrag(on entity: Entity) {
        if entity.name.hasPrefix("tile_tray_") {
            // Grabbing a tray tile: spawn a fresh carried copy; tray stays.
            let value = trayValue(from: entity)
            interaction.carriedValue = value
            let carried = makeTileEntity(value: value, name: "tile_carried")
            // Start at the tray tile's current world position.
            carried.setPosition(entity.position(relativeTo: nil), relativeTo: nil)
            boardRoot.parent?.addChild(carried) // add to scene root so world-space moves are simple
            interaction.carried = carried
        } else if entity.name.hasPrefix("tile_placed_") {
            // Grabbing a placed tile: lift it OUT of its cell.
            guard let (row, col) = placedCell(from: entity) else { return }
            let value = model.placedValue(row: row, col: col) ?? 0
            model.clear(row: row, col: col)
            broadcast()
            interaction.carriedValue = value
            entity.removeFromParent()   // remove the in-cell entity
            let carried = makeTileEntity(value: value, name: "tile_carried")
            carried.setPosition(entity.position(relativeTo: nil), relativeTo: nil)
            boardRoot.parent?.addChild(carried)
            interaction.carried = carried
        }
    }

    private func commitPlacement(value: Int, row: Int, col: Int) {
        model.place(value: value, row: row, col: col)  // displaced tile removed by reconcile
        broadcast()
    }

    private func endDragCleanup() {
        interaction.carried = nil
        interaction.carriedValue = 0
        interaction.pendingCell = nil
        setHighlightVisible(false)
    }

    private func broadcast() {
        sessionManager.sendTileSudokuUpdate(placed: model.snapshot)
    }

    // MARK: - Entity construction

    private func buildBoard() {
        // Board backing plane (white, vertical, facing +Z).
        let mesh = MeshResource.generatePlane(width: boardSize, height: boardSize)
        var mat = UnlitMaterial(color: .init(white: 0.97, alpha: 1.0))
        mat.blending = .opaque
        let plane = ModelEntity(mesh: mesh, materials: [mat])
        plane.name = "tileBoardBacking"
        boardRoot.addChild(plane)

        // Grid lines drawn as thin dark boxes just in front of the plane.
        addGridLines(to: boardRoot)

        // Fixed clues, rendered as text-on-plane tiles that are NOT grabbable.
        for row in 0..<9 {
            for col in 0..<9 where model.isClue[row][col] {
                let value = model.clueValue(row: row, col: col)
                let clue = makeTileEntity(value: value, name: "tile_clue_\(row)_\(col)",
                                          isClue: true)
                let c = model.cellCenter(row: row, col: col)
                clue.position = [c.x, c.y, tileZLift * 0.5]
                clue.components.remove(InputTargetComponent.self) // not grabbable
                boardRoot.addChild(clue)
            }
        }
    }

    private func addGridLines(to parent: Entity) {
        let half = boardSize / 2
        let thin: Float = 0.0015
        let thick: Float = 0.004
        let dark = UnlitMaterial(color: .init(white: 0.1, alpha: 1.0))

        for i in 0...9 {
            let isBold = (i % 3 == 0)
            let w = isBold ? thick : thin
            let offset = -half + cellSize * Float(i)

            // vertical line
            let vMesh = MeshResource.generateBox(size: [w, boardSize, 0.001])
            let v = ModelEntity(mesh: vMesh, materials: [dark])
            v.position = [offset, 0, 0.0008]
            parent.addChild(v)

            // horizontal line
            let hMesh = MeshResource.generateBox(size: [boardSize, w, 0.001])
            let h = ModelEntity(mesh: hMesh, materials: [dark])
            h.position = [0, offset, 0.0008]
            parent.addChild(h)
        }
    }

    private func buildTray() {
        // A row of tiles 1...9 beneath the board. These are the "sources":
        // grabbing one spawns a carried copy and stays put itself.
        trayRoot.position = [0, -(boardSize / 2) - trayGap, tileZLift]
        boardRoot.addChild(trayRoot)

        let spacing = cellSize * 1.05
        let startX = -spacing * 4  // center the 9 tiles around x=0

        for value in 1...9 {
            let tile = makeTileEntity(value: value, name: "tile_tray_\(value)")
            tile.position = [startX + spacing * Float(value - 1), 0, 0]
            trayRoot.addChild(tile)
        }
    }

    private func buildHighlight() {
        // A green square that appears over the cell a carried tile would
        // land in. Hidden until a valid target exists.
        let mesh = MeshResource.generatePlane(width: cellSize, height: cellSize)
        var mat = UnlitMaterial(color: .init(red: 0.2, green: 0.85, blue: 0.3, alpha: 0.45))
        mat.blending = .transparent(opacity: .init(scale: 0.45))
        let hl = ModelEntity(mesh: mesh, materials: [mat])
        hl.name = "tileHighlight"
        hl.isEnabled = false
        boardRoot.addChild(hl)
        interaction.highlight = hl
    }

    /// Builds a number tile: a small rounded-ish plane with the digit on it.
    private func makeTileEntity(value: Int, name: String, isClue: Bool = false) -> ModelEntity {
        let mesh = MeshResource.generateBox(size: [tileSize, tileSize, tileDepth],
                                            cornerRadius: tileSize * 0.12)
        let faceColor: UIColor = isClue
            ? .init(white: 0.9, alpha: 1.0)       // clues look "printed" / muted
            : .init(red: 0.99, green: 0.93, blue: 0.55, alpha: 1.0) // sticky-note yellow
        var mat = UnlitMaterial(color: faceColor)
        mat.blending = .opaque

        let tile = ModelEntity(mesh: mesh, materials: [mat])
        tile.name = name

        // Digit as a 3D text entity on the front face.
        let textMesh = MeshResource.generateText(
            "\(value)",
            extrusionDepth: 0.001,
            font: .systemFont(ofSize: CGFloat(tileSize * 0.6), weight: .bold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let textMat = UnlitMaterial(color: isClue ? .darkGray : .black)
        let text = ModelEntity(mesh: textMesh, materials: [textMat])
        // generateText anchors at the text's baseline/left; recenter it.
        let bounds = text.model?.mesh.bounds ?? .init()
        text.position = [-bounds.center.x, -bounds.center.y, tileDepth / 2 + 0.0005]
        tile.addChild(text)

        if !isClue {
            tile.components.set(InputTargetComponent())
            tile.generateCollisionShapes(recursive: false)
        }
        return tile
    }

    // MARK: - Highlight

    private func updateHighlight(_ target: (row: Int, col: Int)?) {
        guard let hl = interaction.highlight else { return }
        if let t = target {
            let c = model.cellCenter(row: t.row, col: t.col)
            hl.position = [c.x, c.y, tileZLift * 0.4]
            hl.isEnabled = true
        } else {
            hl.isEnabled = false
        }
    }

    private func setHighlightVisible(_ visible: Bool) {
        interaction.highlight?.isEnabled = visible
    }

    // MARK: - Reconcile placed tiles against the model

    /// Ensures exactly one entity exists per placed (row,col), matching the
    /// model. Removes stale ones, adds missing ones, fixes changed values.
    /// This is what makes both local displacement and remote updates show up.
    private func reconcilePlacedTiles() {
        // Remove entities whose cell is no longer occupied or whose value changed.
        for (key, entity) in interaction.placedEntities {
            let parts = key.split(separator: "_").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let (row, col) = (parts[0], parts[1])
            let modelValue = model.placedValue(row: row, col: col)
            if modelValue == nil || modelValue != interaction.placedValues[key] {
                entity.removeFromParent()
                interaction.placedEntities[key] = nil
                interaction.placedValues[key] = nil
            }
        }
        // Add entities for any placed cell that doesn't have one.
        for (key, value) in model.snapshot {
            guard interaction.placedEntities[key] == nil else { continue }
            let parts = key.split(separator: "_").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let (row, col) = (parts[0], parts[1])
            let tile = makeTileEntity(value: value, name: "tile_placed_\(row)_\(col)")
            let c = model.cellCenter(row: row, col: col)
            tile.position = [c.x, c.y, tileZLift]
            boardRoot.addChild(tile)
            interaction.placedEntities[key] = tile
            interaction.placedValues[key] = value
        }
    }

    // MARK: - Name parsing helpers

    private func trayValue(from entity: Entity) -> Int {
        Int(entity.name.dropFirst("tile_tray_".count)) ?? 0
    }

    private func placedCell(from entity: Entity) -> (row: Int, col: Int)? {
        let suffix = entity.name.dropFirst("tile_placed_".count)
        let parts = suffix.split(separator: "_").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
}

/// Per-view transient interaction state for the tile board.
final class TileInteractionState {
    var carried: Entity?
    var carriedValue: Int = 0
    var pendingCell: (row: Int, col: Int)?
    var highlight: ModelEntity?

    /// "row_col" -> the entity currently rendering that placed tile.
    var placedEntities: [String: ModelEntity] = [:]
    var placedValues: [String: Int] = [:]

    var remoteTick: UInt64 = 0
    var cancellables = Set<AnyCancellable>()
}
