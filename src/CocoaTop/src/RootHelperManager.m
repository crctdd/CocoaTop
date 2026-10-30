#import "RootHelperManager.h"
#import <spawn.h>
#import <sys/stat.h>
#import <sys/mman.h>
#import <sys/socket.h>
#import <sys/wait.h>
#import <poll.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <signal.h>
#import <time.h>
#import <stdint.h>
#import <stdlib.h>
#import <stdio.h>
#import <string.h>
#import <limits.h>

#define CT_MAX_SHM (256U * 1024U * 1024U)
static void *CTHelperQueueKey = &CTHelperQueueKey;
static NSError *CTHelperError(int code) {
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}
static int64_t CTMonotonicMS(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

@interface RootHelperManager () {
    dispatch_queue_t _ioQueue;
    dispatch_source_t _exitSource;
    pid_t _helperPID;
    int _socketFD;
    void *_mapping;
    size_t _capacity;
    NSData *_lastSnapshot;
}
@end

@implementation RootHelperManager
+ (instancetype)sharedManager {
    static RootHelperManager *manager;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ manager = [self new]; });
    return manager;
}
- (instancetype)init {
    if ((self = [super init])) {
        _socketFD = -1;
        _ioQueue = dispatch_queue_create("com.crctdd.cocoatop.helper", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_ioQueue, CTHelperQueueKey, (__bridge void *)self, NULL);
    }
    return self;
}
- (void)onQueue:(dispatch_block_t)block {
    if (dispatch_get_specific(CTHelperQueueKey) == (__bridge void *)self) block();
    else dispatch_sync(_ioQueue, block);
}
- (void)cleanup {
    if (_exitSource) { dispatch_source_cancel(_exitSource); _exitSource = nil; }
    if (_socketFD >= 0) { close(_socketFD); _socketFD = -1; }
    if (_helperPID > 0) {
        /* Keep ownership of the child until reaped: no stale PID can be killed. */
        kill(_helperPID, SIGKILL);
        while (waitpid(_helperPID, NULL, 0) < 0 && errno == EINTR) {}
        _helperPID = 0;
    }
    if (_mapping) { munmap(_mapping, _capacity); _mapping = NULL; }
    _capacity = 0;
    _lastSnapshot = nil;
}
- (NSString *)readLine {
    char line[128];
    size_t used = 0;
    int64_t deadline = CTMonotonicMS() + 5000;
    while (used < sizeof(line) - 1) {
        int64_t remaining = deadline - CTMonotonicMS();
        if (remaining <= 0) { errno = ETIMEDOUT; return nil; }
        struct pollfd pfd = { _socketFD, POLLIN, 0 };
        int ready = poll(&pfd, 1, (int)remaining);
        if (ready < 0 && errno == EINTR) continue;
        if (ready <= 0) { if (!ready) errno = ETIMEDOUT; return nil; }
        ssize_t n = read(_socketFD, line + used, 1);
        if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
        if (n <= 0) { if (!n) errno = EPIPE; return nil; }
        if (line[used] == '\n') {
            line[used] = 0;
            NSString *result = [NSString stringWithUTF8String:line];
            if (!result) errno = EPROTO;
            return result;
        }
        used++;
    }
    errno = EOVERFLOW;
    return nil;
}
- (BOOL)startHelperWithPath:(NSString *)helperPath error:(NSError **)outError {
    __block BOOL success = NO;
    __block int failure = 0;
    [self onQueue:^{
        if (self->_helperPID > 0) { success = YES; return; }
        int shmFD = -1, sockets[2] = {-1, -1};
        NSString *name = nil;
        BOOL ownsSHM = NO;
        posix_spawn_file_actions_t actions;
        posix_spawnattr_t attr;
        BOOL actionsReady = NO, attrReady = NO;
        struct stat st;
        int maxproc = 0;
        int mib[2] = { CTL_KERN, KERN_MAXPROC };
        size_t len = sizeof(maxproc);
        do {
            if (stat(helperPath.fileSystemRepresentation, &st)) { failure = errno; break; }
            if (!S_ISREG(st.st_mode) || st.st_uid != 0 || (st.st_mode & 0022) ||
                !(st.st_mode & S_IXUSR) || (geteuid() != 0 && !(st.st_mode & S_ISUID))) {
                failure = EPERM; break;
            }
            if (sysctl(mib, 2, &maxproc, &len, NULL, 0)) { failure = errno; break; }
            if (maxproc <= 0 || (size_t)maxproc > CT_MAX_SHM / sizeof(struct kinfo_proc)) {
                failure = EOVERFLOW; break;
            }
            self->_capacity = (size_t)maxproc * sizeof(struct kinfo_proc);
            /* Darwin shm names are short; never infer the name from getppid(). */
            name = [@"/ct_" stringByAppendingString:
                    [[[NSUUID UUID] UUIDString] substringToIndex:24]];
            shmFD = shm_open(name.UTF8String, O_CREAT | O_EXCL | O_RDWR, 0600);
            if (shmFD < 0) { failure = errno; break; }
            ownsSHM = YES;
            if (fchmod(shmFD, 0600) || ftruncate(shmFD, (off_t)self->_capacity)) {
                failure = errno; break;
            }
            fcntl(shmFD, F_SETFD, FD_CLOEXEC);
            void *mapping = mmap(NULL, self->_capacity, PROT_READ, MAP_SHARED, shmFD, 0);
            if (mapping == MAP_FAILED) { failure = errno; break; }
            self->_mapping = mapping;
            if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets)) { failure = errno; break; }
            int one = 1;
            if (setsockopt(sockets[0], SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one))) {
                failure = errno; break;
            }
            fcntl(sockets[0], F_SETFD, FD_CLOEXEC);
            fcntl(sockets[1], F_SETFD, FD_CLOEXEC);
            /* File actions must not accidentally close a remapped stdio FD. */
            for (int i = 0; i < 2; i++) {
                if (sockets[i] <= STDERR_FILENO) {
                    int replacement = fcntl(sockets[i], F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
                    if (replacement < 0) { failure = errno; break; }
                    close(sockets[i]); sockets[i] = replacement;
                }
            }
            if (failure) break;
            failure = posix_spawnattr_init(&attr);
            if (failure) break;
            attrReady = YES;
            failure = posix_spawnattr_setflags(&attr, POSIX_SPAWN_CLOEXEC_DEFAULT);
            if (failure) break;
            failure = posix_spawn_file_actions_init(&actions);
            if (failure) break;
            actionsReady = YES;
            if ((failure = posix_spawn_file_actions_adddup2(&actions, sockets[1], STDIN_FILENO)) ||
                (failure = posix_spawn_file_actions_adddup2(&actions, sockets[1], STDOUT_FILENO)) ||
                (failure = posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)) ||
                (failure = posix_spawn_file_actions_addclose(&actions, sockets[0])) ||
                (failure = posix_spawn_file_actions_addclose(&actions, sockets[1]))) break;
            char sizeArg[32];
            snprintf(sizeArg, sizeof(sizeArg), "%zu", self->_capacity);
            char *args[] = { (char *)helperPath.fileSystemRepresentation, (char *)name.UTF8String, sizeArg, NULL };
            char *env[] = { "PATH=/usr/bin:/bin", "LANG=C", NULL };
            failure = posix_spawn(&self->_helperPID, helperPath.fileSystemRepresentation, &actions, &attr, args, env);
            if (failure) { self->_helperPID = 0; break; }
            close(sockets[1]); sockets[1] = -1;
            self->_socketFD = sockets[0]; sockets[0] = -1;
            NSString *greeting = [self readLine];
            if (![greeting isEqualToString:@"READY 1"]) {
                failure = greeting ? EPROTO : errno; break;
            }
            pid_t watchedPID = self->_helperPID;
            self->_exitSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, watchedPID, DISPATCH_PROC_EXIT, self->_ioQueue);
            if (!self->_exitSource) { failure = ENOMEM; break; }
            dispatch_source_set_event_handler(self->_exitSource, ^{
                if (self->_helperPID == watchedPID) [self cleanup];
            });
            dispatch_resume(self->_exitSource);
            success = YES;
        } while (0);
        if (actionsReady) posix_spawn_file_actions_destroy(&actions);
        if (attrReady) posix_spawnattr_destroy(&attr);
        for (int i = 0; i < 2; i++) if (sockets[i] >= 0) close(sockets[i]);
        if (shmFD >= 0) close(shmFD);
        /* After READY both sides hold mappings; remove the name immediately. */
        if (ownsSHM) shm_unlink(name.UTF8String);
        if (!success) [self cleanup];
    }];
    if (!success && outError) *outError = CTHelperError(failure ?: EIO);
    return success;
}
- (NSString *)requestLine:(const char *)command {
    if (_socketFD < 0) { errno = ENOTCONN; return nil; }
    size_t length = strlen(command);
    size_t sent = 0;
    while (sent < length) {
        ssize_t n = write(_socketFD, command + sent, length - sent);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) {
            int error = n ? errno : EPIPE;
            [self cleanup]; errno = error; return nil;
        }
        sent += (size_t)n;
    }
    NSString *line = [self readLine];
    if (!line) { int error = errno; [self cleanup]; errno = error; }
    return line;
}
- (NSString *)requestProcessList {
    return [self requestLine:"getprocs\n"];
}
- (void)sendCommand:(NSString *)command completion:(RHCommandCompletion)completion {
    dispatch_async(_ioQueue, ^{
        if (![command isEqualToString:@"getprocs"] && ![command isEqualToString:@"getprocs\n"]) {
            completion(nil, @"Unsupported helper command", -EINVAL); return;
        }
        NSString *line = [self requestProcessList];
        int error = errno;
        completion(line, line ? nil : [NSString stringWithUTF8String:strerror(error)], line ? 0 : -error);
    });
}
- (NSData *)processSnapshotWithError:(NSError **)outError {
    __block NSData *snapshot = nil;
    __block int failure = 0;
    [self onQueue:^{
        NSString *line = [self requestProcessList];
        if (!line) { failure = errno; return; }
        if ([line isEqualToString:@"-1"]) { failure = EIO; return; }
        const char *text = line.UTF8String;
        char *end = NULL;
        errno = 0;
        unsigned long long count = strtoull(text, &end, 10);
        if (errno || !text[0] || text[0] < '0' || text[0] > '9' || *end ||
            count > self->_capacity / sizeof(struct kinfo_proc)) {
            failure = EPROTO; [self cleanup]; return;
        }
        snapshot = [NSData dataWithBytes:self->_mapping length:(NSUInteger)count * sizeof(struct kinfo_proc)];
        self->_lastSnapshot = snapshot;
    }];
    if (!snapshot && outError) *outError = CTHelperError(failure ?: EIO);
    return snapshot;
}
- (BOOL)terminateProcess:(pid_t)pid signal:(int)sig error:(NSError **)outError {
    __block int failure = 0;
    [self onQueue:^{
        if (pid <= 1 || (sig != SIGTERM && sig != SIGKILL)) { failure = EINVAL; return; }
        if (pid == getpid() || pid == self->_helperPID) { failure = EPERM; return; }
        if (self->_socketFD < 0) { failure = ENOTCONN; return; }
        const struct kinfo_proc *items = self->_lastSnapshot.bytes;
        NSUInteger count = self->_lastSnapshot.length / sizeof(*items);
        const struct kinfo_proc *target = NULL;
        for (NSUInteger i = 0; i < count; i++) {
            if (items[i].kp_proc.p_pid == pid) { target = &items[i]; break; }
        }
        if (!target) { failure = ESRCH; return; }
        long long sec = (long long)target->kp_proc.p_starttime.tv_sec;
        long usec = (long)target->kp_proc.p_starttime.tv_usec;
        if (sec <= 0 || usec < 0 || usec > 999999) { failure = ESTALE; return; }
        char command[64];
        int length = snprintf(command, sizeof(command), "signal %d %d %lld %ld\n",
                              (int)pid, sig, sec, usec);
        if (length < 0 || (size_t)length >= sizeof(command)) { failure = EOVERFLOW; return; }
        NSString *line = [self requestLine:command];
        if (!line) { failure = errno; return; }
        if (![line hasPrefix:@"SIGNAL "]) { failure = EPROTO; [self cleanup]; return; }
        const char *text = line.UTF8String + 7;
        char *end = NULL;
        errno = 0;
        unsigned long code = strtoul(text, &end, 10);
        if (errno || text[0] < '0' || text[0] > '9' || *end || code > INT_MAX) {
            failure = EPROTO; [self cleanup]; return;
        }
        failure = (int)code;
    }];
    if (failure && outError) *outError = CTHelperError(failure);
    return failure == 0;
}
- (void)stopHelper {
    [self onQueue:^{ [self cleanup]; }];
}
@end
