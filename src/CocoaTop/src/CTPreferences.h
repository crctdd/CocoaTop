#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Explicit jailbreak-local plist store; not an NSUserDefaults subclass.
@interface CTPreferences : NSObject
+ (instancetype)standardUserDefaults;
@property (nonatomic, readonly, nullable) NSString *preferencesPath;
@property (nonatomic, readonly, nullable) NSError *lastError;
- (void)registerDefaults:(NSDictionary<NSString *, id> *)defaults;
- (nullable id)objectForKey:(NSString *)key;
- (nullable NSString *)stringForKey:(NSString *)key;
- (nullable NSArray *)arrayForKey:(NSString *)key;
- (nullable NSDictionary *)dictionaryForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (NSInteger)integerForKey:(NSString *)key;
- (float)floatForKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key;
- (void)setObject:(nullable id)value forKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;
- (void)setFloat:(float)value forKey:(NSString *)key;
- (void)setDouble:(double)value forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
/// Accepts this app's bundle ID or com.crctdd.cocoatop; never touches a native domain.
- (void)removePersistentDomainForName:(NSString *)domain;
- (NSDictionary *)dictionaryRepresentation;
- (BOOL)synchronize;
@end
NS_ASSUME_NONNULL_END
