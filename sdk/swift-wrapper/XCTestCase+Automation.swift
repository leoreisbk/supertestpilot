//
//  XCTestCase+Automation.swift
//  
//
//  Created by Igor Lira on 4/13/23.
//

import Foundation
import TestPilotShared
import XCTest

@MainActor
public extension XCTestCase {
    func automate(
        config: Config,
        objective: String,
        bundleId: String?,
        shouldRecordSteps: Bool = false
    ) async throws {
        try await TestPilotIOS.shared.automate(
            test: self,
            config: config,
            objective: objective,
            bundleId: bundleId,
            shouldRecordSteps: shouldRecordSteps
        )
    }
}
