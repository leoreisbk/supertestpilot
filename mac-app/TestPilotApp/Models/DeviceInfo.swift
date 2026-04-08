import Foundation

enum DeviceType {
    case simulator, physical, androidEmulator, androidDevice
}

struct DeviceInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let type: DeviceType

    var isPhysical: Bool {
        type == .physical || type == .androidDevice
    }

    var displayName: String {
        switch type {
        case .simulator:       return "\(name) (Simulator)"
        case .physical:        return "\(name) (Device)"
        case .androidEmulator: return "\(name) (Emulator)"
        case .androidDevice:   return "\(name) (Device)"
        }
    }
}
