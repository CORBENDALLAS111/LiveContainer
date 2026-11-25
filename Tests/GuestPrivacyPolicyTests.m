#import <Foundation/Foundation.h>
#import "../LiveContainer/Tweaks/LCGuestPrivacyPolicy.h"

int main(void) {
    @autoreleasepool {
        NSDictionary *guestA = @{@"LCGuestPrivacy": @{@"camera": @YES, @"battery": @YES}};
        NSDictionary *guestB = @{@"LCGuestPrivacy": @{@"microphone": @YES}};
        NSCAssert(LCGuestPrivacyEnabled(guestA, @"camera"), @"Camera opt-in");
        NSCAssert(LCGuestPrivacyEnabled(guestA, @"battery"), @"Battery opt-in");
        NSCAssert(!LCGuestPrivacyEnabled(guestB, @"camera"), @"Separate guest policies");
        NSCAssert(LCGuestPrivacyEnabled(guestB, @"microphone"), @"Microphone opt-in");
        NSCAssert(!LCGuestPrivacyEnabled(@{}, @"camera"), @"Legacy app defaults to off");
        NSCAssert(!LCGuestPrivacyEnabled(@{@"LCGuestPrivacy": @"invalid"}, @"camera"), @"Malformed policy");
        NSCAssert(!LCGuestPrivacyEnabled(@{@"LCGuestPrivacy": @{@"camera": @"true"}}, @"camera"), @"Malformed value");
        NSCAssert(!LCGuestPrivacyEnabled(@{@"LCGuestPrivacy": @{@"unknown": @YES}}, @"unknown"), @"Unknown key");
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:guestA format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
        NSDictionary *decoded = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
        NSCAssert(LCGuestPrivacyEnabled(decoded, @"camera"), @"Binary plist round trip");
        NSLog(@"Guest privacy policy defaults, opt-in, isolation and plist round trip passed.");
    }
    return 0;
}
