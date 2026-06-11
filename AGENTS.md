# PureLottie

A typed Lottie document model (`LottieModel`) and an importer (`LottieImport`)
that maps it onto the [PureLayer](https://github.com/mihaelamj/PureLayer)
engine.

Non-negotiables for any change:

- `LottieModel` mirrors the Lottie format (lottie-spec 1.0 subset) faithfully
  and knows nothing about PureLayer. All semantic decisions live in
  `LottieImport`.
- The importer never renders silently wrong: a feature is either mapped
  correctly or recorded in the `ImportReport` with the layer/shape path where it
  was found. Extending the supported subset means moving a feature from the
  report to the mapping, with a test on both sides.
- Times in `LottieModel` are frames, exactly as in the file. The frame-to-second
  conversion happens once, in the importer.
- PureLottie depends on PureLayer (and PureDraw transitively) and never modifies
  them. No other dependencies.
- CI gates are not set up yet: PureLayer is a private dependency and the
  workflows need a deploy key before they can resolve it. Until then, run the
  full local gate before every commit:
  `swiftformat . --config .swiftformat && swiftlint --config .swiftlint.yml --strict && swift test`.
- Commits follow `<type>(<scope>): summary`.
