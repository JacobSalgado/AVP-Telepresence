import Foundation
import simd
import Combine

/// Emitted whenever a remote participant's drag updates this client's
/// puzzle state, so the view layer can animate the affected entities
/// smoothly instead of teleporting them.
struct RemotePuzzleUpdate {
    let positions: [String: SIMD3<Float>]
    /// nil while the remote user is still mid-drag; set to true/false once
    /// they release (whether it snapped or not).
    let isPlaced: Bool?
}

@MainActor
final class PuzzleViewModel: ObservableObject {
    @Published var pieces: [PuzzlePiece] = []
    @Published var isSolved: Bool = false
    
    private(set) var tilesX = 0
    private(set) var tilesY = 0

    private func xzDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        simd_distance(SIMD2(a.x, a.z), SIMD2(b.x, b.z))
    }
    
    private static let cornerClearance: Float = 0.03

    private var rowRange = 0...0
    private var colRange = 0...0

    private func isCorner(_ p: PuzzlePiece) -> Bool {
        (p.data.row == rowRange.lowerBound || p.data.row == rowRange.upperBound) &&
        (p.data.col == colRange.lowerBound || p.data.col == colRange.upperBound)
    }

    /// Sitting on its home spot inside the corner frame.
    func isAnchored(_ p: PuzzlePiece) -> Bool {
        xzDistance(p.currentPosition, p.homeCenter) < 0.001
    }

    /// Anchored pieces are aligned with every other anchored piece.
    /// Join any that touch so they move and sync as one group.
    private func joinAnchoredNeighbors(of piece: PuzzlePiece) {
        for member in piecesInGroup(of: piece) where isAnchored(member) {
            for neighbor in neighbors(of: member) where isAnchored(neighbor) {
                union(member.id, neighbor.id)
            }
        }
    }

    /// Overall board size in meters. Adjust to taste for how big the
    /// puzzle should appear on the table. Aspect ratio is taken from
    /// layout.json's puzzle.width/height automatically.
    let boardWidthMeters: Float = 2.0
    private(set) var boardSizeMeters: SIMD3<Float> = .zero

    /// Fires on every remote-applied update. ImmersiveView subscribes to
    /// this to animate the corresponding RealityKit entities.
    let remoteUpdates = PassthroughSubject<RemotePuzzleUpdate, Never>()

    private var cancellables = Set<AnyCancellable>()

    // "row_col" -> piece
    private var piecesByGridPosition: [String: PuzzlePiece] = [:]
    private var piecesByID: [String: PuzzlePiece] = [:]

    // union-find grouping (which pieces are locked together)
    private var parent: [String: String] = [:]

    private func find(_ id: String) -> String {
        if parent[id] == nil { parent[id] = id }
        if parent[id] != id { parent[id] = find(parent[id]!) }
        return parent[id]!
    }

    private func union(_ a: String, _ b: String) {
        let rootA = find(a), rootB = find(b)
        guard rootA != rootB else { return }
        parent[rootA] = rootB
    }

    // every piece currently locked together with 'piece', including itself
    func piecesInGroup(of piece: PuzzlePiece) -> [PuzzlePiece] {
        let root = find(piece.id)
        return pieces.filter { find($0.id) == root }
    }
    
    

    /// Loads layout.json from the app bundle (add it to your asset/resource
    /// folder with "Copy Bundle Resources" build phase membership).
    func loadPuzzle(layoutResourceName: String = "layout") {
        guard let url = Bundle.main.url(forResource: layoutResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let layout = try? JSONDecoder().decode(PuzzleLayout.self, from: data) else {
            assertionFailure("Could not load \(layoutResourceName).json from bundle")
            return
        }

        let aspect = layout.puzzle.width / layout.puzzle.height
        let boardDepth = boardWidthMeters / Float(aspect)
        boardSizeMeters = SIMD3<Float>(boardWidthMeters, boardDepth, 0)
        let boardSize2D = SIMD2<Float>(boardWidthMeters, boardDepth)
        
        let rows = layout.pieces.map(\.row), cols = layout.pieces.map(\.col)
        rowRange = rows.min()!...rows.max()!
        colRange = cols.min()!...cols.max()!

        var newPieces: [PuzzlePiece] = []
        for pieceData in layout.pieces {
            let piece = PuzzlePiece(data: pieceData, puzzleDimensions: layout.puzzle,
                                    boardSizeMeters: boardSize2D, scatterPosition: .zero)
            newPieces.append(piece)
            piece.$isPlaced
                .sink { [weak self] _ in self?.checkSolved() }
                .store(in: &cancellables)
        }

        let corners = newPieces.filter { isCorner($0) }

        for p in newPieces {
            if isCorner(p) {
                p.currentPosition = p.homeCenter
                p.isPlaced = true
            }
        }
        pieces = newPieces
        piecesByGridPosition = Dictionary(uniqueKeysWithValues:
                                            newPieces.map { ("\($0.data.row)_\($0.data.col)", $0)})
        piecesByID = Dictionary(uniqueKeysWithValues: newPieces.map{($0.id, $0)})
    }

    // the up to 4 grid-adjacent pieces (no diagonals) for a given piece
    private func neighbors(of piece: PuzzlePiece) -> [PuzzlePiece] {
        let row = piece.data.row, col = piece.data.col
        let keys = ["\(row-1)_\(col)", "\(row+1)_\(col)", "\(row)_\(col-1)", "\(row)_\(col+1)"]
        return keys.compactMap {piecesByGridPosition[$0]}
    }

    /// Called by the view after a LOCAL drag ends. Snaps the piece's whole
    /// group onto a matching neighbor's group if close enough on the table
    /// plane (X/Z — Y is ignored since it's just the small lift-above-table
    /// height and shouldn't block a valid snap).
    func handleDragEnded(draggedPiece: PuzzlePiece) {
        let group = piecesInGroup(of: draggedPiece)
        let groupRoot = find(draggedPiece.id)

        // Closest valid snap wins, whether it's a corner marker or a neighbor.
        var best: (correction: SIMD3<Float>, neighbor: PuzzlePiece?, dist: Float)? = nil

        // 1. Corner pieces snap to their marker (= their home spot)
        for member in group where isCorner(member) {
            let dist = xzDistance(member.currentPosition, member.homeCenter)
            if dist < PuzzlePiece.cornerSnapDistance, (best == nil || dist < best!.dist) {
                best = (member.homeCenter - member.currentPosition, nil, dist)
            }
        }

        // 2. Any piece snaps to a matching neighbor (same logic as before)
        for member in group {
            for neighbor in neighbors(of: member) {
                guard find(neighbor.id) != groupRoot else { continue }
                let expected = neighbor.currentPosition + (member.homeCenter - neighbor.homeCenter)
                let dist = xzDistance(member.currentPosition, expected)
                if dist < PuzzlePiece.snapDistance, (best == nil || dist < best!.dist) {
                    best = (expected - member.currentPosition, neighbor, dist)
                }
            }
        }

        if let match = best {
            for m in group {
                m.currentPosition += match.correction
                m.isPlaced = true
            }
            if let neighbor = match.neighbor { union(draggedPiece.id, neighbor.id) }
            joinAnchoredNeighbors(of: draggedPiece)
        } else {
            for m in group { m.isPlaced = false }
        }
        checkSolved()
    }

    // MARK: - Remote sync

    /// Applies a live (still-dragging) position update from a remote
    /// participant. Does not touch isPlaced — that's only decided on
    /// drag-end.
    func applyRemoteDragUpdate(groupPositions: [String: SIMD3<Float>]) {
        for (id, pos) in groupPositions {
            piecesByID[id]?.currentPosition = pos
        }
        remoteUpdates.send(RemotePuzzleUpdate(positions: groupPositions, isPlaced: nil))
    }

    /// Applies the final, settled state from a remote participant's
    /// completed drag, and keeps this client's union-find groups
    /// consistent with theirs (merging every piece in the payload into one
    /// group, mirroring whatever merge happened on their end).
    func applyRemoteDragEnded(groupPositions: [String: SIMD3<Float>], isPlaced: Bool) {
        for (id, pos) in groupPositions {
            piecesByID[id]?.currentPosition = pos
            piecesByID[id]?.isPlaced = isPlaced
        }
        let ids = Array(groupPositions.keys)
        if let first = ids.first {
            for other in ids.dropFirst() {
                union(first, other)
            }
        }
        remoteUpdates.send(RemotePuzzleUpdate(positions: groupPositions, isPlaced: isPlaced))
        checkSolved()
    }

    private func checkSolved() {
        guard let first = pieces.first else { isSolved = false; return }
        let root = find(first.id)
        let solved = pieces.allSatisfy { find($0.id) == root }
        if solved != isSolved { isSolved = solved }
    }

    /// Scatters pieces in a loose ring around the board, on the table
    /// plane (X/Z), with a small random lift in Y so scattered pieces
    /// don't visually clip through the tabletop or each other.
    private static func randomScatterPosition(around boardSize: SIMD2<Float>) -> SIMD3<Float> {
        let angle = Float.random(in: 0..<(2 * .pi))
        let radius = (max(boardSize.x, boardSize.y) * 0.6) + Float.random(in: 0...0.08)
        let x = cos(angle) * radius
        let z = sin(angle) * radius
        let y = Float.random(in: 0.005...0.02)
        return SIMD3<Float>(x, y, z)
    }

    /// True if a piece placed at `center` would overlap `other` where it sits in the frame.
    private static func overlaps(_ center: SIMD3<Float>, size: SIMD2<Float>, other: PuzzlePiece) -> Bool {
        abs(center.x - other.homeCenter.x) < (size.x + other.pieceSize.x) / 2 + cornerClearance &&
        abs(center.z - other.homeCenter.z) < (size.y + other.pieceSize.y) / 2 + cornerClearance
    }

    private static func scatterPosition(for piece: PuzzlePiece, board: SIMD2<Float>,
                                        avoiding corners: [PuzzlePiece]) -> SIMD3<Float> {
        var candidate = randomScatterPosition(around: board)
        for _ in 0..<50 {
            if !corners.contains(where: { overlaps(candidate, size: piece.pieceSize, other: $0) }) { break }
            candidate = randomScatterPosition(around: board)
        }
        return candidate
    }
}
