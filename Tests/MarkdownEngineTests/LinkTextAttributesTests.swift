//
//  LinkTextAttributesTests.swift
//  MarkdownEngineTests
//
//  The display-time link attributes derived from the theme. AppKit's
//  `NSTextView.linkTextAttributes` default paints every `.link` range
//  `.linkColor` blue regardless of the foreground the styler set, so the
//  editor re-declares the theme's link ink there (see NativeTextViewWrapper's
//  makeNSView/updateNSView). These tests pin the derivation.
//

import AppKit
import Testing
@testable import MarkdownEngine

@MainActor
@Suite("Link text attributes")
struct LinkTextAttributesTests {

    @Test("linkTextAttributes carry the theme's link ink, underline, and pointing hand")
    func attributesFollowThemeLinkInk() {
        let brand = NSColor(calibratedRed: 0.4, green: 0.05, blue: 0.13, alpha: 1)
        let theme = MarkdownEditorTheme(link: brand)
        let attrs = theme.linkTextAttributes
        #expect(attrs[.foregroundColor] as? NSColor == brand)
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attrs[.cursor] as? NSCursor == NSCursor.pointingHand)
    }

    @Test("the default theme reproduces AppKit's stock link look")
    func defaultThemeMatchesStockAppKitLook() {
        // `.linkColor` + single underline is exactly what AppKit's own
        // `linkTextAttributes` default renders, so installing these
        // attributes changes nothing for embedders on the default theme.
        let attrs = MarkdownEditorTheme.default.linkTextAttributes
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.linkColor)
        #expect(attrs[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }
}
