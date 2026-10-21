// Included once by LCOSAutomation.m; UIKit dispatch is observed only in opted-in guest sessions.
@interface LCOSRecorder : NSObject
@property(nonatomic) BOOL active;
@property(nonatomic, strong) NSMutableArray *steps;
@property(nonatomic, strong) NSMutableDictionary *origins;
@property(nonatomic, strong) UIButton *button;
@property(nonatomic) NSTimeInterval lastTime;
@property(nonatomic) NSUInteger generation;
- (void)observe:(UIEvent *)event;
- (void)stop;
@end
static LCOSRecorder *LCOSRecording;

@implementation LCOSRecorder
- (void)result:(NSString *)message {
    [NSUserDefaults.lcUserDefaults setObject:@{@"message":message, @"date":@(NSDate.date.timeIntervalSince1970)} forKey:@"LCOSAutomationLastResult"];
    [NSUserDefaults.lcUserDefaults synchronize];
}
- (void)stop {
    if (!self.active) return;
    self.active = NO; self.generation++;
    [self.button removeFromSuperview]; self.button = nil; self.origins = nil;
    NSMutableDictionary *file = LCOSReadAutomationFile().mutableCopy;
    NSMutableArray *profiles = [file[@"profiles"] isKindOfClass:NSArray.class] ? [file[@"profiles"] mutableCopy] : [NSMutableArray new];
    NSString *message = LCOSAutomationText(@"No taps recorded", @"Нажатия не записаны");
    if (self.steps.count && file && profiles.count < 100) {
        NSString *app = NSBundle.mainBundle.bundlePath.lastPathComponent;
        NSString *name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: app;
        NSDateFormatter *format = [NSDateFormatter new]; format.dateFormat = @"HH:mm dd.MM";
        [profiles addObject:@{@"id":NSUUID.UUID.UUIDString, @"app":app, @"name":[NSString stringWithFormat:@"%@ · %@", [name substringToIndex:MIN(name.length, 70)], [format stringFromDate:NSDate.date]], @"steps":self.steps.copy}];
        file[@"profiles"] = profiles;
        NSData *data = [NSJSONSerialization dataWithJSONObject:file options:0 error:nil];
        NSString *path = [@(getenv("LC_HOME_PATH") ?: "") stringByAppendingPathComponent:@"Documents/LCOSAutomations.json"];
        BOOL saved = data && data.length <= 512000 && [data writeToFile:path options:NSDataWritingAtomic error:nil];
        message = saved ? LCOSAutomationText(@"Recording saved in Settings → Automations", @"Запись сохранена в Настройки → Автоматизации") : LCOSAutomationText(@"Recording could not be saved", @"Не удалось сохранить запись");
    } else if (self.steps.count) message = LCOSAutomationText(@"Recording could not be saved: scenario limit reached.", @"Запись не сохранена: достигнут лимит сценариев.");
    self.steps = nil; [self result:message];
}
- (void)start {
    if (self.active || ![LCOSReadAutomationFile()[@"enabled"] isEqual:@YES] || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    UIWindow *window = [LCOSAutomationRunner new].windows.firstObject;
    if (!window) return;
    self.active = YES; self.steps = [NSMutableArray new]; self.origins = [NSMutableDictionary new];
    self.lastTime = NSProcessInfo.processInfo.systemUptime; NSUInteger generation = ++self.generation;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(MAX(8, window.bounds.size.width - 170), window.safeAreaInsets.top + 8, 160, 44);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [button setTitle:LCOSAutomationText(@"● Record · Stop", @"● Запись · Стоп") forState:UIControlStateNormal];
    button.backgroundColor = UIColor.secondarySystemBackgroundColor; button.tintColor = UIColor.systemRedColor;
    button.layer.cornerRadius = 22; button.accessibilityIdentifier = @"lcos.record.stop";
    [button addTarget:self action:@selector(stop) forControlEvents:UIControlEventTouchUpInside];
    self.button = button; [window addSubview:button];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (generation == self.generation) [self stop]; });
}
- (void)observe:(UIEvent *)event {
    if (!self.active || event.type != UIEventTypeTouches) return;
    for (UITouch *touch in event.allTouches) {
        NSValue *key = [NSValue valueWithNonretainedObject:touch];
        UIView *view = [touch.view isKindOfClass:UIView.class] ? touch.view : nil;
        BOOL excluded = touch.view == self.button || [view isDescendantOfView:self.button] || [NSStringFromClass(touch.window.class).lowercaseString containsString:@"keyboard"];
        for (UIView *parent = view; parent && !excluded; parent = parent.superview)
            if ([parent conformsToProtocol:@protocol(UITextInput)]) excluded = YES;
        if (excluded || !touch.window || touch.window.bounds.size.width <= 0 || touch.window.bounds.size.height <= 0) continue;
        CGPoint point = [touch locationInView:touch.window];
        if (touch.phase == UITouchPhaseBegan) self.origins[key] = [NSValue valueWithCGPoint:point];
        if (touch.phase == UITouchPhaseMoved) {
            NSValue *origin = self.origins[key];
            if (origin && hypot(point.x-origin.CGPointValue.x, point.y-origin.CGPointValue.y) > 12) [self.origins removeObjectForKey:key];
        }
        if (touch.phase == UITouchPhaseCancelled) [self.origins removeObjectForKey:key];
        if (touch.phase != UITouchPhaseEnded) continue;
        NSValue *origin = self.origins[key]; [self.origins removeObjectForKey:key];
        if (!origin || hypot(point.x-origin.CGPointValue.x, point.y-origin.CGPointValue.y) > 12) continue;
        double now = NSProcessInfo.processInfo.systemUptime, delay = MAX(0.2, now-self.lastTime), total = 0;
        for (NSDictionary *step in self.steps) total += [step[@"seconds"] doubleValue];
        if (total+delay > 300 || self.steps.count >= 60) { [self stop]; return; }
        while (delay > 60 && self.steps.count < 59) {
            [self.steps addObject:@{@"id":NSUUID.UUID.UUIDString, @"kind":@"wait", @"seconds":@60, @"target":@"", @"x":@0.5, @"y":@0.5}]; delay -= 60;
        }
        if (delay > 60) { [self stop]; return; }
        [self.steps addObject:@{@"id":NSUUID.UUID.UUIDString, @"kind":@"point", @"seconds":@(delay), @"target":@"", @"x":@(MIN(1,MAX(0,point.x/touch.window.bounds.size.width))), @"y":@(MIN(1,MAX(0,point.y/touch.window.bounds.size.height)))}];
        self.lastTime = now;
        [self.button setTitle:[NSString stringWithFormat:LCOSAutomationText(@"● %lu taps · Stop", @"● %lu нажатий · Стоп"), (unsigned long)self.steps.count] forState:UIControlStateNormal];
        if (self.steps.count >= 60) { [self stop]; return; }
    }
}
@end

void LCOSStartRecording(void) {
    if (NSUserDefaults.isSideStore || NSUserDefaults.isLiveProcess) return;
    dispatch_async(dispatch_get_main_queue(), ^{ if (!LCOSRecording) LCOSRecording = [LCOSRecorder new]; [LCOSRecording start]; });
}
void LCOSStopRecording(void) { [LCOSRecording stop]; }
@implementation UIApplication (LCOSRecording)
- (void)lcos_record_sendEvent:(UIEvent *)event {
    if (LCOSRecording.active) [LCOSRecording observe:event];
    [self lcos_record_sendEvent:event];
}
@end

void LCOSOfferRecording(void) {
    if (NSUserDefaults.isSideStore || NSUserDefaults.isLiveProcess) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIViewController *presenter = [LCOSAutomationRunner new].windows.firstObject.rootViewController;
            while (presenter.presentedViewController) presenter = presenter.presentedViewController;
            if (!presenter || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:LCOSAutomationText(@"Record taps?", @"Записать нажатия?") message:LCOSAutomationText(@"Stop saves the scenario. Keyboard input and scrolling are not recorded.", @"Стоп сохраняет сценарий. Клавиатура и прокрутка не записываются.") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:LCOSAutomationText(@"Skip", @"Пропустить") style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:LCOSAutomationText(@"Record", @"Записать") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ LCOSStartRecording(); }); }]];
            [presenter presentViewController:alert animated:YES completion:nil];
        });
}

__attribute__((constructor)) static void LCOSRecordingInit(void) {
    if (!NSUserDefaults.lcGuestAppId || NSUserDefaults.isSideStore || NSUserDefaults.isLiveProcess) return;
    swizzle(UIApplication.class, @selector(sendEvent:), @selector(lcos_record_sendEvent:));
    BOOL launchedWithScenario = [NSUserDefaults.lcUserDefaults dictionaryForKey:@"LCOSAutomationPending"] != nil;
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { LCOSStopRecording(); }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        static BOOL offered = NO;
        if (offered) return;
        NSDictionary *file = LCOSReadAutomationFile();
        if (![file[@"enabled"] isEqual:@YES] || ![file[@"recordAtLaunch"] isEqual:@YES] || launchedWithScenario || [NSUserDefaults.lcUserDefaults dictionaryForKey:@"LCOSAutomationPending"]) return;
        offered = YES;
        LCOSOfferRecording();
    }];
}
