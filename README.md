TestPilot
===

Automated end-to-end tests for mobile apps using GPT-4.

https://user-images.githubusercontent.com/1066295/227050296-9e616a41-ef9e-411c-8c14-03b396d2d0df.mp4

# Installation
You can install `testpilot` using Homebrew:

```sh
$ brew tap workco/testpilot
$ brew install testpilot
```

# Usage
Write your test cases in plain natural language. The CLI scans the given directory for files using the `.testpilot` extension, then run each as an individual test case.

There are no rules for writing tests. Below are examples using a step-by-step approach where the test describes which elements must be interacted with, and another example that has just an objective, which GPT-4 will try to figure out how to achieve

### Examples for [Apple's Fruta app](https://developer.apple.com/documentation/swiftui/fruta_building_a_feature-rich_app_with_swiftui):
```
# searchAndBuy.testpilot
Search for 'Tropical Blue' and navigate to that item. Add it to favorites.
Buy with Apple Pay from the Favorites tab
```
```
# manageFavorites.testpilot
Scroll up, go to Sailor Man. then add it to Favorites. Go back to the Menu and then into "That's a Smore!".
Add that to favorites. Go to the Favorites tab and then back to the root.
Go to Sailor Man and remove it from favorites
```
```
# buyWithApplePay.testpilot
Buy my favorite beverage
```

## Before running tests - Start the logging server

Host the websocket logging server available on `ws-logging-server/`, in order to see the steps being executed by the test runner. This is required due to [limitation around Xcode test targets](https://developer.apple.com/forums/thread/727620). See the [server's documentation](./ws-logging-server/README.md) for running instructions.

## Running the tests

Now you can just run `testpilot` providing the path to the test files, the bundle identifier for the app you are testing, and your OpenAI key:
```sh
$ testpilot [<tests-path> | .] -o <open-ai-key> --bundle-id 'your.bundle.id'
```

The key can also be defined as an environment variable named `OPEN_AI_KEY`

### Test device

You can preemptively specify which device should be used for testing with the `--device` option. When using that option, you must also provide which platform that device uses:

```sh
$ testpilot --device 'platform=iOS Simulator,UDID=53D7B166-09AC-4A9B-9815-6264EC2552AD'
```
> Note that `UDID` need to be all caps following this exacly pattern.

If you don't send the `--device` option, `testpilot` will halt and ask you which device you'd like to use. Enter the number of the desired device from the given list:

```sh
$ testpilot

Found 1 test file:
1. Sample test

0: iPad 16.2 53D7B166-09AC-4A9B-9815-6264EC2552AD
1: iPad Air 16.2 9ADC85CC-6826-40F5-BC44-43CBAFE76D60
2: iPad Pro 16.2 1BEFFE89-5BDA-403C-9479-D20497FA52E8

Enter the device number (ex. 12):
2
```

## Config File

Since the arguments sent to `testpilot` can grow to an extensive list, you can define these in a JSON config file and use that by default. By default, `testpilot` looks for a file named `testpilot.config.json` in the current directly. Alternatively, you can send the path to the config file as an argument:

```json
// testpilot.config.json
{
  "bundle-id": "your.bundle.id",
  "logging-server": "ws://loggingserver.domain",
  "device": "UDID", 
}
```

## Code Sign on Real Devices

Since you can run `testpilot` on real devices you need to provide the code sign identity and provisioning profile. You can do this by setting `--code-sign-config` with the following `json` format file:

```json
// codesign.config.json
{
    "teamId": "[TEAM_ID]",
    "runnerBundleId": "[RUNNER_BUNDLE_ID]",
    "provisioningProfile": "[RUNNER_PROVISIONING_PROFILE]",
    "codeSignStyle": "Manual"
}
```

```json
// testpilot.config.json
{
  "bundle-id": "your.bundle.id",
  "logging-server": "ws://loggingserver.domain",
  "device": "platform=iOS Simulator,UDID=[DEVICE_UDID]", 
  "code-sign-config": "/path/to/codesign.config.json",
}
```

# Capabilities
`testpilot` relies on accessibility labels to "see" and interact with your app. Currently, it can interact using the following commands. We're expanding its capabilities, but keep this in mind when writing your tests for now:
- Tapping on elements
- Typing texts into elements
- Scrolling up and down
- Waiting (useful if you need to load something)

A test is considered successful if `testpilot` was capable of executing all steps to completion.

# UI Minification & Token usage

To reduce the number of tokens used on each step of the test execution and to ensure GPT-4 only receives relevant UI elements from the accessibility tree, TestPilot pre-processes a dump of the host app XCUIApplication, and removes any any tokens that may bloat the REST request or confuse GPT-4. All UI elements that don't contain a `label`, `identifier`, or `value` are automatically removed, since interacting with them becomes virtually impossible. Similarly, all frames and memory addresses also get stripped out, along with the UI dump "header" and "footer".

Considering the following raw UI dump. Notice how it has a header, footer and a bunch of `Other` UI elements that aren't used and will only increment the token count and limit for each request.
```
Attributes: Application, 0x7fb5a0512bb0, pid: 41491, label: 'Test App'
Element subtree:
 →Application, 0x7fb5a0512bb0, pid: 41491, label: 'Test App'
    Window (Main), 0x7fb5a052ab50, {{0.0, 0.0}, {393.0, 852.0}}
      Other, 0x7fb5a051ea50, {{0.0, 0.0}, {393.0, 852.0}}
        Other, 0x7fb5a0647560, {{0.0, 0.0}, {393.0, 852.0}}
          Other, 0x7fb5a0644cb0, {{0.0, 0.0}, {393.0, 852.0}}
            Other, 0x7fb5a066c4e0, {{0.0, 0.0}, {393.0, 852.0}}
              Other, 0x7fb5a067d650, {{0.0, 0.0}, {393.0, 852.0}}
                Other, 0x7fb5a06163f0, {{0.0, 0.0}, {393.0, 852.0}}
                  Other, 0x7fb5a0655880, {{0.0, 0.0}, {393.0, 852.0}}
                    Other, 0x7fb5a06539d0, {{0.0, 0.0}, {393.0, 852.0}}
                      Other, 0x7fb5a0651680, {{0.0, 0.0}, {393.0, 852.0}}
                        Other, 0x7fb5a06554b0, {{0.0, 0.0}, {393.0, 852.0}}
                          Other, 0x7fb5a0654160, {{0.0, 0.0}, {393.0, 852.0}}
                            Other, 0x7fb5a06143a0, {{0.0, 0.0}, {393.0, 852.0}}
                              Other, 0x7fb5a0653da0, {{0.0, 0.0}, {393.0, 852.0}}
                                Button, 0x7fb5a0614770, {{20.0, 59.0}, {55.0, 40.0}}, label: 'Menu'
                                  Image, 0x7fb5a0650280, {{20.0, 59.0}, {40.0, 40.0}}
                                  Image, 0x7fb5a0655100, {{66.5, 75.8}, {10.0, 6.3}}, label: 'chevron'
                                Other, 0x7fb5a0619ff0, {{203.5, 71.8}, {169.5, 14.3}}, label: 'App presented by sponsor'
                                  StaticText, 0x7fb5a0664eb0, {{203.5, 71.8}, {93.0, 14.3}}, label: 'App presented by'
                                  Image, 0x7fb5a061d2d0, {{300.3, 72.0}, {72.7, 14.0}}, label: 'Sponsor'
                                StaticText, 0x7fb5a06167a0, {{20.0, 111.2}, {121.0, 45.7}}, label: 'See more'
                  TabBar, 0x7fb5a066e600, {{0.0, 769.0}, {393.0, 83.0}}, label: 'Tab Bar'
                    Other, 0x7fb5a066e710, {{0.0, 769.0}, {393.0, 1.0}}
                    Button, 0x7fb5a0627f50, {{2.0, 770.0}, {75.0, 48.0}}, label: 'News'
                      Image, 0x7fb5a0628060, {{27.0, 776.0}, {24.0, 24.0}}, identifier: 'News'
                    Button, 0x7fb5a0628170, {{81.0, 770.0}, {74.0, 48.0}}, label: 'Explore', Selected
                      Image, 0x7fb5a06228d0, {{105.7, 776.0}, {24.0, 24.0}}, identifier: 'Explore'
                    Button, 0x7fb5a06229e0, {{159.0, 770.0}, {75.0, 48.0}}, label: 'Leaderboard'
                      Image, 0x7fb5a0622af0, {{184.0, 776.0}, {24.0, 24.0}}, identifier: 'Leaderboard'
                    Button, 0x7fb5a0654530, {{238.0, 770.0}, {74.0, 48.0}}, label: 'Watch'
                      Image, 0x7fb5a0654640, {{262.7, 776.0}, {24.0, 24.0}}, identifier: 'Watch'
                    Button, 0x7fb5a0654750, {{316.0, 770.0}, {75.0, 48.0}}, label: 'Profile'
                      Image, 0x7fb5a065e180, {{341.3, 776.0}, {24.0, 24.0}}, identifier: 'Profile'
Path to element:
 →Application, 0x7fb5a0512bb0, pid: 41491, label: 'Test App'
Query chain:
 →Find: Target Application 'co.work.TestApp'
  Output: {
    Application, 0x7fb5a070ea10, pid: 41491, label: 'TestApp'
  }
```

After minification, this is what TestPilot sends to GPT-4. Note how TestPilot preserved only the UI elements that can actually be interacted with:
```
Button, label: 'Menu'
Image, label: 'chevron'
Other, label: 'App presented by sponsor'
StaticText, label: 'App presented by'
Image, label: 'Sponsor'
StaticText, label: 'See more'
TabBar, label: 'Tab Bar'
Button, label: 'News'
Image, identifier: 'News'
Button, label: 'Explore', Selected
Image, identifier: 'Explore'
Button, label: 'Leaderboard'
Image, identifier: 'Leaderboard'
Button, label: 'Watch'
Image, identifier: 'Watch'
Button, label: 'Profile'
Image, identifier: 'Profile'
```

This allows us to reduce the original UI dump from 1386 tokens to 154 tokens after minification. That's a 88.8% reduction without losing any relevant information!

# License
// TODO
