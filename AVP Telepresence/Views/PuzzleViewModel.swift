import Foundation
import simd
import Combine

@MainActor
final class PuzzleViewModel: ObservableObject {
    @Published var pieces: [PuzzlePiece] = []
    @Published var isSolved: Bool = false

    /// Overall board size in meters. Adjust to taste for how big the
    /// puzzle should appear in the user's space. Aspect ratio is taken
    /// from layout.json automatically.
    let boardWidthMeters: Float = 0.5
    private(set) var boardSizeMeters: SIMD3<Float> = .zero

    private var cancellables = Set<AnyCancellable>()
    
    // "row_col" -> piece
    private var piecesByGridPosition: [String: PuzzlePiece] = [:]
    private var piecesByID: [Int: PuzzlePiece] = [:]
    
    // union-find grouping (which pieces are locked together)
    private var parent: [Int: Int] = [:]
    
    private func find(_ id: Int) -> Int {
        if parent[id] == nil { parent[id] = id }
        if parent[id] != id {parent[id] = find(parent[id]!)}
        return parent[id]!
    }
    
    private func union (_ a: Int, _ b: Int) {
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

        let boardHeight = boardWidthMeters / Float(layout.boardAspect)
        boardSizeMeters = SIMD3<Float>(boardWidthMeters, boardHeight, 0)
        let boardSize2D = SIMD2<Float>(boardWidthMeters, boardHeight)

        var newPieces: [PuzzlePiece] = []
        for pieceData in layout.pieces {
            let scatter = Self.randomScatterPosition(around: boardSize2D)
            let piece = PuzzlePiece(data: pieceData, boardSizeMeters: boardSize2D, scatterPosition: scatter)
            newPieces.append(piece)

            // Watch each piece's placement state so we can detect a full solve.
            piece.$isPlaced
                .sink { [weak self] _ in self?.checkSolved() }
                .store(in: &cancellables)
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

    /// Called by the view after a drag ends. Snaps the piece home if close
    /// enough, otherwise leaves it at the dropped position.
    func handleDragEnded(draggedPiece: PuzzlePiece) {
        let group = piecesInGroup(of: draggedPiece)
        let groupRoot = find(draggedPiece.id)
        
        var best: (member: PuzzlePiece, neighbor: PuzzlePiece, dist: Float)? = nil
        
        for member in group {
            for neighbor in neighbors(of: member) {
                guard find(neighbor.id) != groupRoot else {continue} // same group already
                
                let expectedOffset = member.homeCenter - neighbor.homeCenter
                let expectedPosition = neighbor.currentPosition + expectedOffset
                let dist = simd_distance(SIMD2<Float>(member.currentPosition.x, member.currentPosition.y),
                                         SIMD2<Float>(expectedPosition.x, expectedPosition.y))
                if dist < PuzzlePiece.snapDistance, (best == nil || dist < best!.dist) {
                    best = (member, neighbor, dist)
                }
            }
        }
        if let match = best {
            let expectedOffset = match.member.homeCenter - match.neighbor.homeCenter
            let expectedPosition = match.neighbor.currentPosition + expectedOffset
            let correction = expectedPosition - match.member.currentPosition
            
            for m in group {
                m.currentPosition += correction
                m.isPlaced = true
            }
            union(match.member.id, match.neighbor.id)
        } else {
            for m in group {m.isPlaced = false}
        }
    }

    private func checkSolved() {
        isSolved = !pieces.isEmpty && pieces.allSatisfy { $0.isPlaced }
    }

    /// Scatters pieces in a loose ring around the board so they don't overlap
    /// the board itself at launch. Tune radius/jitter as you like.
    private static func randomScatterPosition(around boardSize: SIMD2<Float>) -> SIMD3<Float> {
        let angle = Float.random(in: 0..<(2 * .pi))
        let radius = (max(boardSize.x, boardSize.y) * 0.9) + Float.random(in: 0...0.15)
        let x = cos(angle) * radius
        let y = sin(angle) * radius
        let z = Float.random(in: 0.02...0.08) // slightly toward the user
        return SIMD3<Float>(x, y, z)
    }
}
