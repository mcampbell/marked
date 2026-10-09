import Foundation

public enum ImageStamp {
    /// Appends ?v=<mtime ms> to each local double-quoted <img src>; mtime(path) nil leaves src as is. W7 stub.
    public static func apply(_ html: String, shell: URL, mtime: (String) -> Double?) -> String {
        html
    }
}
