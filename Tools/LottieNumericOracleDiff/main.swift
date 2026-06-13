import Foundation
import LottieOracleDiff

do {
    let code = try LottieNumericOracleDiffCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
    Foundation.exit(code)
} catch LottieNumericOracleDiffUsage.requested {
    print(LottieNumericOracleDiffUsage.requested.description)
    Foundation.exit(0)
} catch let error as LottieNumericOracleDiffUsage {
    fputs("\(error.description)\n", stderr)
    Foundation.exit(2)
} catch {
    fputs("\(error)\n", stderr)
    Foundation.exit(1)
}
