$ErrorActionPreference = "Stop"

$packageRoot = Join-Path ".build" "ci/semantic-only"

if (Test-Path $packageRoot) {
    Remove-Item -Recurse -Force $packageRoot
}

New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Sources") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Tests") | Out-Null

Copy-Item -Recurse "Sources/LottieModel" (Join-Path $packageRoot "Sources/LottieModel")
Copy-Item -Recurse "Sources/LottieEvaluation" (Join-Path $packageRoot "Sources/LottieEvaluation")
Copy-Item -Recurse "Sources/LottieOracleDiff" (Join-Path $packageRoot "Sources/LottieOracleDiff")
Copy-Item -Recurse "Tests/LottieModelTests" (Join-Path $packageRoot "Tests/LottieModelTests")
Copy-Item -Recurse "Tests/LottieEvaluationTests" (Join-Path $packageRoot "Tests/LottieEvaluationTests")
Copy-Item -Recurse "Tests/LottieOracleDiffTests" (Join-Path $packageRoot "Tests/LottieOracleDiffTests")
Copy-Item -Recurse "Tests/LottieImportTests" (Join-Path $packageRoot "Tests/LottieImportTests")
Copy-Item -Recurse "Tests/Fixtures" (Join-Path $packageRoot "Tests/Fixtures")
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "docs") | Out-Null
Copy-Item -Recurse "docs/lottie-format" (Join-Path $packageRoot "docs/lottie-format")
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Tools") | Out-Null
Copy-Item -Recurse "Tools/LottieAPNGDump" (Join-Path $packageRoot "Tools/LottieAPNGDump")
Copy-Item -Recurse "Tools/LottieFrameDump" (Join-Path $packageRoot "Tools/LottieFrameDump")
Copy-Item -Recurse "Tools/LottieNumericOracleDiff" (Join-Path $packageRoot "Tools/LottieNumericOracleDiff")
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Tools/LottieOracle") | Out-Null
Copy-Item -Recurse "Tools/LottieOracle/scripts" (Join-Path $packageRoot "Tools/LottieOracle/scripts")
Copy-Item "Tools/LottieOracle/README.md" (Join-Path $packageRoot "Tools/LottieOracle/README.md")
Copy-Item "Tools/LottieOracle/oracle-fixtures.json" (Join-Path $packageRoot "Tools/LottieOracle/oracle-fixtures.json")
Copy-Item "Tools/LottieOracle/oracle-tolerances.json" (Join-Path $packageRoot "Tools/LottieOracle/oracle-tolerances.json")
Copy-Item "Tools/LottieOracle/package-lock.json" (Join-Path $packageRoot "Tools/LottieOracle/package-lock.json")
Copy-Item "Tools/LottieOracle/package.json" (Join-Path $packageRoot "Tools/LottieOracle/package.json")
Copy-Item "Tools/LottieOracle/reference-divergences.json" (Join-Path $packageRoot "Tools/LottieOracle/reference-divergences.json")
Copy-Item "Tools/LottieOracle/witness-corpus.json" (Join-Path $packageRoot "Tools/LottieOracle/witness-corpus.json")

$manifest = @'
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
'@

Set-Content -Path (Join-Path $packageRoot "Package.swift") -Value $manifest -Encoding utf8NoBOM
Write-Host "Generated semantic-only package at $packageRoot"
