#import "CTPreferences.h"
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <stdlib.h>
#import <stdio.h>
#import <string.h>
#import <stdint.h>
#if defined(CT_ROOTHIDE) && CT_ROOTHIDE
#import <roothide.h>
#endif

static NSString *const CTDomain = @"com.crctdd.cocoatop";
@interface CTPreferences () {
    NSMutableDictionary *_registered;
    NSMutableDictionary *_pending;
    BOOL _resetPending;
    NSString *_preferencesPath;
    NSError *_lastError;
    NSDictionary *_diskCache;
    struct stat _cachedStat;
    BOOL _hasCachedStat;
}
@end
@implementation CTPreferences
+ (instancetype)standardUserDefaults {
    static CTPreferences *prefs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ prefs = [self new]; });
    return prefs;
}
- (instancetype)init {
    if ((self = [super init])) {
        _registered = [NSMutableDictionary dictionary];
        _pending = [NSMutableDictionary dictionary];
#if defined(CT_ROOTHIDE) && CT_ROOTHIDE
        NSString *path = jbroot(@"/var/mobile/Library/Preferences/com.crctdd.cocoatop.plist");
        /* Fail closed if path resolution fails or unexpectedly yields native storage. */
        NSString *normalized = [path stringByStandardizingPath];
        if (normalized.isAbsolutePath &&
            ![normalized hasPrefix:@"/var/mobile/"] &&
            ![normalized hasPrefix:@"/private/var/mobile/"])
            _preferencesPath = [normalized copy];
#else
        _preferencesPath = @"/var/jb/var/mobile/Library/Preferences/com.crctdd.cocoatop.plist";
#endif
        if (!_preferencesPath) _lastError = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
    }
    return self;
}
- (NSString *)preferencesPath { @synchronized(self) { return _preferencesPath; } }
- (NSError *)lastError { @synchronized(self) { return _lastError; } }
- (void)registerDefaults:(NSDictionary *)defaults {
    @synchronized(self) { [_registered addEntriesFromDictionary:defaults]; }
}
- (NSMutableDictionary *)readDisk:(NSError **)error {
    if (!_preferencesPath) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOENT userInfo:nil];
        return nil;
    }
    struct stat current;
    if (stat(_preferencesPath.fileSystemRepresentation, &current)) {
        if (errno == ENOENT) {
            _hasCachedStat = NO; _diskCache = nil;
            return [NSMutableDictionary dictionary];
        }
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return nil;
    }
    if (_hasCachedStat && _diskCache && current.st_dev == _cachedStat.st_dev &&
        current.st_ino == _cachedStat.st_ino && current.st_size == _cachedStat.st_size &&
        current.st_mtimespec.tv_sec == _cachedStat.st_mtimespec.tv_sec &&
        current.st_mtimespec.tv_nsec == _cachedStat.st_mtimespec.tv_nsec)
        return [_diskCache mutableCopy];
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:_preferencesPath options:0 error:&readError];
    if (!data) {
        if ([readError.domain isEqualToString:NSCocoaErrorDomain] && readError.code == NSFileReadNoSuchFileError)
            return [NSMutableDictionary dictionary];
        if (error) *error = readError;
        return nil;
    }
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&readError];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        if (error) *error = readError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError userInfo:nil];
        return nil;
    }
    _diskCache = [plist copy];
    _cachedStat = current;
    _hasCachedStat = YES;
    return [_diskCache mutableCopy];
}
- (NSDictionary *)dictionaryRepresentation {
    @synchronized(self) {
        NSError *error = nil;
        NSMutableDictionary *disk = _resetPending ? [NSMutableDictionary dictionary] : [self readDisk:&error];
        if (error) _lastError = error;
        NSMutableDictionary *result = [_registered mutableCopy];
        if (disk) [result addEntriesFromDictionary:disk];
        [_pending enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if (value == [NSNull null]) {
                [result removeObjectForKey:key];
                if (self->_registered[key]) result[key] = self->_registered[key];
            } else result[key] = value;
        }];
        return [result copy];
    }
}
- (id)objectForKey:(NSString *)key { return [self dictionaryRepresentation][key]; }
- (NSString *)stringForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:NSString.class] ? value : ([value isKindOfClass:NSNumber.class] ? [value stringValue] : nil);
}
- (NSArray *)arrayForKey:(NSString *)key { id v = [self objectForKey:key]; return [v isKindOfClass:NSArray.class] ? v : nil; }
- (NSDictionary *)dictionaryForKey:(NSString *)key { id v = [self objectForKey:key]; return [v isKindOfClass:NSDictionary.class] ? v : nil; }
- (BOOL)boolForKey:(NSString *)key { id v = [self objectForKey:key]; return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO; }
- (NSInteger)integerForKey:(NSString *)key { id v = [self objectForKey:key]; return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0; }
- (float)floatForKey:(NSString *)key { id v = [self objectForKey:key]; return [v respondsToSelector:@selector(floatValue)] ? [v floatValue] : 0; }
- (double)doubleForKey:(NSString *)key { id v = [self objectForKey:key]; return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0; }
- (void)setObject:(id)value forKey:(NSString *)key {
    @synchronized(self) {
        /* Round-trip to detach mutable caller objects and validate property-list types. */
        if (value) {
            NSError *error = nil;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{key:value} format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
            if (!data) { _lastError = error; NSLog(@"CocoaTop preferences: %@", error); return; }
            NSDictionary *copy = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
            _pending[key] = copy[key];
        } else _pending[key] = [NSNull null];
        [self synchronize];
    }
}
- (void)setBool:(BOOL)v forKey:(NSString *)key { [self setObject:@(v) forKey:key]; }
- (void)setInteger:(NSInteger)v forKey:(NSString *)key { [self setObject:@(v) forKey:key]; }
- (void)setFloat:(float)v forKey:(NSString *)key { [self setObject:@(v) forKey:key]; }
- (void)setDouble:(double)v forKey:(NSString *)key { [self setObject:@(v) forKey:key]; }
- (void)removeObjectForKey:(NSString *)key { [self setObject:nil forKey:key]; }
- (void)removePersistentDomainForName:(NSString *)domain {
    if (![domain isEqualToString:CTDomain] && ![domain isEqualToString:NSBundle.mainBundle.bundleIdentifier]) return;
    @synchronized(self) { _resetPending = YES; [_pending removeAllObjects]; [self synchronize]; }
}
- (BOOL)synchronize {
    @synchronized(self) {
        if (!_pending.count && !_resetPending) return _lastError == nil;
        NSError *error = nil;
        int lockFD = -1, tempFD = -1;
        char *tempPath = NULL;
        BOOL ok = NO;
        do {
            if (!_preferencesPath) { errno = ENOENT; break; }
#if !defined(CT_ROOTHIDE) || !CT_ROOTHIDE
            BOOL isDirectory = NO;
            if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb" isDirectory:&isDirectory] || !isDirectory) {
                errno = ENOENT; break;
            }
#endif
            NSString *directory = [_preferencesPath stringByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) break;
            NSString *resolved = [directory stringByResolvingSymlinksInPath];
            if ([resolved isEqualToString:@"/var/mobile/Library/Preferences"] ||
                [resolved isEqualToString:@"/private/var/mobile/Library/Preferences"]) { errno = EPERM; break; }
            NSString *lockPath = [_preferencesPath stringByAppendingString:@".lock"];
            lockFD = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
            if (lockFD < 0) break;
            if (flock(lockFD, LOCK_EX)) break;
            NSMutableDictionary *values = _resetPending ? [NSMutableDictionary dictionary] : [self readDisk:&error];
            if (!values) break;
            [_pending enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
                if (value == [NSNull null]) [values removeObjectForKey:key];
                else values[key] = value;
            }];
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:values format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
            if (!data) break;
            tempPath = strdup([[_preferencesPath stringByAppendingString:@".XXXXXX"] fileSystemRepresentation]);
            if (!tempPath) { errno = ENOMEM; break; }
            tempFD = mkstemp(tempPath);
            if (tempFD < 0) break;
            if (fchmod(tempFD, 0600)) break;
            const uint8_t *bytes = data.bytes;
            size_t remaining = data.length;
            while (remaining) {
                ssize_t n = write(tempFD, bytes, remaining);
                if (n < 0 && errno == EINTR) continue;
                if (n <= 0) { if (!n) errno = EIO; break; }
                bytes += n; remaining -= (size_t)n;
            }
            if (remaining || fsync(tempFD)) break;
            if (rename(tempPath, _preferencesPath.fileSystemRepresentation)) break;
            ok = YES;
        } while (0);
        int saved = errno;
        if (tempFD >= 0) close(tempFD);
        if (tempPath) { unlink(tempPath); free(tempPath); }
        if (lockFD >= 0) { flock(lockFD, LOCK_UN); close(lockFD); }
        if (ok) { [_pending removeAllObjects]; _resetPending = NO; _lastError = nil; _hasCachedStat = NO; _diskCache = nil; }
        else {
            _lastError = error ?: [NSError errorWithDomain:NSPOSIXErrorDomain code:saved ?: EIO userInfo:nil];
            NSLog(@"CocoaTop preferences were not saved (no native fallback): %@", _lastError);
        }
        return ok;
    }
}
@end
