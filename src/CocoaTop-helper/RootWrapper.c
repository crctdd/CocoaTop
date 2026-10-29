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

#define CT_MAX_SHM (256U * 1024U * 1024U)

static int sort_procs_by_pid(const void *a, const void *b) {
    pid_t x = ((const struct kinfo_proc *)a)->kp_proc.p_pid;
    pid_t y = ((const struct kinfo_proc *)b)->kp_proc.p_pid;
    return (x > y) - (x < y);
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
    puts("READY 1");
    fflush(stdout);
    char line[64];
    while (fgets(line, sizeof(line), stdin)) {
        if (!strcmp(line, "quit\n")) break;
        if (strcmp(line, "getprocs\n")) {
            /* One response per request, including invalid/overlong lines. */
            if (!strchr(line, '\n')) {
                int c;
                while ((c = getchar()) != '\n' && c != EOF) {}
            }
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
