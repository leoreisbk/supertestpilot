# Artifact Toast Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blocking modal setup sheet with a subtle floating pill toast at the bottom of the window that shows download progress and auto-dismisses on success.

**Architecture:** Remove `SetupSheet` and the `.sheet(isPresented: .constant(!artifactManager.isReady))` from `ContentView`. Add a new `ArtifactToastView` struct in `ContentView.swift` that reads `ArtifactManager.state` and overlays itself at the bottom of the `NavigationSplitView` via `.overlay(alignment: .bottom)`. The toast manages its own show/hide state: visible while downloading/checking/failed, transitions to a "Ready" success state for 2 seconds then fades out.

**Tech Stack:** SwiftUI, `@Observable` (already used by `ArtifactManager`), `Task.sleep` for auto-dismiss

---

## File Structure

- **Modify:** `mac-app/TestPilotApp/Views/ContentView.swift`
  - Remove `SetupSheet` struct (lines 100–146)
  - Remove `.sheet(isPresented: .constant(!artifactManager.isReady))` modifier
  - Add `.overlay(alignment: .bottom)` with new `ArtifactToastView`
  - Add `ArtifactToastView` struct at the bottom of the file

---

### Task 1: Replace blocking sheet with toast overlay

**Files:**
- Modify: `mac-app/TestPilotApp/Views/ContentView.swift`

- [ ] **Step 1: Open the file and confirm current state**

  Read `mac-app/TestPilotApp/Views/ContentView.swift` and confirm:
  - Line ~39: `.sheet(isPresented: .constant(!artifactManager.isReady)) { SetupSheet(manager: artifactManager) }`
  - Lines ~100–146: `struct SetupSheet: View { ... }`

- [ ] **Step 2: Remove the blocking sheet modifier**

  In `ContentView.body`, replace:
  ```swift
  .task { await artifactManager.ensureArtifacts() }
  .sheet(isPresented: .constant(!artifactManager.isReady)) {
      SetupSheet(manager: artifactManager)
  }
  ```
  with:
  ```swift
  .task { await artifactManager.ensureArtifacts() }
  .overlay(alignment: .bottom) {
      ArtifactToastView(manager: artifactManager)
          .padding(.bottom, 16)
  }
  ```

- [ ] **Step 3: Delete the SetupSheet struct**

  Remove the entire `// MARK: - SetupSheet` section and `struct SetupSheet` (from the `// MARK: - SetupSheet` comment through the closing `}` of `SetupSheet`).

- [ ] **Step 4: Add ArtifactToastView at the bottom of ContentView.swift**

  Append after the closing `}` of `ContentView`:

  ```swift
  // MARK: - ArtifactToastView

  private struct ArtifactToastView: View {
      let manager: ArtifactManager

      @State private var showReady = false
      @State private var visible   = false

      var body: some View {
          Group {
              if visible {
                  toastContent
                      .padding(.horizontal, 16)
                      .padding(.vertical, 10)
                      .background(.regularMaterial, in: Capsule())
                      .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                      .transition(.asymmetric(
                          insertion: .move(edge: .bottom).combined(with: .opacity),
                          removal:   .move(edge: .bottom).combined(with: .opacity)
                      ))
              }
          }
          .animation(.spring(duration: 0.35), value: visible)
          .onChange(of: manager.state) { _, state in
              handleStateChange(state)
          }
          .onAppear {
              handleStateChange(manager.state)
          }
      }

      @ViewBuilder
      private var toastContent: some View {
          switch manager.state {
          case .checking:
              HStack(spacing: 8) {
                  ProgressView().scaleEffect(0.8)
                  Text("Checking for updates…")
                      .font(.caption.weight(.medium))
                      .foregroundStyle(.secondary)
              }

          case .downloading(let artifact, let progress):
              VStack(spacing: 6) {
                  HStack(spacing: 8) {
                      ProgressView().scaleEffect(0.8)
                      Text("Downloading \(artifact)…")
                          .font(.caption.weight(.medium))
                          .foregroundStyle(.secondary)
                  }
                  ProgressView(value: progress)
                      .progressViewStyle(.linear)
                      .frame(width: 200)
                      .tint(.blue)
              }

          case .failed(let msg):
              HStack(spacing: 10) {
                  Image(systemName: "exclamationmark.circle.fill")
                      .foregroundStyle(.red)
                  Text(msg)
                      .font(.caption.weight(.medium))
                      .foregroundStyle(.red)
                      .lineLimit(2)
                      .frame(maxWidth: 260, alignment: .leading)
                  Button("Retry") {
                      Task { await manager.ensureArtifacts() }
                  }
                  .font(.caption.weight(.medium))
                  .buttonStyle(.borderedProminent)
                  .controlSize(.mini)
              }

          case .ready where showReady:
              HStack(spacing: 8) {
                  Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(.green)
                  Text("Ready")
                      .font(.caption.weight(.medium))
                      .foregroundStyle(.secondary)
              }

          default:
              EmptyView()
          }
      }

      private func handleStateChange(_ state: ArtifactState) {
          switch state {
          case .checking, .downloading, .failed:
              visible = true
              showReady = false
          case .ready:
              showReady = true
              visible = true
              Task {
                  try? await Task.sleep(for: .seconds(2))
                  withAnimation { visible = false }
                  try? await Task.sleep(for: .milliseconds(400))
                  showReady = false
              }
          case .unknown:
              visible = false
          }
      }
  }
  ```

- [ ] **Step 5: Build and verify in Xcode**

  Open `mac-app/TestPilot.xcodeproj`, build the `TestPilotApp` scheme (`Cmd+B`).
  Expected: BUILD SUCCEEDED with no errors or warnings about missing `SetupSheet`.

  To test the toast manually: in `ArtifactManager.ensureArtifacts()`, temporarily comment out the `#if DEBUG` early return to let the download flow run, then re-enable it.

- [ ] **Step 6: Commit**

  ```bash
  git add mac-app/TestPilotApp/Views/ContentView.swift
  git commit -m "feat(mac): replace setup sheet with floating pill toast"
  ```

---

## Self-Review

**Spec coverage:**
- ✅ App immediately accessible — blocking `.sheet` removed
- ✅ Bottom center pill — `.overlay(alignment: .bottom)` with `Capsule` background
- ✅ Spinner + progress during download — `checking` and `downloading` cases
- ✅ "Ready" + checkmark on success — `ready` case with `showReady`
- ✅ 2s auto-dismiss with fade — `Task.sleep(2s)` + `withAnimation { visible = false }`
- ✅ Error state with Retry — `failed` case with red styling and button
- ✅ Spring appear, easeOut dismiss — `.asymmetric` transition + `.spring` animation

**Placeholder scan:** None found.

**Type consistency:** `ArtifactState` cases match `ArtifactManager.swift` exactly: `.unknown`, `.checking`, `.downloading(artifact:progress:)`, `.ready`, `.failed`.
