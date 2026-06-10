#pragma once
#include <sys/types.h>

pid_t pty_spawn(const char *slavePath,
                const char *shell,
                char **argv,
                char **envp,
                unsigned short rows,
                unsigned short cols);
