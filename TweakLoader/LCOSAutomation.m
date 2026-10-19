#import "LCOSAutomation.h"
#import <UIKit/UIKit.h>
#import "../LiveContainer/utils.h"
#import <math.h>

@interface LCOSAutomationRunner : NSObject
@property(nonatomic) NSUInteger generation;
@property(nonatomic, strong) UIButton *stopButton;
@property(nonatomic, copy) NSArray *steps;
@property(nonatomic, copy) NSString *profileID;
@property(nonatomic) NSUInteger nextStep;
@end

static NSDictionary *LCOSReadAutomationFile(void) {
    const char *home = getenv("LC_HOME_PATH");
    if (!home) return nil;
    NSString *path = [@(home) stringByAppendingPathComponent:@"Documents/LCOSAutomations.json"];
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if ([attributes[NSFileSize] unsignedLongLongValue] > 512000) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    id file = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [file isKindOfClass:NSDictionary.class] && [file[@"version"] isEqual:@1] ? file : nil;
}

@implementation LCOSAutomationRunner
- (void)finish:(NSString *)message {
    self.generation++;
    [self.stopButton removeFromSuperview]; self.stopButton = nil;
    self.steps = nil; self.profileID = nil;
    [NSUserDefaults.lcUserDefaults setObject:@{@"message":message, @"date":@(NSDate.date.timeIntervalSince1970)} forKey:@"LCOSAutomationLastResult"];
    [NSUserDefaults.lcUserDefaults synchronize];
}
- (void)stop { [self finish:@"Stopped / Остановлено"]; }
- (NSArray<UIWindow *> *)windows {
    NSMutableArray *windows = [NSMutableArray new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows.reverseObjectEnumerator) {
            if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal) [windows addObject:window];
        }
    }
    if (windows.count == 0) {
        // Legacy UIKit guests do not necessarily create UIWindowScene objects.
        for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
            if (!window.hidden && window.alpha > 0.01 && window.windowLevel == UIWindowLevelNormal) [windows addObject:window];
        }
    }
    return windows;
}
- (BOOL)activate:(UIView *)view {
    if (view == self.stopButton || view.hidden || view.alpha <= 0.01 || !view.userInteractionEnabled) return NO;
    if ([view isKindOfClass:UIControl.class]) {
        UIControl *control = (UIControl *)view;
        if (!control.enabled || control.allTargets.count == 0) return NO;
        UIControlEvents events = control.allControlEvents;
        if (events & UIControlEventPrimaryActionTriggered) [control sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
        else if (events & UIControlEventTouchUpInside) [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        else return NO;
        return YES;
    }
    return [view accessibilityActivate];
}
- (void)find:(NSString *)target inView:(UIView *)view matches:(NSMutableArray *)matches {
    if (view.hidden || view.alpha <= 0.01 || view == self.stopButton || !view.userInteractionEnabled) return;
    NSString *title = [view isKindOfClass:UIButton.class] ? ((UIButton *)view).currentTitle : nil;
    if ([view.accessibilityIdentifier isEqualToString:target] || [view.accessibilityLabel isEqualToString:target] || [title isEqualToString:target]) {
        [matches addObject:view];
        return;
    }
    for (UIView *child in view.subviews) [self find:target inView:child matches:matches];
}
- (void)schedule {
    if (self.nextStep >= self.steps.count) { [self finish:@"Completed / Выполнено"]; return; }
    NSUInteger generation = self.generation;
    NSDictionary *step = self.steps[self.nextStep];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([step[@"seconds"] doubleValue] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self.generation) return;
        if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive || ![LCOSReadAutomationFile()[@"enabled"] isEqual:@YES]) {
            [self finish:@"Stopped: app left the foreground or scenarios were disabled. / Приложение скрыто или сценарии отключены."]; return;
        }
        NSString *kind = step[@"kind"];
        BOOL success = [kind isEqualToString:@"wait"];
        if ([kind isEqualToString:@"button"]) {
            NSMutableArray *matches = [NSMutableArray new];
            for (UIWindow *window in self.windows) [self find:step[@"target"] inView:window matches:matches];
            if (matches.count == 1) success = [self activate:matches.firstObject];
        } else if ([kind isEqualToString:@"point"]) {
            UIWindow *window = self.windows.firstObject;
            CGPoint point = CGPointMake(window.bounds.size.width * [step[@"x"] doubleValue], window.bounds.size.height * [step[@"y"] doubleValue]);
            UIView *view = [window hitTest:point withEvent:nil];
            while (view && view != window && ![view isKindOfClass:UIControl.class] && !view.isAccessibilityElement) view = view.superview;
            if (view && view != window) success = [self activate:view];
        }
        if (!success) {
            [self finish:[NSString stringWithFormat:@"Step %lu: button unavailable, ambiguous or unsupported. / Кнопка не найдена, неоднозначна или не поддерживается.", (unsigned long)self.nextStep + 1]]; return;
        }
        if (generation != self.generation) return;
        self.nextStep++; [self schedule];
    });
}
- (void)start:(NSString *)identifier {
    NSDictionary *file = LCOSReadAutomationFile();
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        ![identifier isKindOfClass:NSString.class] || ![file[@"enabled"] isEqual:@YES] || ![[NSUUID alloc] initWithUUIDString:identifier]) return;
    id profiles = file[@"profiles"];
    if (![profiles isKindOfClass:NSArray.class]) return;
    NSDictionary *profile = nil;
    for (id item in profiles) {
        if ([item isKindOfClass:NSDictionary.class] && [item[@"id"] isEqual:identifier]) { profile = item; break; }
    }
    if (!profile || ![profile[@"app"] isEqual:NSBundle.mainBundle.bundlePath.lastPathComponent]) return;
    NSArray *steps = profile[@"steps"];
    if (![steps isKindOfClass:NSArray.class] || steps.count == 0 || steps.count > 60) return;
    double total = 0;
    for (id step in steps) {
        if (![step isKindOfClass:NSDictionary.class] || ![step[@"seconds"] isKindOfClass:NSNumber.class]) return;
        double delay = [step[@"seconds"] doubleValue]; total += delay;
        if (!isfinite(delay) || delay < 0.2 || delay > 60 || total > 300) return;
        NSString *kind = step[@"kind"];
        if ([kind isEqual:@"button"]) {
            if (![step[@"target"] isKindOfClass:NSString.class] || ![step[@"target"] length] || [step[@"target"] length] > 256) return;
        } else if ([kind isEqual:@"point"]) {
            for (NSString *axis in @[@"x", @"y"]) {
                if (![step[axis] isKindOfClass:NSNumber.class]) return;
                double value = [step[axis] doubleValue];
                if (!isfinite(value) || value < 0 || value > 1) return;
            }
        } else if (![kind isEqual:@"wait"]) return;
    }
    UIWindow *window = self.windows.firstObject;
    if (!window) return;
    self.generation++; [self.stopButton removeFromSuperview];
    self.profileID = identifier; self.steps = steps; self.nextStep = 0;
    UIButton *stop = [UIButton buttonWithType:UIButtonTypeSystem];
    stop.frame = CGRectMake(MAX(8, window.bounds.size.width - 60), window.safeAreaInsets.top + 8, 48, 48);
    stop.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [stop setImage:[UIImage systemImageNamed:@"stop.fill"] forState:UIControlStateNormal];
    stop.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.95];
    stop.layer.cornerRadius = 24; stop.accessibilityLabel = @"Stop automation / Остановить сценарий";
    [stop addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton = stop; [window addSubview:stop]; [self schedule];
}
@end

static LCOSAutomationRunner *runner;
void LCOSStartAutomation(NSString *identifier) {
    if (!identifier || NSUserDefaults.isSideStore || NSUserDefaults.isLiveProcess) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!runner) runner = [LCOSAutomationRunner new];
        [runner start:identifier];
    });
}

__attribute__((constructor)) static void LCOSAutomationInit(void) {
    if (!NSUserDefaults.lcGuestAppId || NSUserDefaults.isSideStore || NSUserDefaults.isLiveProcess) return;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (runner.steps) [runner stop];
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NSDictionary *pending = [NSUserDefaults.lcUserDefaults dictionaryForKey:@"LCOSAutomationPending"];
        if (!pending) return;
        [NSUserDefaults.lcUserDefaults removeObjectForKey:@"LCOSAutomationPending"];
        [NSUserDefaults.lcUserDefaults synchronize];
        double age = NSDate.date.timeIntervalSince1970 - [pending[@"date"] doubleValue];
        if (age < 0 || age > 90 || ![pending[@"app"] isEqual:NSBundle.mainBundle.bundlePath.lastPathComponent]) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ LCOSStartAutomation(pending[@"id"]); });
    }];
}
