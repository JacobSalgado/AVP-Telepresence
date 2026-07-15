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

    /// Home position in board-local space, in meters, measured from the
    /// board's top-left corner. boardSizeMeters is the physical/virtual
    /// size you decide the whole board should occupy.
    let homeCenter: SIMD3<Float>
    let pieceSize: SIMD2<Float> // width, height in meters

    /// Current live position, mutated as the user drags. Starts scattered.
    @Published var currentPosition: SIMD3<Float>
    @Published var isPlaced: Bool = false

    init(data: PuzzlePieceData, boardSizeMeters: SIMD2<Float>, scatterPosition: SIMD3<Float>) {
        self.id = data.id
        self.data = data
        self.imageName = data.file.replacingOccurrences(of: ".png", with: "")

        let hx = Float(data.homeCenterNormX) * boardSizeMeters.x
        let hy = Float(data.homeCenterNormY) * boardSizeMeters.y
        // Board space: x right, y down (image space) -> convert to RealityKit
        // x right, y up by flipping. z is fixed (pieces float slightly above board).
        self.homeCenter = SIMD3<Float>(hx, -hy, 0)
        self.pieceSize = SIMD2<Float>(Float(data.widthNorm) * boardSizeMeters.x,
                                       Float(data.heightNorm) * boardSizeMeters.y)
        self.currentPosition = scatterPosition
    }

    /// Distance threshold under which a drag-release snaps the piece home.
    static let snapDistance: Float = 0.05 // 5cm, tune to taste
}
