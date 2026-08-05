import Foundation
import simd

/// Matches PuzzleGenio's exported layout.json shape directly. Extra JSON
/// keys we don't need (label, connections, version, generatedAt) are
/// simply ignored by Codable — no need to declare them.
struct PieceBounds: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct PuzzlePieceData: Codable {
    let id: String
    let row: Int   // PuzzleGenio calls this gridY
    let col: Int   // PuzzleGenio calls this gridX
    let fileName: String
    let bounds: PieceBounds

    enum CodingKeys: String, CodingKey {
        case id, fileName, bounds
        case col = "gridX"
        case row = "gridY"
    }
}

struct PuzzleDimensions: Codable {
    let width: Double
    let height: Double
    let tilesX: Int
    let tilesY: Int
    let totalPieces: Int
}

struct PuzzleLayout: Codable {
    let puzzle: PuzzleDimensions
    let pieces: [PuzzlePieceData]
}

/// Runtime state for a piece, wrapping the static layout data.
final class PuzzlePiece: Identifiable, ObservableObject {
    let id: String
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

    /// - Parameters:
    ///   - puzzleDimensions: the overall canvas size from layout.json's
    ///     "puzzle" object — used purely to normalize bounds.x/y/width/height
    ///     into 0...1 fractions before scaling to real-world meters.
    init(data: PuzzlePieceData, puzzleDimensions: PuzzleDimensions,
         boardSizeMeters: SIMD2<Float>, scatterPosition: SIMD3<Float>) {
        self.id = data.id
        self.data = data
        // fileName looks like "pieces/A1.png". The "pieces" folder in the
        // Asset Catalog has "Provides Namespace" checked, so image sets
        // inside it are addressed as "pieces/A1" — keep the folder prefix
        // here and only strip the .png extension. (Deliberately not using
        // URL(fileURLWithPath:) here — it resolves relative-looking paths
        // against the current working directory, which would mangle this
        // string.)
        self.imageName = data.fileName.hasSuffix(".png")
            ? String(data.fileName.dropLast(4))
            : data.fileName

        // PuzzleGenio's bounds are the piece's full bounding box INCLUDING
        // tab overhang, in canvas pixels — x/y can be negative for pieces
        // whose tabs bulge left/up past their nominal cell. The box's
        // center is still the right reference point for "home position."
        let centerXPx = data.bounds.x + data.bounds.width / 2
        let centerYPx = data.bounds.y + data.bounds.height / 2

        let normX = Float(centerXPx / puzzleDimensions.width)
        let normY = Float(centerYPx / puzzleDimensions.height)
        let normW = Float(data.bounds.width / puzzleDimensions.width)
        let normH = Float(data.bounds.height / puzzleDimensions.height)

        let hx = normX * boardSizeMeters.x
        let hz = normY * boardSizeMeters.y
        // Image space: x right, y down. Table space: x right, z "away from
        // the user" across the table's depth. No flip needed here (unlike
        // a vertical wall board) since there's no up/down gravity concern —
        // if the layout ends up mirrored front-to-back, flip the sign on hz.
        self.homeCenter = SIMD3<Float>(hx, 0, hz)
        self.pieceSize = SIMD2<Float>(normW * boardSizeMeters.x, normH * boardSizeMeters.y)
        self.currentPosition = scatterPosition
    }

    /// Distance threshold under which a drag-release snaps the piece home.
    static let snapDistance: Float = 0.025 // 2.5cm, tune to taste
}
