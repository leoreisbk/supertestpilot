//
//  Logging.swift
//  
//
//  Created by Igor Lira on 4/12/23.
//

import Foundation
import TestPilotShared

public struct Logging {
    private static let LoggingKt = TestPilotShared.Logging.shared
    
    public static func info(_ msg: String) {
        LoggingKt.info(msg: msg)
    }
}
