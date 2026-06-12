$ErrorActionPreference = "Stop"

$packageRoot = Join-Path ".build" "ci/model-only"

if (Test-Path $packageRoot) {
    Remove-Item -Recurse -Force $packageRoot
}

New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Sources") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "Tests") | Out-Null

Copy-Item -Recurse "Sources/LottieModel" (Join-Path $packageRoot "Sources/LottieModel")
Copy-Item -Recurse "Tests/LottieModelTests" (Join-Path $packageRoot "Tests/LottieModelTests")
Copy-Item -Recurse "Tests/Fixtures" (Join-Path $packageRoot "Tests/Fixtures")
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "docs") | Out-Null
Copy-Item -Recurse "docs/lottie-format" (Join-Path $packageRoot "docs/lottie-format")

$manifest = @'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PureLottieModelOnly",
    products: [
        .library(name: "LottieModel", targets: ["LottieModel"]),
    ],
    targets: [
        .target(name: "LottieModel"),
        .testTarget(
            name: "LottieModelTests",
            dependencies: ["LottieModel"]
        ),
    ]
)
'@

Set-Content -Path (Join-Path $packageRoot "Package.swift") -Value $manifest -Encoding utf8NoBOM
Write-Host "Generated model-only package at $packageRoot"
