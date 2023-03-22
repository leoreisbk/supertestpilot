qavinci - Automated E2E tests using GPT
===

Automated end-to-end tests for mobile tests using GPT.

https://user-images.githubusercontent.com/1066295/227050296-9e616a41-ef9e-411c-8c14-03b396d2d0df.mp4

# Installation
You can install `qavinci` using Homebrew:

// TODO

# Usage
Write your test cases in plain natural language. The CLI scans the given directory for files using the `.qavinci` extension, then run each as an individual test case.

Best results have been observed by giving a step-by-step instruction of how to achieve the final objective for the given test case. `qavinci` will try to split the test case into steps and then execute each individual step.

### Examples for [Apple's Fruta app](https://developer.apple.com/documentation/swiftui/fruta_building_a_feature-rich_app_with_swiftui):
```
# buyWithApplePay.qavinci
Search for 'Tropical Blue' and navigate to that item. Add it to favorites.
Buy with Apple Pay from the Favorites tab
```
```
# manageFavorites.qavinci
Scroll up, go to Sailor Man. then add it to Favorites. Go back to the Menu and then into "That's a Smore!".
Add that to favorites. Go to the Favorites tab and then back to the root.
Go to Sailor Man and remove it from favorites
```

Then just run `qavinci` providing the path to the test files and tested project, and your OpenAI key:
```sh
$ qavinci [<tests-path> | .] -o <open-ai-key>
```

The key can also be defined as an environment variable named `OPEN_AI_KEY`

# Capabilities
`qavinci` relies on accessibility labels to "see" and interact with your app. Currently, it can interact using the following commands. We're expanding its capabilities, but keep this in mind when writing your tests for now:
- Tapping on elements
- Typing texts into elements
- Scrolling up and down
- Waiting (useful if you need to load something)

A test is considered successful if `qavinci` was capable of executing all steps to completion.

# License
// TODO