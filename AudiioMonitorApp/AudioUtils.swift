import Foundation

func sanitizeDeviceName(_ name: String?) -> String {
    return name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
