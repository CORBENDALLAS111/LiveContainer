// Adapted from KIF (Square, Inc., Apache-2.0), with runtime capability checks,
// asynchronous touch release and process-local delivery. See Resources/KIF-NOTICE.txt.
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach_time.h>

typedef struct __IOHIDEvent *LCOSHID;
typedef LCOSHID (*LCOSHand)(CFAllocatorRef, AbsoluteTime, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t,
                            double, double, double, double, double, Boolean, Boolean, uint32_t);
typedef LCOSHID (*LCOSFinger)(CFAllocatorRef, AbsoluteTime, uint32_t, uint32_t, uint32_t,
                              double, double, double, double, double, double, double, double, double, double,
                              Boolean, Boolean, uint32_t);
static LCOSHID LCOSCreateHID(UITouch *touch) CF_RETURNS_RETAINED;
static LCOSHID LCOSCreateHID(UITouch *touch) {
    static LCOSHand hand; static LCOSFinger finger;
    static void (*integer)(LCOSHID, uint32_t, int);
    static void (*append)(LCOSHID, LCOSHID);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (!library) library = dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (!library) return;
        hand = (LCOSHand)dlsym(library, "IOHIDEventCreateDigitizerEvent");
        finger = (LCOSFinger)dlsym(library, "IOHIDEventCreateDigitizerFingerEventWithQuality");
        integer = dlsym(library, "IOHIDEventSetIntegerValue"); append = dlsym(library, "IOHIDEventAppendEvent");
    });
    if (!hand || !finger || !integer || !append) return NULL;
    uint64_t now = mach_absolute_time(); AbsoluteTime timestamp = { (UInt32)(now >> 32), (UInt32)now };
    BOOL down = touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled;
    CGPoint point = [touch locationInView:touch.window];
    LCOSHID parent = hand(kCFAllocatorDefault, timestamp, 3, 0, 0, 2, 0, 0, 0, 0, 0, 0, false, down, 0);
    LCOSHID child = finger(kCFAllocatorDefault, timestamp, 1, 2, 3, point.x, point.y, 0, 0, 0, 5, 5, 1, 1, 1, down, down, 0);
    if (!parent || !child) { if (parent) CFRelease(parent); if (child) CFRelease(child); return NULL; }
    integer(parent, (11 << 16) + 25, 1); integer(child, (11 << 16) + 25, 1);
    append(parent, child); CFRelease(child); return parent;
}

@interface UITouch (LCOSPrivateTouch)
- (void)setWindow:(UIWindow *)window;
- (void)setView:(id)view;
- (void)setTapCount:(NSUInteger)count;
- (void)setTimestamp:(NSTimeInterval)value;
- (void)setPhase:(UITouchPhase)phase;
- (void)setGestureView:(id)view;
- (void)_setLocationInWindow:(CGPoint)point resetPrevious:(BOOL)reset;
- (void)_setIsFirstTouchForView:(BOOL)value;
- (void)_setIsTapToClick:(BOOL)value;
- (void)_setHidEvent:(LCOSHID)event;
@end
@interface UIEvent (LCOSPrivateEvent)
- (void)_clearTouches;
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_setHIDEvent:(LCOSHID)event;
@end
@interface UIApplication (LCOSPrivateEvent)
- (UIEvent *)_touchesEvent;
@end
@interface UIView (LCOSHitTest)
- (id)_hitTestWithContext:(id)context;
@end

static BOOL LCOSDeliverTouch(UITouch *touch) {
    LCOSHID hid = LCOSCreateHID(touch);
    if (!hid) return NO;
    BOOL delivered = NO;
    @try {
        UIEvent *event = [UIApplication.sharedApplication _touchesEvent];
        if ([event respondsToSelector:@selector(_clearTouches)] && [event respondsToSelector:@selector(_setHIDEvent:)] &&
            [event respondsToSelector:@selector(_addTouch:forDelayedDelivery:)]) {
            [touch _setHidEvent:hid]; [event _clearTouches]; [event _setHIDEvent:hid];
            [event _addTouch:touch forDelayedDelivery:NO]; [UIApplication.sharedApplication sendEvent:event]; delivered = YES;
        }
    } @catch (NSException *exception) { delivered = NO; }
    CFRelease(hid); return delivered;
}

static void LCOSTapAtPoint(UIWindow *window, CGPoint point, void (^completion)(BOOL)) {
    if (!NSThread.isMainThread || !window || window.hidden || !CGRectContainsPoint(window.bounds, point) ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        ![UIApplication.sharedApplication respondsToSelector:@selector(_touchesEvent)]) { completion(NO); return; }
    @try {
        id hit = [window hitTest:point withEvent:nil];
        if (@available(iOS 18.0, *)) {
            Class contextClass = NSClassFromString(@"_UIHitTestContext"); SEL selector = NSSelectorFromString(@"contextWithPoint:radius:");
            if ([contextClass respondsToSelector:selector] && [UIView instancesRespondToSelector:@selector(_hitTestWithContext:)]) {
                id context = ((id (*)(id, SEL, CGPoint, CGFloat))objc_msgSend)(contextClass, selector, point, 0);
                for (UIView *view = [hit isKindOfClass:UIView.class] ? hit : nil; context && view; view = view.superview) {
                    id found = [view _hitTestWithContext:context]; if (found) { hit = found; break; }
                }
            }
        }
        if (!hit || hit == window) { completion(NO); return; }
        UITouch *touch = [UITouch new];
        for (NSString *name in @[@"setWindow:", @"setView:", @"setTapCount:", @"setTimestamp:", @"setPhase:", @"_setLocationInWindow:resetPrevious:", @"_setHidEvent:"])
            if (![touch respondsToSelector:NSSelectorFromString(name)]) { completion(NO); return; }
        [touch setWindow:window]; [touch setTapCount:1]; [touch _setLocationInWindow:point resetPrevious:YES];
        [touch setView:hit]; [touch setPhase:UITouchPhaseBegan];
        if ([touch respondsToSelector:@selector(_setIsFirstTouchForView:)]) [touch _setIsFirstTouchForView:YES];
        else if ([touch respondsToSelector:@selector(_setIsTapToClick:)]) [touch _setIsTapToClick:YES];
        [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
        if ([touch respondsToSelector:@selector(setGestureView:)]) [touch setGestureView:hit];
        if (!LCOSDeliverTouch(touch)) { completion(NO); return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            @try {
                [touch setPhase:UIApplication.sharedApplication.applicationState == UIApplicationStateActive ? UITouchPhaseEnded : UITouchPhaseCancelled];
                [touch setTimestamp:NSProcessInfo.processInfo.systemUptime];
                completion(LCOSDeliverTouch(touch));
            } @catch (NSException *exception) { completion(NO); }
        });
    } @catch (NSException *exception) { completion(NO); }
}
