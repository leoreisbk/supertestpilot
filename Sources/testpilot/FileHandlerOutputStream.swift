import Foundation

struct FileHandlerOutputStream: TextOutputStream {
    enum FileHandlerOutputStream: Error {
        case couldNotCreateFile
    }
    
    private let fileHandle: FileHandle
    let encoding: String.Encoding

    init(localFile url: URL, encoding: String.Encoding = .utf8) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil) else {
                throw FileHandlerOutputStream.couldNotCreateFile
            }
        }
        
        let fileHandle = try FileHandle(forWritingTo: url)
        fileHandle.seekToEndOfFile()
        self.fileHandle = fileHandle
        self.encoding = encoding
    }

    mutating func write(_ string: String) {
        if let data = string.data(using: encoding) {
            fileHandle.write(data)
        }
    }
}
