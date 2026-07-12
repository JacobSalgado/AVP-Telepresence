//
//  WhiteboardView.swift
//  AVP Telepresence
//
//  Created by Research on 7/1/26.
//

import SwiftUI

struct WhiteboardStroke: Identifiable, Codable {
    let id: UUID
    var points: [CGPoint]
    var lineWidth: CGFloat
}

struct WhiteboardView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(SessionManager.self) private var sessionManager
    
    @State private var currentPoints: [CGPoint] = []
    
    private let boardSize: CGFloat = 720
    private let gridSize: Int = 4
    private var cellSize: CGFloat {boardSize / 4}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    appModel.whiteboardStrokes.removeAll()
                    sessionManager.send(.whiteboardCleared)
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .padding(8)
            }
            .background(.white.opacity(0.95))
            
            ZStack{
                Canvas { context, size in
                    drawSudokuGrid(context: context)
                    
                    for stroke in appModel.whiteboardStrokes {
                        var path = Path()
                        path.addLines(stroke.points)
                        context.stroke(path, with: .color(.black), lineWidth: stroke.lineWidth)
                    }
                    if currentPoints.count > 1 {
                        var path = Path()
                        path.addLines(currentPoints)
                        context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 3)
                    }
                }
                .frame(width: boardSize, height: boardSize)
                .background(.white.opacity(0.95))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            currentPoints.append(value.location)
                        }
                        .onEnded { _ in
                            guard currentPoints.count > 1 else { currentPoints = []; return }
                            let stroke = WhiteboardStroke(id: UUID(), points: currentPoints, lineWidth: 3)
                            appModel.whiteboardStrokes.append(stroke)
                            sessionManager.send(.whiteboardStroke(stroke))
                            currentPoints = []
                        }
                )
                // hover highlight overlay
                VStack(spacing:0) {
                    ForEach(0..<gridSize, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<gridSize, id: \.self) { col in
                                Color.clear
                                    .frame(width: cellSize, height: cellSize)
                                    .hoverEffect(.highlight)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .frame(width: boardSize, height: boardSize)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /**
     * @brief draws the sudoku grid onto the whiteboard
     * @param context
     * @param size
     */
    private func drawSudokuGrid(context: GraphicsContext) {
        // grid lines
        for i in 0...gridSize {
            let lineWidth: CGFloat = (i % 2 == 0) ? 2 : 1
            let offset = CGFloat(i) * cellSize
            
            var vertical = Path()
            vertical.move(to: CGPoint(x:offset, y:0))
            vertical.addLine(to: CGPoint(x:offset, y:boardSize))
            context.stroke(vertical, with: .color(.black), lineWidth: lineWidth)
            
            var horizontal = Path()
            horizontal.move(to: CGPoint(x: 0, y: offset))
            horizontal.addLine(to: CGPoint(x:boardSize, y:offset))
            context.stroke(horizontal, with: .color(.black), lineWidth: lineWidth)
        }
        
        // given numbers (fixed clues)
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let value = SudokuPuzzle.sample[row][col]
                guard value != 0 else { continue }
                let point = CGPoint(
                    x: CGFloat(col) * cellSize + cellSize / 2,
                    y: CGFloat(row) * cellSize + cellSize / 2
                )
                context.draw(
                    Text("\(value)")
                        .font(.system(size: cellSize * 0.5, weight: .semibold))
                        .foregroundColor(.black),
                    at: point
                )
            }
        }
    }
}

#Preview {
    WhiteboardView()
}
