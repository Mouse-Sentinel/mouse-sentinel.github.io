import AppKit
import CoreGraphics
import SwiftUI

struct MouseMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.2),
            control1: CGPoint(x: rect.midX - rect.width * 0.48, y: rect.maxY - rect.height * 0.28),
            control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.2),
            control1: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.minY - rect.height * 0.04),
            control2: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.minY - rect.height * 0.04)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.62),
            control2: CGPoint(x: rect.midX + rect.width * 0.48, y: rect.maxY - rect.height * 0.28)
        )
        path.closeSubpath()
        return path
    }
}

struct EarPair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width * 0.43, height: rect.height * 0.92))
        path.addEllipse(in: CGRect(x: rect.maxX - rect.width * 0.43, y: rect.minY, width: rect.width * 0.43, height: rect.height * 0.92))
        return path
    }
}

struct Whiskers: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let leftX = rect.minX
        let rightX = rect.maxX
        let centerY = rect.midY
        let leftStart = rect.midX - rect.width * 0.18
        let rightStart = rect.midX + rect.width * 0.18

        path.move(to: CGPoint(x: leftStart, y: centerY - 8))
        path.addLine(to: CGPoint(x: leftX, y: centerY - 14))
        path.move(to: CGPoint(x: leftStart, y: centerY))
        path.addLine(to: CGPoint(x: leftX + 3, y: centerY))
        path.move(to: CGPoint(x: leftStart, y: centerY + 8))
        path.addLine(to: CGPoint(x: leftX + 8, y: centerY + 14))

        path.move(to: CGPoint(x: rightStart, y: centerY - 8))
        path.addLine(to: CGPoint(x: rightX, y: centerY - 14))
        path.move(to: CGPoint(x: rightStart, y: centerY))
        path.addLine(to: CGPoint(x: rightX - 3, y: centerY))
        path.move(to: CGPoint(x: rightStart, y: centerY + 8))
        path.addLine(to: CGPoint(x: rightX - 8, y: centerY + 14))
        return path
    }
}

struct MouseHeadGlyph: View {
    private static let cream = Color(red: 0.96, green: 0.94, blue: 0.88)
    private static let ink = Color(red: 0.10, green: 0.14, blue: 0.19)

    var body: some View {
        ZStack {
            MouseMark()
                .fill(Self.cream)
                .frame(width: 86, height: 98)
                .offset(y: 14)

            EarPair()
                .fill(Color(red: 0.98, green: 0.96, blue: 0.91))
                .frame(width: 106, height: 62)
                .offset(y: -21)

            Whiskers()
                .stroke(Self.ink.opacity(0.78), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 88, height: 35)
                .offset(y: 31)

            HStack(spacing: 18) {
                Circle().fill(Self.ink.opacity(0.92))
                Circle().fill(Self.ink.opacity(0.92))
            }
            .frame(width: 46, height: 9)
            .offset(y: 16)

            Circle()
                .fill(Self.ink.opacity(0.92))
                .frame(width: 10, height: 10)
                .offset(y: 54)
        }
        .offset(y: -5)
        .frame(width: 150, height: 150)
        .scaleEffect(5.0, anchor: .center)
    }
}

enum DockIcon {
    @MainActor
    static func image(canvas: CGFloat = 1024, scale: CGFloat = 2) -> NSImage? {
        let shapeSize = canvas * (824.0 / 1024.0)
        let cornerRadius = canvas * (185.42 / 1024.0)

        let background = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.37, green: 0.77, blue: 0.23),
                        Color(red: 0.05, green: 0.60, blue: 0.39),
                        Color(red: 0.39, green: 0.78, blue: 0.37)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: shapeSize, height: shapeSize)
            .shadow(color: Color.black.opacity(0.30), radius: canvas * (40.0 / 1024.0), x: 0, y: canvas * (26.0 / 1024.0))

        let content = ZStack {
            background

            MouseHeadGlyph()
        }
        .frame(width: canvas, height: canvas)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.isOpaque = false

        guard let cgImage = renderer.cgImage else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: canvas, height: canvas))
    }
}