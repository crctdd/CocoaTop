#import <Foundation/Foundation.h>
#import <sys/sysctl.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^RHCommandCompletion)(NSString * _Nullable stdoutString,
                                   NSString * _Nullable stderrString,
                                   NSInteger exitCode);

@interface RootHelperManager : NSObject
+ (instancetype)sharedManager;
/// Requires a root-owned, non-group/world-writable setuid helper installed by deb.
- (BOOL)startHelperWithPath:(NSString *)helperPath error:(NSError * _Nullable * _Nullable)outError;
/// Completion runs on the private serial I/O queue, never the main queue.
/// Only getprocs is supported; a response or failure arrives within 5 seconds.
- (void)sendCommand:(NSString *)command completion:(RHCommandCompletion)completion;
/// An owned, immutable snapshot. Never exposes a mapping that cleanup can unmap.
- (nullable NSData *)processSnapshotWithError:(NSError * _Nullable * _Nullable)error;
/// SIGTERM/SIGKILL only; checks identity against the last successful refresh snapshot.
/// Returns POSIX errors (including ESTALE/ESRCH); never retries an uncertain signal RPC.
- (BOOL)terminateProcess:(pid_t)pid signal:(int)signal error:(NSError * _Nullable * _Nullable)error;
- (void)stopHelper;
@end

NS_ASSUME_NONNULL_END
