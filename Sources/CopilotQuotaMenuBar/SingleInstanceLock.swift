import Darwin
import Foundation

@MainActor
final class SingleInstanceLock {
    private static var fd: Int32?

    static func tryAcquire() -> Bool {
        // Best-effort lock; if it fails, we just exit quietly.
        let lockURL = FileManager.default.temporaryDirectory.appendingPathComponent(AppMetadata.lockFileName)
        let path = lockURL.path

        let newFd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard newFd >= 0 else { return true }
        guard flock(newFd, LOCK_EX | LOCK_NB) == 0 else {
            close(newFd)
            return false
        }

        fd = newFd
        return true
    }
}
