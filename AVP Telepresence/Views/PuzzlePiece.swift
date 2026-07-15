import Foundation
import simd

/// One entry from layout.json, decoded directly.
struct PuzzlePieceData: Codable {
    let id: Int
    let row: Int
    let col: Int
    let file: String
    let boardX: Int
    let boardY: Int
    let width: Int
    let height: Int
    let homeCenterNormX: Double
    let homeCenterNormY: Double
    let widthNorm: Double
    let heightNorm: Double
}

struct PuzzleGrid: Codable {
    let cols: Int
    let rows: Int
}

struct PuzzleLayout: Codable {
    let grid: PuzzleGrid
    let boardWidthPx: Int
    let boardHeightPx: Int
    let boardAspect: Double
    let pieces: [PuzzlePieceData]
}

/// Runtime state for a piece, wrapping the static layout data.
final class PuzzlePiece: Identifiable, ObservableObject {
    let id: Int
    let data: PuzzlePieceData
    let imageName: String

    /// Home position in board-local space, in meters, measured relative to
    /// the puzzleAnchor. The board lies FLAT on a table: X is left/right,
    /// Z is near/far across the table, and Y is a small constant lift
    /// above the table surface (to avoid z-fighting with the tabletop).
    let homeCenter: SIMD3<Float>
    let pieceSize: SIMD2<Float> // width (X), depth (Z) in meters

    /// Current live position, mutated as the user drags. Starts scattered.
    @Published var currentPosition: SIMD3<Float>
    @Published var isPlaced: Bool = false

    init(data: PuzzlePieceData, boardSizeMeters: SIMD2<Float>, scatterPosition: SIMD3<Float>) {
        self.id = data.id
        self.data = data
        self.imageName = data.file.replacingOccurrences(of: ".png", with: "")

        let hx = Float(data.homeCenterNormX) * boardSizeMeters.x
        let hz = Float(data.homeCenterNormY) * boardSizeMeters.y
        // Image space: x right, y down. Table space: x right, z "away from
        // the user" across the table's depth. No flip needed here (unlike
        // a vertical wall board) since there's no up/down gravity concern —
        // if the layout ends up mirrored front-to-back, flip the sign on hz.
        self.homeCenter = SIMD3<Float>(hx, 0, hz)
        self.pieceSize = SIMD2<Float>(Float(data.widthNorm) * boardSizeMeters.x,
                                       Float(data.heightNorm) * boardSizeMeters.y)
        self.currentPosition = scatterPosition
    }

    /// Distance threshold under which a drag-release snaps the piece home.
    /// Scaled down along with the smaller board/piece size.
    static let snapDistance: Float = 0.025 // 2.5cm, tune to taste
}
