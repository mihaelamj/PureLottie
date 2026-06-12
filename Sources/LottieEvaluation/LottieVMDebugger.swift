//
//  LottieVMDebugger.swift
//  PureLottie
//

import LottieModel

/// Breakpoint predicates understood by the composition VM debugger.
public enum LottieVMBreakpoint: Sendable, Equatable {
    /// Stops at an exact human-readable source path.
    case sourcePath(String)
    /// Stops within a human-readable source subtree.
    case sourcePathPrefix(String)
    /// Stops at an exact authored Lottie JSON path.
    case jsonPath(JSONPath)
    /// Stops when a layer with this authored name is entered, left, or skipped.
    case layerName(String)
    /// Stops when a layer with this authored `ind` value is entered, left, or skipped.
    case layerIndex(Int)
    /// Stops within a shape source subtree.
    case shapePath(String)
    /// Stops at a VM instruction kind.
    case instruction(LottieVMInstruction.Kind)
    /// Stops at a VM trace generated for this source frame.
    case frame(Double)
}

/// Watch expressions evaluated against debugger steps.
public enum LottieVMWatch: Sendable, Equatable {
    /// Current transform stack plus sampled transform values when present.
    case transform
    /// Current opacity/compositing stack plus sampled opacity when present.
    case opacity
    /// One evaluated value by trace-key name, such as `localFrame`, `position`, or `matrix`.
    case sampledProperty(String)
    /// Current style stack.
    case styleState
    /// Render node emission details.
    case renderNodeEmission
}

/// One evaluated watch value at a debugger step.
public struct LottieVMWatchValue: Sendable, Equatable {
    /// Watch expression that produced this value.
    public var watch: LottieVMWatch
    /// Display-ready watch fields.
    public var values: [String: String]

    public init(watch: LottieVMWatch, values: [String: String]) {
        self.watch = watch
        self.values = values
    }
}

/// Backend output emitted by a debugger step.
public struct LottieVMDebugOutput: Sendable, Equatable {
    /// Render node emitted by this step.
    public var renderNodeID: LottieRenderNodeID
    /// VM emission label.
    public var label: String
    /// Display-ready emitted values.
    public var values: [String: String]

    public init(renderNodeID: LottieRenderNodeID, label: String, values: [String: String]) {
        self.renderNodeID = renderNodeID
        self.label = label
        self.values = values
    }
}

/// Compact, display-ready view of the VM state after a step.
public struct LottieVMDebugStateSummary: Sendable, Equatable, CustomStringConvertible {
    /// Selected Lottie source frame.
    public var frameClock: Double
    /// Current human-readable source path.
    public var sourcePath: String
    /// Number of active root/precomposition scopes.
    public var compositionDepth: Int
    /// Number of active layer scopes.
    public var layerDepth: Int
    /// Number of active transform scopes.
    public var transformDepth: Int
    /// Number of active style scopes.
    public var styleDepth: Int
    /// Number of active opacity/compositing scopes.
    public var opacityDepth: Int
    /// Number of active mask/matte scopes.
    public var matteDepth: Int

    public init(state: LottieVMState) {
        frameClock = state.frameClock
        sourcePath = state.sourcePath
        compositionDepth = state.compositionStack.count
        layerDepth = state.layerStack.count
        transformDepth = state.transformStack.count
        styleDepth = state.styleStack.count
        opacityDepth = state.opacityStack.count
        matteDepth = state.matteStack.count
    }

    public var description: String {
        [
            "frame=\(frameClock)",
            "source=\(sourcePath)",
            "compositionDepth=\(compositionDepth)",
            "layerDepth=\(layerDepth)",
            "transformDepth=\(transformDepth)",
            "styleDepth=\(styleDepth)",
            "opacityDepth=\(opacityDepth)",
            "matteDepth=\(matteDepth)",
        ].joined(separator: " ")
    }
}

/// One debugger-visible step over a VM trace record.
public struct LottieVMDebugStep: Sendable, Equatable {
    /// The trace record this debugger step exposes.
    public var record: LottieVMTraceRecord
    /// Current human-readable source path.
    public var sourcePath: String
    /// Authored Lottie JSON path.
    public var jsonPath: JSONPath
    /// Source range when the trace record retained one.
    public var sourceRange: SourceRange?
    /// Stack and frame summary after this step.
    public var stateSummary: LottieVMDebugStateSummary
    /// Emitted backend-independent output, if this step emitted a render node.
    public var emittedOutput: LottieVMDebugOutput?
    /// Watch values that were meaningful at this step.
    public var watchValues: [LottieVMWatchValue]
    /// Breakpoints matched by this step.
    public var hitBreakpoints: [LottieVMBreakpoint]
    /// Checkpoint that can seed deterministic replay for step-back.
    public var replayCheckpoint: LottieVMCheckpoint?
}

/// Deterministic debugger cursor over `LottieCompositionVM` trace results.
public struct LottieVMDebugger: Sendable {
    /// VM execution result being debugged.
    public let result: LottieVMResult
    /// Stored breakpoints used by `continueToBreakpoint()`.
    public var breakpoints: [LottieVMBreakpoint]
    /// Watch expressions evaluated for each returned step.
    public var watches: [LottieVMWatch]
    /// Current index into `result.trace`.
    public private(set) var currentIndex: Int

    public init(
        result: LottieVMResult,
        breakpoints: [LottieVMBreakpoint] = [],
        watches: [LottieVMWatch] = [],
        startAt index: Int = 0
    ) {
        self.result = result
        self.breakpoints = breakpoints
        self.watches = watches
        if result.trace.isEmpty {
            currentIndex = 0
        } else {
            currentIndex = min(max(index, 0), result.trace.count - 1)
        }
    }

    /// Builds a debugger by running the composition VM for one source frame.
    public init(
        animation: LottieAnimation,
        sourceFrame: Double,
        checkpointInterval: Int = 8,
        breakpoints: [LottieVMBreakpoint] = [],
        watches: [LottieVMWatch] = []
    ) {
        let result = LottieCompositionVM(animation: animation, checkpointInterval: checkpointInterval)
            .run(at: sourceFrame, mode: .debug)
        self.init(result: result, breakpoints: breakpoints, watches: watches)
    }

    /// Current debugger step, if the trace is non-empty.
    public var currentStep: LottieVMDebugStep? {
        step(at: currentIndex)
    }

    /// Advances to the next trace boundary.
    @discardableResult
    public mutating func stepInto() -> LottieVMDebugStep? {
        move(to: currentIndex + 1)
    }

    /// Advances past the current scoped operation, preserving its child trace in the result.
    @discardableResult
    public mutating func stepOver() -> LottieVMDebugStep? {
        guard let end = scopeEnd(startingAt: currentIndex) else {
            return stepInto()
        }
        return move(to: min(end + 1, result.trace.count - 1))
    }

    /// Advances to the boundary after the containing scoped operation.
    @discardableResult
    public mutating func stepOut() -> LottieVMDebugStep? {
        guard let scopeStart = activeScopeStart(containing: currentIndex),
              let end = scopeEnd(startingAt: scopeStart)
        else {
            return nil
        }
        return move(to: min(end + 1, result.trace.count - 1))
    }

    /// Moves back to the previous trace boundary.
    @discardableResult
    public mutating func stepBack() -> LottieVMDebugStep? {
        guard currentIndex > 0 else { return nil }
        return move(to: currentIndex - 1)
    }

    /// Continues until the next configured breakpoint or the final trace record.
    @discardableResult
    public mutating func continueToBreakpoint() -> LottieVMDebugStep? {
        guard !breakpoints.isEmpty else { return currentStep }
        guard !result.trace.isEmpty else { return nil }

        for index in (currentIndex + 1) ..< result.trace.count {
            let record = result.trace[index]
            if !matchingBreakpoints(for: record).isEmpty {
                return move(to: index)
            }
        }
        return move(to: result.trace.count - 1)
    }

    /// Continues until the next temporary breakpoint without replacing stored breakpoints.
    @discardableResult
    public mutating func continueToBreakpoint(_ temporaryBreakpoints: [LottieVMBreakpoint]) -> LottieVMDebugStep? {
        let storedBreakpoints = breakpoints
        breakpoints = temporaryBreakpoints
        defer { breakpoints = storedBreakpoints }
        return continueToBreakpoint()
    }

    private mutating func move(to index: Int) -> LottieVMDebugStep? {
        guard result.trace.indices.contains(index) else { return nil }
        currentIndex = index
        return currentStep
    }

    private func step(at index: Int) -> LottieVMDebugStep? {
        guard result.trace.indices.contains(index) else { return nil }
        let record = result.trace[index]
        return LottieVMDebugStep(
            record: record,
            sourcePath: record.sourcePath,
            jsonPath: record.jsonPath,
            sourceRange: record.sourceRange,
            stateSummary: LottieVMDebugStateSummary(state: record.state),
            emittedOutput: emittedOutput(for: record),
            watchValues: watchValues(for: record),
            hitBreakpoints: matchingBreakpoints(for: record),
            replayCheckpoint: result.checkpoint(beforeOrAt: record.step)
        )
    }

    private func emittedOutput(for record: LottieVMTraceRecord) -> LottieVMDebugOutput? {
        guard let renderNodeID = record.renderNodeID else { return nil }
        return LottieVMDebugOutput(
            renderNodeID: renderNodeID,
            label: record.instruction.label,
            values: record.evaluatedValues
        )
    }

    private func watchValues(for record: LottieVMTraceRecord) -> [LottieVMWatchValue] {
        watches.compactMap { watch in
            value(for: watch, record: record).map {
                LottieVMWatchValue(watch: watch, values: $0)
            }
        }
    }

    private func value(for watch: LottieVMWatch, record: LottieVMTraceRecord) -> [String: String]? {
        switch watch {
        case .transform:
            var values = ["stack": record.state.transformStack.joined(separator: " | ")]
            copy("matrix", from: record, into: &values)
            copy("position", from: record, into: &values)
            copy("rotationZ", from: record, into: &values)
            return values.isMeaningful ? values : nil
        case .opacity:
            var values = ["stack": record.state.opacityStack.joined(separator: " | ")]
            copy("opacity", from: record, into: &values)
            return values.isMeaningful ? values : nil
        case let .sampledProperty(key):
            guard let value = record.evaluatedValues[key] else { return nil }
            return [key: value]
        case .styleState:
            let values = [
                "stack": record.state.styleStack.joined(separator: " | "),
                "instruction": record.instruction.kind.rawValue,
            ]
            guard !record.state.styleStack.isEmpty
                || record.instruction.kind == .pushStyle
                || record.instruction.kind == .popStyle
            else { return nil }
            return values
        case .renderNodeEmission:
            guard let renderNodeID = record.renderNodeID else { return nil }
            return [
                "id": renderNodeID.description,
                "label": record.instruction.label,
            ].merging(record.evaluatedValues) { current, _ in current }
        }
    }

    private func copy(_ key: String, from record: LottieVMTraceRecord, into values: inout [String: String]) {
        if let value = record.evaluatedValues[key] {
            values[key] = value
        }
    }

    private func matchingBreakpoints(for record: LottieVMTraceRecord) -> [LottieVMBreakpoint] {
        breakpoints.filter { breakpoint in
            matches(breakpoint, record: record)
        }
    }

    private func matches(_ breakpoint: LottieVMBreakpoint, record: LottieVMTraceRecord) -> Bool {
        switch breakpoint {
        case let .sourcePath(path):
            record.sourcePath == path
        case let .sourcePathPrefix(prefix):
            record.sourcePath == prefix || record.sourcePath.hasPrefix("\(prefix) >")
        case let .jsonPath(path):
            record.jsonPath == path
        case let .layerName(name):
            isLayerBoundary(record) && record.instruction.label == name
        case let .layerIndex(index):
            isLayerBoundary(record) && record.evaluatedValues["layerIndex"] == String(index)
        case let .shapePath(path):
            record.sourcePath == path || record.sourcePath.hasPrefix("\(path) >")
        case let .instruction(kind):
            record.instruction.kind == kind
        case let .frame(frame):
            record.state.frameClock == frame
        }
    }

    private func scopeEnd(startingAt index: Int) -> Int? {
        guard result.trace.indices.contains(index),
              let closing = closingKind(for: result.trace[index].instruction.kind)
        else { return nil }

        var depth = 0
        let opening = result.trace[index].instruction.kind
        for candidate in (index + 1) ..< result.trace.count {
            let kind = result.trace[candidate].instruction.kind
            if kind == opening {
                depth += 1
            } else if kind == closing {
                if depth == 0 {
                    return candidate
                }
                depth -= 1
            }
        }
        return nil
    }

    private func activeScopeStart(containing index: Int) -> Int? {
        guard result.trace.indices.contains(index) else { return nil }
        var stack: [(index: Int, closing: LottieVMInstruction.Kind)] = []

        for candidate in 0 ... index {
            let kind = result.trace[candidate].instruction.kind
            if let closing = closingKind(for: kind) {
                stack.append((candidate, closing))
            } else if stack.last?.closing == kind {
                stack.removeLast()
            }
        }
        return stack.last?.index
    }

    private func closingKind(for kind: LottieVMInstruction.Kind) -> LottieVMInstruction.Kind? {
        switch kind {
        case .enterComposition:
            .leaveComposition
        case .enterLayer:
            .leaveLayer
        case .enterGroup:
            .leaveGroup
        case .pushStyle:
            .popStyle
        case .enterMatte:
            .leaveMatte
        case .enterPrecomposition:
            .leavePrecomposition
        case .leaveComposition,
             .leaveLayer,
             .evaluateLocalFrame,
             .evaluateTransform,
             .leaveGroup,
             .popStyle,
             .applyModifier,
             .leaveMatte,
             .leavePrecomposition,
             .emitRenderNode,
             .semanticDecision,
             .skipLayer:
            nil
        }
    }

    private func isLayerBoundary(_ record: LottieVMTraceRecord) -> Bool {
        switch record.instruction.kind {
        case .enterLayer, .leaveLayer, .skipLayer:
            true
        case .enterComposition,
             .leaveComposition,
             .evaluateLocalFrame,
             .evaluateTransform,
             .enterGroup,
             .leaveGroup,
             .pushStyle,
             .popStyle,
             .applyModifier,
             .enterMatte,
             .leaveMatte,
             .enterPrecomposition,
             .leavePrecomposition,
             .emitRenderNode,
             .semanticDecision:
            false
        }
    }
}

private extension [String: String] {
    var isMeaningful: Bool {
        values.contains { !$0.isEmpty }
    }
}
