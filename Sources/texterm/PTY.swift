import Darwin
import Foundation

class PTY {
    private(set) var masterFD: Int32 = -1
    private var childPID: pid_t = -1

    var onOutput: ((Data) -> Void)?
    var onExit: (() -> Void)?

    // PTY output is coalesced: the reader thread appends every read() chunk to
    // `pending` and schedules a single main-thread flush per frame (~8ms). A busy
    // shell can fire dozens of reads per frame; without this each one would cost a
    // separate main.async + evaluateJavaScript, swamping the main thread on heavy
    // output (build logs, `cat` big files). Guarded by `pendingLock`.
    private let pendingLock = NSLock()
    private var pending = Data()
    private var flushScheduled = false
    private static let flushInterval = 0.008

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
        // Exec path is the real shell binary; argv[0] is "-zsh" (leading '-') so the
        // shell runs as a LOGIN shell and sources ~/.zprofile -- where Homebrew's
        // PATH (/opt/homebrew/bin, holding ffmpeg/node/etc.) is set. A non-login
        // shell skips .zprofile and those tools go missing. Matches Terminal.app.
        let shellPath = strdup(shell)
        let argv0 = strdup("-" + (shell as NSString).lastPathComponent)
        var argv: [UnsafeMutablePointer<CChar>?] = [argv0, nil]

        // Launched from Finder the app's cwd is "/", which the child would inherit;
        // start the shell in the home directory instead.
        FileManager.default.changeCurrentDirectoryPath(NSHomeDirectory())

        // pty_spawn() is a C function (pty_spawn.c) that calls fork() and exec().
        // Swift can't call fork() directly because the Swift runtime starts GCD
        // threads that make fork()-without-exec unsafe.
        childPID = argv.withUnsafeMutableBufferPointer { argBuf in
            envCStrs.withUnsafeMutableBufferPointer { envBuf in
                pty_spawn(slavePath, shellPath, argBuf.baseAddress, envBuf.baseAddress, 40, 220)
            }
        }

        envCStrs.compactMap({ $0 }).forEach { free($0) }
        free(shellPath)
        free(argv0)

        guard childPID > 0 else { throw PTYError.forkFailed }
        startReading()
    }

    private func startReading() {
        let fd = masterFD
        let pid = childPID
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(fd, &buf, buf.count)
                guard n > 0 else {
                    // EOF: the shell has exited. Reap it so it doesn't linger as a
                    // zombie, flush any buffered tail, then report the exit.
                    if pid > 0 { waitpid(pid, nil, 0) }
                    DispatchQueue.main.async { self?.flush(); self?.onExit?() }
                    return
                }
                guard let self = self else { return }
                self.pendingLock.lock()
                self.pending.append(contentsOf: buf[..<n])
                let needSchedule = !self.flushScheduled
                self.flushScheduled = true
                self.pendingLock.unlock()
                if needSchedule {
                    DispatchQueue.main.asyncAfter(deadline: .now() + PTY.flushInterval) { [weak self] in
                        self?.flush()
                    }
                }
            }
        }
    }

    // Drains the coalescing buffer and hands one combined chunk to the renderer.
    // Always runs on the main thread (onOutput calls into WebKit).
    private func flush() {
        pendingLock.lock()
        let data = pending
        pending.removeAll(keepingCapacity: true)
        flushScheduled = false
        pendingLock.unlock()
        if !data.isEmpty { onOutput?(data) }
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

    /// Kill the shell and close the master fd. Safe to call from the main thread:
    /// closing a PTY master blocks in the kernel while the read thread is still in
    /// read(), so the close is done on a background queue (otherwise window/pane
    /// close hangs). SIGHUP makes read() return EOF so the read thread exits.
    func stop() {
        PTY.teardown(childPID, masterFD)
        childPID = -1
        masterFD = -1
    }

    deinit { PTY.teardown(childPID, masterFD) }

    private static func teardown(_ pid: pid_t, _ fd: Int32) {
        guard fd >= 0 else { return }
        DispatchQueue.global(qos: .utility).async {
            if pid > 0 {
                kill(pid, SIGHUP)
                waitpid(pid, nil, 0)   // reap; no-op (ECHILD) if the reader already did
            }
            Darwin.close(fd)
        }
    }
}

enum PTYError: Error {
    case openFailed, forkFailed
}
