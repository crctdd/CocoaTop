#import "CTLocalization.h"

BOOL CTUsesSimplifiedChinese(void)
{
    // Use the actual first system preference, not bundle-negotiated language.
    NSString *language = [NSLocale preferredLanguages].firstObject.lowercaseString;
    if ([language hasPrefix:@"zh-hant"]) return NO;
    return [language hasPrefix:@"zh-hans"] || [language isEqualToString:@"zh"] ||
        [language isEqualToString:@"zh-cn"] || [language isEqualToString:@"zh-sg"];
}

NSString *CTLocalizedString(NSString *source)
{
    if (!source || !CTUsesSimplifiedChinese()) return source;
    static NSBundle *chineseBundle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"zh-Hans" ofType:@"lproj"];
        if (path) chineseBundle = [NSBundle bundleWithPath:path];
    });
    // Missing resource/key safely falls back to the original English.
    return chineseBundle ? [chineseBundle localizedStringForKey:source value:source table:@"Localizable"] : source;
}
