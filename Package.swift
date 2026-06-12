// swift-tools-version: 6.0
import PackageDescription

// PureLottie: a typed Lottie document model and an importer that maps it onto
// the PureLayer engine.
//
// Two strictly separated layers:
// - LottieModel decodes Lottie JSON (lottie-spec 1.0 subset) into faithful
//   typed values. It knows nothing about PureLayer and depends only on
//   Foundation's JSON decoding.
// - LottieImport walks the model and emits a PureLayer tree plus animations,
//   collecting every unsupported feature into an ImportReport instead of
//   rendering it silently wrong.
let package = Package(
    name: "PureLottie",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "LottieModel", targets: ["LottieModel"]),
        .library(name: "LottieEvaluation", targets: ["LottieEvaluation"]),
        .library(name: "LottieImport", targets: ["LottieImport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mihaelamj/PureLayer.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "LottieModel"
        ),
        .target(
            name: "LottieEvaluation",
            dependencies: ["LottieModel"]
        ),
        .target(
            name: "LottieImport",
            dependencies: [
                "LottieModel",
                .product(name: "PureLayer", package: "PureLayer"),
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
            name: "LottieImportTests",
            dependencies: [
                "LottieImport",
                .product(name: "PureLayer", package: "PureLayer"),
            ]
        ),
        .executableTarget(
            name: "LottieFrameDump",
            dependencies: [
                "LottieImport",
                .product(name: "PureLayer", package: "PureLayer"),
            ],
            path: "Tools/LottieFrameDump"
        ),
    ]
)
