import Foundation

    /// Trims leading and trailing whitespace from an optional device name.
    /// Returns an empty string if input is nil.
func sanitizeDeviceName(_ name: String?) -> String {
    return name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}
