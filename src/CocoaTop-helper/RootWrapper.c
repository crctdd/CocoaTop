#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <fcntl.h>
#include <errno.h>
#include <stdint.h>
#include <grp.h>
#include <signal.h>
#include <limits.h>

#define CT_MAX_SHM (256U * 1024U * 1024U)

static int sort_procs_by_pid(const void *a, const void *b) {
    pid_t x = ((const struct kinfo_proc *)a)->kp_proc.p_pid;
    pid_t y = ((const struct kinfo_proc *)b)->kp_proc.p_pid;
    return (x > y) - (x < y);
}

/* Decimal fields only: no signs, whitespace, groups or trailing bytes. */
static int parse_number(const char **cursor, unsigned long long limit,
                        char delimiter, unsigned long long *value) {
    const char *p = *cursor;
    unsigned long long n = 0;
    if (*p < '0' || *p > '9') return 0;
    do {
        unsigned digit = (unsigned)(*p++ - '0');
        if (n > limit / 10 || (n == limit / 10 && digit > limit % 10)) return 0;
        n = n * 10 + digit;
    } while (*p >= '0' && *p <= '9');
    if (*p != delimiter) return 0;
    *cursor = p + 1;
    *value = n;
    return 1;
}

static int signal_process(const char *line, pid_t guiPID) {
    const char *p = line + strlen("signal ");
    unsigned long long pid, sig, sec, usec;
    if (!parse_number(&p, INT_MAX, ' ', &pid) ||
        !parse_number(&p, INT_MAX, ' ', &sig) ||
        !parse_number(&p, LLONG_MAX, ' ', &sec) ||
        !parse_number(&p, 999999, '\n', &usec) || *p || pid <= 1 ||
        (sig != SIGTERM && sig != SIGKILL) || !sec)
        return EINVAL;
    if ((pid_t)pid == getpid() || (pid_t)pid == guiPID || (pid_t)pid == getppid())
        return EPERM;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, (int)pid };
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    if (sysctl(mib, 4, &info, &size, NULL, 0)) return errno;
    if (!size) return ESRCH;
    if (size != sizeof(info) || info.kp_proc.p_pid != (pid_t)pid) return EIO;
    if ((unsigned long long)info.kp_proc.p_starttime.tv_sec != sec ||
        (unsigned long long)info.kp_proc.p_starttime.tv_usec != usec)
        return ESTALE;
    /* This reduces PID reuse risk; Darwin kill + sysctl is not atomic. */
    return kill((pid_t)pid, (int)sig) ? errno : 0;
}

int main(int argc, char *argv[]) {
    /* The package must install this restricted helper root:wheel, mode 4755.
       No persona APIs, shell commands, arbitrary paths or native prefs writes. */
    if (argc != 3 || (getuid() != 501 && getuid() != 0) || geteuid() != 0)
        return EXIT_FAILURE;
    char *end = NULL;
    errno = 0;
    unsigned long long requested = strtoull(argv[2], &end, 10);
    if (errno || argv[2][0] < '0' || argv[2][0] > '9' || !end || *end ||
        requested < sizeof(struct kinfo_proc) || requested > CT_MAX_SHM ||
        requested % sizeof(struct kinfo_proc) != 0 ||
        strncmp(argv[1], "/ct_", 4) || strlen(argv[1]) > 30 || strchr(argv[1] + 1, '/'))
        return EXIT_FAILURE;
    size_t capacity = (size_t)requested;
    int fd = shm_open(argv[1], O_RDWR, 0);
    if (fd < 0) return EXIT_FAILURE;
    struct stat st;
    if (fstat(fd, &st) || st.st_uid != getuid() ||
        (st.st_mode & 0777) != 0600 || st.st_size != (off_t)capacity) {
        close(fd);
        return EXIT_FAILURE;
    }
    struct kinfo_proc *kp = mmap(NULL, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if (kp == MAP_FAILED) return EXIT_FAILURE;
    /* Retain the caller's real UID so the mobile parent can signal/reap us.
       Root sysctl access only needs the effective UID; never make real UID 0. */
    if (setgroups(0, NULL) || setegid(0) || seteuid(0)) {
        munmap(kp, capacity);
        return EXIT_FAILURE;
    }
    const pid_t guiPID = getppid();
    puts("READY 1");
    fflush(stdout);
    char line[64];
    for (;;) {
        /* Drain exactly one bounded frame, including NUL/overlong input. */
        size_t used = 0;
        int c, invalid = 0;
        while ((c = getchar()) != EOF && c != '\n') {
            if (!c || used >= sizeof(line) - 2) invalid = 1;
            else line[used++] = (char)c;
        }
        if (c == EOF) break;
        line[used++] = '\n';
        line[used] = 0;
        if (invalid) {
            puts("-1");
        } else if (!strcmp(line, "quit\n")) {
            break;
        } else if (!strncmp(line, "signal ", 7)) {
            printf("SIGNAL %d\n", signal_process(line, guiPID));
        } else if (strcmp(line, "getprocs\n")) {
            puts("-1");
        } else {
            int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
            size_t size = capacity;
            if (sysctl(mib, 4, kp, &size, NULL, 0) || size > capacity ||
                size % sizeof(*kp)) {
                puts("-1");
            } else {
                size_t count = size / sizeof(*kp);
                qsort(kp, count, sizeof(*kp), sort_procs_by_pid);
                printf("%zu\n", count);
            }
        }
        if (fflush(stdout)) break;
    }
    munmap(kp, capacity);
    return EXIT_SUCCESS;
}
