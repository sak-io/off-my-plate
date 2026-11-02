import Foundation
import OMPWeb

// omp-web-cli: reads a transcript on stdin (JSON request lines plus @capture/@expect directives, see
// TranscriptRunner), writes one response line per request on stdout. Failed @expect checks go to stderr
// and make the exit code 1. Used by the tests natively and by CI under wasmtime (byte comparison).

var input: [String] = []
while let line = readLine(strippingNewline: true) {
    input.append(line)
}
let session = FacadeSession()
let output = await TranscriptRunner.run(lines: input, session: session)
for response in output.responses {
    print(response)
}
for failure in output.failures {
    FileHandle.standardError.write(Data(("FAILED: " + failure + "\n").utf8))
}
exit(output.failures.isEmpty ? 0 : 1)
