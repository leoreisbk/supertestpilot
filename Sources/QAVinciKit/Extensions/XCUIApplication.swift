//
//  XCUIApplication.swift
//  QAVinci
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation
import XCTest

extension String {
    func simplifyUI() -> String {
        var simplifiedUI = self
            // Removing all elements without relevant info; also removes all hex mem addresses and frames
            .replacing(#/(\n\s*.*\}\}$|, 0x.*\}\})/#.anchorsMatchLineEndings(), with: "")
            .replacing(#/^\s\s+/#.anchorsMatchLineEndings(), with: "")

        if let range = simplifiedUI.ranges(of: #/→Application.*?$/#.anchorsMatchLineEndings()).first {
            simplifiedUI = String(simplifiedUI[range.upperBound...])
        }

        if let range = simplifiedUI.range(of: "\nPath to element") {
            simplifiedUI = String(simplifiedUI[...range.lowerBound])
        }

        // Remove duplicated lines. Consider this logic as a fallback if the request fails due to token limit
//        simplifiedUI = simplifiedUI
//            .split(separator: "\n")
//            .reduce([]) { result, line in
//                result.contains(line) ? result : result + [line]
//            }
//            .joined(separator: "\n")

        return simplifiedUI
    }
}
