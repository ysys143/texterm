import Darwin
import Foundation

class PTY {
    private(set) var masterFD: Int32 = -1
    private var childPID: pid_t = -1

    var onOutput: ((Data) -> Void)?
    var onExit: (() -> Void)?

    func start(shell: String = "/bin/zsh") throws {
        masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        guard masterFD >= 0 else { throw PTYError.openFailed }
        grantpt(masterFD)
        unlockpt(masterFD)

        let slavePath = String(cString: ptsname(masterFD))

        // Build env and argv as C strings in Swift before handing off to C.
        var envMap = ProcessInfo.processInfo.environment
        envMap["TERM"]      = "xterm-256color"
        envMap["COLORTERM"] = "truecolor"
        let envStrings = envMap.map { "\($0.key)=\($0.value)" }

        // strdup copies into C-heap; freed in parent after pty_spawn returns.
        var envCStrs: [UnsafeMutablePointer<CChar>?] = envStrings.map { strdup($0) } + [nil]
        let shellDup = strdup(shell)
        var argv: [UnsafeMutablePointer<CChar>?] = [shellDup, nil]

        // pty_spawn() is a C function (pty_spawn.c) that calls fork() and exec().
        // Swift can't call fork() directly because the Swift runtime starts GCD
        // threads that make fork()-without-exec unsafe.
        childPID = argv.withUnsafeMutableBufferPointer { argBuf in
            envCStrs.withUnsafeMutableBufferPointer { envBuf in
                pty_spawn(slavePath, shellDup, argBuf.baseAddress, envBuf.baseAddress, 40, 220)
            }
        }

        envCStrs.compactMap({ $0 }).forEach { free($0) }
        free(shellDup)

        guard childPID > 0 else { throw PTYError.forkFailed }
        startReading()
    }

    private func startReading() {
        let fd = masterFD
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(fd, &buf, buf.count)
                guard n > 0 else {
                    DispatchQueue.main.async { self?.onExit?() }
                    return
                }
                let data = Data(buf[..<n])
                DispatchQueue.main.async { self?.onOutput?(data) }
            }
        }
    }

    func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        write(data)
    }

    func write(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes {
            guard let base = $0.baseAddress else { return }
            _ = Darwin.write(masterFD, base, data.count)
        }
    }

    func resize(cols: UInt16, rows: UInt16) {
        guard masterFD >= 0 else { return }
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        ioctl(masterFD, UInt(TIOCSWINSZ), &ws)
    }

    deinit {
        if childPID > 0 { kill(childPID, SIGTERM) }
        if masterFD >= 0 { Darwin.close(masterFD) }
    }
}

enum PTYError: Error {
    case openFailed, forkFailed
}
