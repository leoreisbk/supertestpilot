import Logging
import LoggingFormatAndPipe
import Foundation

public struct CustomLogHandler: LogHandler {
    public let formatter: LoggingFormatAndPipe.Formatter
    public let verboseFormatter: LoggingFormatAndPipe.Formatter
    public let pipe: LoggingFormatAndPipe.Pipe
    public var logLevel: Logger.Level = .debug
    
    private let logLevelInternal: Logger.Level
    private let verboseStream: TextOutputStream?
    private var prettyMetadata: String?
    
    public init(
        formatter: LoggingFormatAndPipe.Formatter,
        pipe: LoggingFormatAndPipe.Pipe,
        logLevel: Logger.Level = .info,
        verboseFile: URL
    ) {
        self.formatter = formatter
        self.verboseFormatter = BasicFormatter([.timestamp, .level, .message])
        self.pipe = pipe
        self.logLevelInternal = logLevel
        self.verboseStream = try? FileHandlerOutputStream(localFile: verboseFile)
    }

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    file: String, function: String, line: UInt) {
        let prettyMetadata = metadata?.isEmpty ?? true
            ? self.prettyMetadata
            : self.prettify(self.metadata.merging(metadata!, uniquingKeysWith: { _, new in new }))

        if var stream = self.verboseStream {
            let verboseFormattedMessage = self.verboseFormatter.processLog(level: level, message: message, prettyMetadata: prettyMetadata, file: file, function: function, line: line)
            stream.write("\(verboseFormattedMessage)\n")
        }
        
        if self.logLevelInternal <= level {
            let formattedMessage = self.formatter.processLog(level: level, message: message, prettyMetadata: prettyMetadata, file: file, function: function, line: line)
            self.pipe.handle(formattedMessage)
        }
    }

    public var metadata = Logger.Metadata() {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata)
        }
    }

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    private func prettify(_ metadata: Logger.Metadata) -> String? {
        return !metadata.isEmpty ? metadata.map { "\($0)=\($1)" }.joined(separator: " ") : nil
    }
}
