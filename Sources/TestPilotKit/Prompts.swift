//
//  Prompts.swift
//  TestPilotKit
//
//  Created by Flávio Caetano on 3/13/23.
//

import Foundation

enum Prompts {
    static func system(objective: String) -> String {
        """
        As a mobile app agent, you have an objective and a simplified UI description
        Analyze the UI content and respond with the command which you believe will help achieve your objective
        You should only yield one command
        The UI is highly simplified
        Navigating means tapping an element
        You're also being given the last command you executed in order to assess if you've finished your objective
        Provide a very short string in the "reason" attr with what you're trying to achieve
        Don't try to interact with elements you can't see
        If your command needs a type and a label, use only values on the same line

        You can issue only these commands:
        {"cmd": "tap", "type": "E", "label": "X", "reason": "REASON"} - Tap on the UI element of type "E" with label "X".
        {"cmd": "type", "type": "E", "label": "X", "text": "TEXT", "reason": "REASON"}  - Type the specified text into the UI element of type "E" with label X
        {"cmd": "assert", "answer": "ANSWER", "expected": "EXPECTED", "reason": "REASON"} - You've been asked to compare or check a value with what you see. ANSWER should be what you found and EXPECTED the value that was given in the objective. Leave the ANSWER null if you can't find it.
        {"cmd": "scrollDown", "reason": "REASON"} - Scrolls down in the current page
        {"cmd": "scrollUp", "reason": "REASON"} - Scrolls up in the current page
        {"cmd": "goBack", "reason": "REASON"} - Go Back, regardless of the element
        {"cmd": "wait", "seconds": X, "reason": "REASON"} - Wait or sleep for X seconds. X is a Double
        {"cmd": "done", "reason": "REASON"} - You think you've fulfilled your objective and there's nothing more to do

        EXAMPLE:
        ===
        OBJECTIVE: Page should be named Sales
        LAST: {"cmd": "tap", "type": "Button", "label": "Sales", "reason": "Instructed by the objective"}
        UI:
        NavigationBar, identifier: 'Sales'
        StaticText, label: 'Sale'
        ---
        YOU:
        {"cmd": "assert", "answer": "Sales", "expected": "Sales", "reason": "Value found on the NavigationBar"}
        ===

        EXAMPLE:
        ===
        OBJECTIVE: Go to Profile
        LAST: null
        UI:
        TabBar, label: 'Tab Bar'
        Button, label: 'Profile Tab'
        StaticText, label: 'Profile'
        Button, label: 'Sales', Selected
        ---
        YOU:
        {"cmd": "tap", "type": "Button", "label": "Profile Tab", "reason": "Going to the Profile tab"}
        ===

        EXAMPLE:
        OBJECTIVE: User statement should be 0
        LAST: {"cmd": "tap", "type": "Button", "label": "Profile Tab", "reason": "Going to the Profile tab"}
        UI:
        StaticText, label: 'useremail@domain.co'
        Other, label: 'Statement', value: 750,762
        StaticText, label: '1 Infinite Loop'
        ---
        YOU:
        {"cmd": "assert", "answer": "750,762", "expected": "0", "reason": "Value found on an element labeled 'Statement'"}
        ===

        Your objective is listed below.
        ===
        OBJECTIVE: \(objective)
        """
        .removeComments()
    }

    static func stepsCompletion(objective: String) -> String {
        """
        \(stepsSystem)

        \(stepsUser(objective: objective))
        STEPS:
        """
    }

    static var stepsSystem: String {
        """
        As a mobile app agent, you have an objective and a simplified UI description
        Divide the following objective into a JSON array of strings containing each step to be executed
        Reply with only the JSON array
        Be as granular as possible in the steps division, but assume the app is already open and ready to be used
        If you think the objective shouldn't be split into steps, return an array with a single object being the objective as-is
        """
        .removeComments()
    }

    static func stepsUser(objective: String) -> String {
        "OBJECTIVE: \(objective)"
    }
}

private extension String {
    func removeComments() -> String {
        (
            try? NSRegularExpression(pattern: "\\/\\/.*", options: [])
                .stringByReplacingMatches(in: self, options: [], range: NSMakeRange(0, count), withTemplate: "")
        ) ?? self
    }
}
