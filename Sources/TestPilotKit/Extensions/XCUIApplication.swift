//
//  XCUIApplication.swift
//  TestPilotKit
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation
import XCTest

extension String {
    func simplifyUI() -> String {
        // Removing all elements without relevant info; also removes all hex mem addresses and frames
        var simplifiedUI = (
            try? NSRegularExpression(pattern: "(\\n\\s*.*\\}\\}$|, 0x.*\\}\\})", options: .anchorsMatchLines)
                .stringByReplacingMatches(in: self, options: [], range: NSMakeRange(0, count), withTemplate: "")
        ) ?? self

        simplifiedUI = (
            try? NSRegularExpression(pattern: "^\\s\\s+", options: .anchorsMatchLines)
                .stringByReplacingMatches(
                    in: simplifiedUI,
                    options: [],
                    range: NSMakeRange(0, simplifiedUI.count),
                    withTemplate: ""
                )
        ) ?? simplifiedUI

        // Removing "header"
        if let range = try? NSRegularExpression(pattern: "→Application.*?$", options: .anchorsMatchLines)
            .firstMatch(in: simplifiedUI, options: [], range: NSMakeRange(0, simplifiedUI.count))?
            .range
        {
            simplifiedUI = String(simplifiedUI[String.Index(utf16Offset: range.location + range.length, in: simplifiedUI)...])
        }

        // Removing "footer"
        if let range = simplifiedUI.range(of: "\nPath to element") {
            simplifiedUI = String(simplifiedUI[...range.lowerBound])
        }
        
        return simplifiedUI
    }
}
