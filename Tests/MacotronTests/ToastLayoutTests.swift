// ToastLayoutTests.swift
import AppKit
import Testing
@testable import Modules

@Suite("Toast")
struct ToastLayoutTests {
    @Test("bottom toast is centered and inset from the anchor")
    func bottomCenters() {
        let anchor = NSRect(x: 100, y: 200, width: 800, height: 600)
        let frame = ToastLayout.frame(size: NSSize(width: 200, height: 40), in: anchor, position: .bottom)
        #expect(frame.midX == anchor.midX)
        #expect(frame.minY == 248)
        #expect(frame.width == 200)
    }

    @Test("top toast is centered and inset from the top")
    func topCenters() {
        let anchor = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = ToastLayout.frame(size: NSSize(width: 180, height: 36), in: anchor, position: .top)
        #expect(frame.midX == 500)
        #expect(frame.maxY == 752)
    }

    @Test("toast stays padded inside a narrow window")
    func clampsToEdges() {
        let anchor = NSRect(x: 0, y: 0, width: 200, height: 400)
        let frame = ToastLayout.frame(size: NSSize(width: 180, height: 40), in: anchor, position: .bottom)
        #expect(frame.minX >= ToastLayout.margin)
        #expect(frame.maxX <= anchor.maxX - ToastLayout.margin)
        #expect(frame.minY == ToastLayout.margin)
    }

    @Test("tall copy keeps its height and only width is capped")
    func wrapsInsteadOfClippingHeight() {
        let anchor = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = ToastLayout.frame(size: NSSize(width: 800, height: 72), in: anchor, position: .bottom)
        #expect(frame.width == ToastLayout.maxWidth)
        #expect(frame.height == 72)
    }

    @Test("title and body join on one line")
    func oneLine() {
        #expect(ToastLayout.line("Copied", nil) == "Copied")
        #expect(ToastLayout.line("Copied", "UUID") == "Copied UUID")
        #expect(ToastLayout.line("Copied", "  ") == "Copied")
    }

    @Test("success is green")
    @MainActor
    func successColor() {
        #expect(ToastLayout.kind("success").tint == .systemGreen)
        #expect(ToastLayout.kind("failure").tint == .systemRed)
        #expect(ToastLayout.kind("error").tint == .systemRed)
        #expect(ToastLayout.kind("warning").tint == .systemOrange)
        #expect(ToastLayout.kind("info").tint == nil)
        #expect(ToastLayout.kind(nil).tint == nil)
    }

    @Test("status kinds pick default icons")
    func defaultSymbols() {
        #expect(ToastLayout.kind("success").defaultSymbol == "checkmark.circle.fill")
        #expect(ToastLayout.kind("error").defaultSymbol == "xmark.circle.fill")
        #expect(ToastLayout.kind("warning").defaultSymbol == "exclamationmark.triangle.fill")
        #expect(ToastLayout.kind("info").defaultSymbol == nil)
        #expect(ToastLayout.kind(nil).defaultSymbol == nil)
    }

    @Test("custom colors tint the icon but never the text")
    func customColorTextStaysLegible() {
        let custom = ToastLayout.kind("#ff00ff")
        #expect(custom.tint != nil)
        #expect(custom.textTint == nil)
        #expect(ToastLayout.kind("success").textTint == .systemGreen)
        #expect(ToastLayout.kind("error").textTint == .systemRed)
        #expect(ToastLayout.kind(nil).textTint == nil)
    }

    @Test("position parse defaults to bottom")
    func parsePosition() {
        #expect(ToastPosition.parse("top") == .top)
        #expect(ToastPosition.parse("BOTTOM") == .bottom)
        #expect(ToastPosition.parse(nil) == .bottom)
        #expect(ToastPosition.parse("nope") == .bottom)
    }
}
