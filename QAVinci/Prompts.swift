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
        {"cmd": "tap", "type": "E", "label": "X"} - Tap on the UI element of type "E" with label "X". This command cannot be issued with UI elements where `"type": "Other"`
        {"cmd": "type", "type": "E", "label": "X", "text": "TEXT"}  - Type the specified text into the UI element of type "E" with label X
        {"cmd": "stop", "answer": "ANSWER"} - You've fulfilled your objective or don't know how to proceed. If your objective was a question, then provide the answer you found, otherwise, leave the answer empty.
        {"cmd": "scrollDown"} - Scrolls down in the current page
        {"cmd": "scrollUp"} - Scrolls up in the current page
        {"cmd": "goBack"} - Go Back, regardless of the element
        {"cmd": "wait", "seconds": X} - Wait or sleep for X seconds. X is a Double

        EXAMPLE:
        ===
        OBJECTIVE: What's the name of the current page?
        UI:
        NavigationBar, identifier: 'Sales'
        StaticText, label: 'Sale'
        ---
        YOU:
        {"cmd": "stop", "answer": "Sales"}
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
        OBJECTIVE: Find the user's statement
        UI:
        StaticText, label: 'useremail@domain.co'
        Other, label: 'Statement', value: 750,762
        StaticText, label: '1 Infinite Loop'
        ---
        YOU:
        {"cmd": "stop", "answer": "750,762"}
        ===

        Your objective is listed below.
        ===
        OBJECTIVE: \(objective)
        """
        .removeComments()
    }

    static func steps(objective: String) -> String {
        """
        As a mobile app agent, you have an objective and a simplified UI description
        Divide the following objective into a JSON array of strings containing each step to be executed
        Reply with only the JSON array
        Be as granular as possible in the steps division

        OBJECTIVE: `\(objective)`
        STEPS:
        """
        .removeComments()
    }
}

private extension String {
    func removeComments() -> String {
        replacing(/\/\/.*/, with: "")
    }
}
