#import <Foundation/Foundation.h>

/// Per-guest preferences stored in LCAppInfo.plist. Missing or unknown
/// keys never change the behavior of existing apps.
static inline NSArray<NSString *> *LCGuestPrivacyKeys(void) {
    return @[@"camera", @"microphone", @"battery", @"proximity"];
}

static inline BOOL LCGuestPrivacyEnabled(NSDictionary *appInfo, NSString *key) {
    if (![LCGuestPrivacyKeys() containsObject:key]) return NO;
    id policy = appInfo[@"LCGuestPrivacy"];
    if (![policy isKindOfClass:NSDictionary.class]) return NO;
    id value = policy[key];
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}
