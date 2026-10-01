//
//  TileSudokuModel.swift
//  AVP Telepresence
//
//  Created by Research on 8/6/26.
//

import Foundation
import simd
import Combine

/// A number tile that has been placed into a board cell.
struct PlacedTile: Codable {
    var value: Int      // 1...9
    var row: Int
    var col: Int
}

/// Emitted when a remote participant changes the tile board, so the view
/// can update entities to match.
struct RemoteTileUpdate {
    /// Full current occupancy of editable cells, keyed by "row_col".
    let placed: [String: Int]
}

@MainActor
final class TileSudokuModel: ObservableObject {
    // MARK: Board geometry (vertical, XY plane, facing +Z)

    /// Overall board width in meters. Height is equal (9x9 square).
    let boardSize: Float = 0.72
    var cellSize: Float { boardSize / 9 }

    /// The board's local origin is its CENTER. This returns the local
    /// (x, y) center of a given cell, in the board entity's coordinate
    /// space. Row 0 is the TOP row, col 0 is the LEFT column.
    func cellCenter(row: Int, col: Int) -> SIMD2<Float> {
        let half = boardSize / 2
        // +x is right, +y is up. Row increases downward, so y flips sign.
        let x = -half + cellSize * (Float(col) + 0.5)
        let y =  half - cellSize * (Float(row) + 0.5)
        return SIMD2<Float>(x, y)
    }

    /// Snap tolerance: how close (in meters, on the board plane) a released
    /// tile's center must be to a cell center to count as landing in it.
    /// Half a cell means "closest cell wins as long as you're over the board."
    var snapDistance: Float { cellSize * 0.5 }

    // MARK: Fixed clues vs. editable cells

    /// true where the puzzle has a given clue (not editable).
    private(set) var isClue: [[Bool]] = []

    /// Editable cell occupancy: "row_col" -> value (1...9). Absent = empty.
    @Published private(set) var placed: [String: Int] = [:]

    let remoteUpdates = PassthroughSubject<RemoteTileUpdate, Never>()

    init() {
        isClue = SudokuPuzzle.sample.map { row in row.map { $0 != 0 } }
    }

    static func key(_ row: Int, _ col: Int) -> String { "\(row)_\(col)" }

    func clueValue(row: Int, col: Int) -> Int {
        SudokuPuzzle.sample[row][col]
    }

    func isEditable(row: Int, col: Int) -> Bool {
        !isClue[row][col]
    }

    func placedValue(row: Int, col: Int) -> Int? {
        placed[Self.key(row, col)]
    }

    // MARK: Cell hit-testing

    /// Given a point in the board's local XY space, returns the nearest
    /// EDITABLE cell within snapDistance, or nil if none qualifies (point
    /// is off the board or only over clue cells).
    func nearestEditableCell(toLocal point: SIMD2<Float>) -> (row: Int, col: Int)? {
        let half = boardSize / 2
        // Quick reject: outside the board bounds entirely.
        guard point.x >= -half, point.x <= half,
              point.y >= -half, point.y <= half else { return nil }

        // Convert directly to a grid index, then verify distance + editability.
        let col = Int(((point.x + half) / cellSize).rounded(.down))
        let row = Int(((half - point.y) / cellSize).rounded(.down))
        guard row >= 0, row < 9, col >= 0, col < 9 else { return nil }
        guard isEditable(row: row, col: col) else { return nil }

        let center = cellCenter(row: row, col: col)
        guard simd_distance(point, center) <= snapDistance + cellSize * 0.5 else { return nil }
        return (row, col)
    }

    // MARK: Local mutations

    /// Place a value into an editable cell (replacing whatever was there).
    /// Returns the value that was displaced, if any (so the view can remove
    /// that entity).
    @discardableResult
    func place(value: Int, row: Int, col: Int) -> Int? {
        guard isEditable(row: row, col: col) else { return nil }
        let k = Self.key(row, col)
        let displaced = placed[k]
        placed[k] = value
        checkSolved()
        return displaced
    }

    /// Remove whatever tile is in an editable cell (e.g. when the user
    /// picks a placed tile back up). Returns the removed value, if any.
    @discardableResult
    func clear(row: Int, col: Int) -> Int? {
        let k = Self.key(row, col)
        let removed = placed[k]
        placed[k] = nil
        checkSolved()
        return removed
    }

    // MARK: Remote sync

    func applyRemote(placed newPlaced: [String: Int]) {
        placed = newPlaced
        checkSolved()
        remoteUpdates.send(RemoteTileUpdate(placed: newPlaced))
    }

    /// Snapshot of current occupancy, for broadcasting.
    var snapshot: [String: Int] { placed }

    // MARK: Solve check

    @Published var isSolved: Bool = false

    private func checkSolved() {
        for row in 0..<9 {
            for col in 0..<9 {
                let v = isClue[row][col] ? SudokuPuzzle.sample[row][col]
                                         : (placed[Self.key(row, col)] ?? 0)
                if v == 0 { isSolved = false; return }
            }
        }
        // All filled — check validity.
        isSolved = Self.isValidSolution(currentGrid())
    }

    private func currentGrid() -> [[Int]] {
        (0..<9).map { row in
            (0..<9).map { col in
                isClue[row][col] ? SudokuPuzzle.sample[row][col]
                                 : (placed[Self.key(row, col)] ?? 0)
            }
        }
    }

    private static func isValidSolution(_ grid: [[Int]]) -> Bool {
        func unique(_ nums: [Int]) -> Bool {
            let filtered = nums.filter { $0 != 0 }
            return Set(filtered).count == filtered.count && filtered.count == 9
        }
        for r in 0..<9 { if !unique(grid[r]) { return false } }
        for c in 0..<9 { if !unique((0..<9).map { grid[$0][c] }) { return false } }
        for br in stride(from: 0, to: 9, by: 3) {
            for bc in stride(from: 0, to: 9, by: 3) {
                var box: [Int] = []
                for r in br..<br+3 { for c in bc..<bc+3 { box.append(grid[r][c]) } }
                if !unique(box) { return false }
            }
        }
        return true
    }
}
