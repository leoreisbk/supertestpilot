//
//  Prompts.swift
//  QAVinci
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
        Yield the "stop" command if you think you've fulfilled your objective
        Navigating means tapping an element

        You can issue only these commands:
        {"cmd": "tap", "type": "E", "label": "X"} - Tap on the UI element of type "E" with label "X". This command can only be issued with UI elements where `"type": "Button"`
        {"cmd": "type", "type": "E", "label": "X", "text": "TEXT"}  - Type the specified text into the UI element of type "E" with label X
        {"cmd": "assert", "answer": "ANSWER", "expected": "EXPECTED"} - You've been asked to compare or check a value with what you see. ANSWER should be what you found and EXPECTED the value that was given in the objective. Leave the ANSWER null if you can't find it.
        {"cmd": "scrollDown"} - Scrolls down in the current page
        {"cmd": "scrollUp"} - Scrolls up in the current page
        {"cmd": "goBack"} - Go Back, regardless of the element
        {"cmd": "wait", "seconds": X} - Wait or sleep for X seconds. X is a Double

        EXAMPLE:
        ===
        OBJECTIVE: Page should be named Sales
        UI:
        NavigationBar, identifier: 'Sales'
        StaticText, label: 'Sale'
        ---
        YOU:
        {"cmd": "assert", "answer": "Sales", "expected": "Sales"}
        ===

        EXAMPLE:
        ===
        OBJECTIVE: Go to Profile
        UI:
        TabBar, label: 'Tab Bar'
        Button, label: 'Profile Tab'
        StaticText, label: 'Profile'
        Button, label: 'Sales', Selected
        ---
        YOU:
        {"cmd": "tap", "type": "Button", "label": "Profile Tab"}
        ===

        EXAMPLE:
        OBJECTIVE: User statement should be 0
        UI:
        StaticText, label: 'useremail@domain.co'
        Other, label: 'Statement', value: 750,762
        StaticText, label: '1 Infinite Loop'
        ---
        YOU:
        {"cmd": "assert", "answer": "750,762", "expected": "0"}
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
        replacing(#/\/\/.*/#, with: "")
    }
}
