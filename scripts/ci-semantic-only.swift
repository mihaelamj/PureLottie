#!/usr/bin/env swift
//
//  ci-semantic-only.swift
//  PureLottie
//

import Foundation

let fileManager = FileManager.default
let repositoryRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let packageRoot = repositoryRoot
    .appendingPathComponent(".build", isDirectory: true)
    .appendingPathComponent("ci", isDirectory: true)
    .appendingPathComponent("semantic-only", isDirectory: true)

func recreateDirectory(_ url: URL) throws {
    if fileManager.fileExists(atPath: url.path) {
        try fileManager.removeItem(at: url)
    }
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
}

func copyDirectory(_ relativePath: String, to destinationRoot: URL) throws {
    let source = repositoryRoot.appendingPathComponent(relativePath, isDirectory: true)
    let destination = destinationRoot.appendingPathComponent(relativePath, isDirectory: true)
    try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try fileManager.copyItem(at: source, to: destination)
}

func copyFile(_ relativePath: String, to destinationRoot: URL) throws {
    let source = repositoryRoot.appendingPathComponent(relativePath)
    let destination = destinationRoot.appendingPathComponent(relativePath)
    try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try fileManager.copyItem(at: source, to: destination)
}

try recreateDirectory(packageRoot)

try copyDirectory("Sources/LottieModel", to: packageRoot)
try copyDirectory("Sources/LottieEvaluation", to: packageRoot)
try copyDirectory("Sources/LottieOracleDiff", to: packageRoot)
try copyDirectory("Tests/LottieModelTests", to: packageRoot)
try copyDirectory("Tests/LottieEvaluationTests", to: packageRoot)
try copyDirectory("Tests/LottieOracleDiffTests", to: packageRoot)
try copyDirectory("Tests/LottieImportTests", to: packageRoot)
try copyDirectory("Tests/Fixtures", to: packageRoot)
try copyDirectory("docs/lottie-format", to: packageRoot)
try copyDirectory("Tools/LottieAPNGDump", to: packageRoot)
try copyDirectory("Tools/LottieFrameDump", to: packageRoot)
try copyDirectory("Tools/LottieNumericOracleDiff", to: packageRoot)
try copyDirectory("Tools/LottieOracle/scripts", to: packageRoot)
try copyFile("Tools/LottieOracle/README.md", to: packageRoot)
try copyFile("Tools/LottieOracle/oracle-fixtures.json", to: packageRoot)
try copyFile("Tools/LottieOracle/oracle-tolerances.json", to: packageRoot)
try copyFile("Tools/LottieOracle/package-lock.json", to: packageRoot)
try copyFile("Tools/LottieOracle/package.json", to: packageRoot)
try copyFile("Tools/LottieOracle/reference-divergences.json", to: packageRoot)

let manifest = """
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PureLottieSemanticOnly",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LottieModel", targets: ["LottieModel"]),
        .library(name: "LottieEvaluation", targets: ["LottieEvaluation"]),
        .library(name: "LottieOracleDiff", targets: ["LottieOracleDiff"]),
    ],
    targets: [
        .target(name: "LottieModel"),
        .target(
            name: "LottieEvaluation",
            dependencies: ["LottieModel"]
        ),
        .target(
            name: "LottieOracleDiff",
            dependencies: [
                "LottieEvaluation",
                "LottieModel",
            ]
        ),
        .testTarget(
            name: "LottieModelTests",
            dependencies: ["LottieModel"]
        ),
        .testTarget(
            name: "LottieEvaluationTests",
            dependencies: [
                "LottieEvaluation",
                "LottieModel",
            ]
        ),
        .testTarget(
            name: "LottieOracleDiffTests",
            dependencies: ["LottieOracleDiff"]
        ),
    ]
)
"""

try manifest.write(
    to: packageRoot.appendingPathComponent("Package.swift"),
    atomically: true,
    encoding: .utf8
)

print("Generated semantic-only package at \(packageRoot.path)")
