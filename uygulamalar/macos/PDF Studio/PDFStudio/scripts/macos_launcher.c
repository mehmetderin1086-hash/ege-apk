#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void) {
    char executable_path[PATH_MAX];
    uint32_t size = sizeof(executable_path);

    if (_NSGetExecutablePath(executable_path, &size) != 0) {
        return 1;
    }

    char resolved_path[PATH_MAX];
    if (realpath(executable_path, resolved_path) == NULL) {
        return 1;
    }

    char *macos_component = strstr(resolved_path, "/Contents/MacOS/");
    if (macos_component == NULL) {
        return 1;
    }
    *macos_component = '\0';

    char launch_script[PATH_MAX];
    int written = snprintf(
        launch_script,
        sizeof(launch_script),
        "%s/Contents/Resources/launch.sh",
        resolved_path
    );
    if (written < 0 || (size_t)written >= sizeof(launch_script)) {
        return 1;
    }

    pid_t child = fork();
    if (child < 0) {
        return 1;
    }
    if (child > 0) {
        return 0;
    }

    (void)setsid();
    execl("/bin/zsh", "zsh", launch_script, (char *)NULL);
    _exit(127);
}
