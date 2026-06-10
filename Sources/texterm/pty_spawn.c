#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <stdlib.h>

// Forks and sets up a full PTY session in the child before exec'ing the shell.
// Returns child PID in the parent; the child replaces itself with the shell.
pid_t pty_spawn(const char *slavePath,
                const char *shell,
                char **argv,
                char **envp,
                unsigned short rows,
                unsigned short cols) {
    pid_t pid = fork();
    if (pid != 0) return pid;  // parent (or error: pid = -1)

    int slaveFD = open(slavePath, O_RDWR);
    if (slaveFD < 0) _exit(1);

    setsid();

    int dummy = 0;
    ioctl(slaveFD, TIOCSCTTY, &dummy);

    struct winsize ws = { .ws_row = rows, .ws_col = cols, .ws_xpixel = 0, .ws_ypixel = 0 };
    ioctl(slaveFD, TIOCSWINSZ, &ws);

    dup2(slaveFD, STDIN_FILENO);
    dup2(slaveFD, STDOUT_FILENO);
    dup2(slaveFD, STDERR_FILENO);

    for (int fd = 3; fd < 256; fd++) close(fd);

    execve(shell, argv, envp);
    _exit(127);
}
