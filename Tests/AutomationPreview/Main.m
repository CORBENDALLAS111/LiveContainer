#import <UIKit/UIKit.h>
#import "../../TweakLoader/LCOSAutomation.h"
#import "../../TweakLoader/LCOSTouch.h"

@interface NSUserDefaults (LCOSFixture)
@end
@implementation NSUserDefaults (LCOSFixture)
+ (NSString *)lcGuestAppId { return @"org.example.automation-fixture"; }
+ (NSUserDefaults *)lcUserDefaults { return NSUserDefaults.standardUserDefaults; }
+ (BOOL)isSideStore { return NO; }
+ (BOOL)isLiveProcess { return NO; }
@end

@interface FixtureDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic) NSInteger count;
@property(nonatomic) NSInteger gestures;
@property(nonatomic) NSInteger swiftUITaps;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) NSMutableDictionary *file;
@end
@implementation FixtureDelegate
- (UILabel *)recordLabel:(UIView *)view {
    if ([view isKindOfClass:UILabel.class] && ([((UILabel *)view).text isEqual:@"Record"] || [((UILabel *)view).text isEqual:@"Записать"])) return (UILabel *)view;
    for (UIView *child in view.subviews) { UILabel *found = [self recordLabel:child]; if (found) return found; }
    return nil;
}
- (void)gesturePressed { self.gestures++; [self pressed]; }
- (void)pressed { self.count++; self.status.text = [NSString stringWithFormat:@"Button activations: %ld", (long)self.count]; }
- (NSString *)path:(NSString *)name { return [NSHomeDirectory() stringByAppendingPathComponent:[@"Documents/" stringByAppendingString:name]]; }
- (void)writeFile {
    [[NSJSONSerialization dataWithJSONObject:self.file options:0 error:nil] writeToFile:[self path:@"LCOSAutomations.json"] atomically:YES];
}
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    setenv("LC_HOME_PATH", NSHomeDirectory().UTF8String, 1);
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    UIView *view = self.window.rootViewController.view; view.backgroundColor = UIColor.systemBackgroundColor;
    self.status = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, self.window.bounds.size.width-40, 80)];
    self.status.numberOfLines = 0; self.status.text = @"Testing actual guest automation runner…";
    [view addSubview:self.status];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.frame = CGRectMake(50, self.window.bounds.size.height/2-150, self.window.bounds.size.width-100, 60);
    button.accessibilityIdentifier = @"fixture.button";
    [button setTitle:@"Continue" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:button];
    UIButton *modern = [UIButton buttonWithType:UIButtonTypeSystem];
    modern.frame = CGRectMake(50, self.window.bounds.size.height/2-30, self.window.bounds.size.width-100, 60);
    [modern setTitle:@"UIAction button" forState:UIControlStateNormal];
    [modern addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) { [self pressed]; }]
       forControlEvents:UIControlEventPrimaryActionTriggered];
    [view addSubview:modern];
    UIView *gesture = [[UIView alloc] initWithFrame:CGRectMake(50, self.window.bounds.size.height*0.7-30, self.window.bounds.size.width-100, 60)];
    gesture.backgroundColor = UIColor.systemOrangeColor;
    [gesture addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(gesturePressed)]];
    [view addSubview:gesture];
    Class factory = NSClassFromString(@"LCOSSwiftUITestFactory");
    SEL create = NSSelectorFromString(@"controllerWithAction:");
    UIViewController *(*make)(id,SEL,void (^)(void)) = (void *)[factory methodForSelector:create];
    UIViewController *swift = make(factory, create, ^{ self.swiftUITaps++; [self pressed]; });
    [self.window.rootViewController addChildViewController:swift];
    swift.view.frame = CGRectMake(50, self.window.bounds.size.height*0.85-40, self.window.bounds.size.width-100, 80);
    [view addSubview:swift.view]; [swift didMoveToParentViewController:self.window.rootViewController];
    [self.window makeKeyAndVisible];
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSDictionary *base = @{@"id":NSUUID.UUID.UUIDString, @"seconds":@0.2, @"target":@"fixture.button", @"x":@0.5, @"y":@0.5};
    NSMutableArray *steps = [NSMutableArray new];
    for (NSString *kind in @[@"button", @"wait", @"point"]) {
        NSMutableDictionary *step = base.mutableCopy; step[@"kind"] = kind; [steps addObject:step];
    }
    for (NSNumber *y in @[@0.7, @0.85]) {
        NSMutableDictionary *step = base.mutableCopy; step[@"kind"] = @"point"; step[@"y"] = y; [steps addObject:step];
    }
    NSMutableDictionary *profile = [@{@"id":identifier, @"name":@"SDK fixture", @"app":NSBundle.mainBundle.bundlePath.lastPathComponent, @"steps":steps} mutableCopy];
    self.file = [@{@"version":@1, @"enabled":@YES, @"apps":@[], @"profiles":@[profile]} mutableCopy];
    [self writeFile];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        LCOSStartAutomation(identifier);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            NSString *message = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"LCOSAutomationLastResult"][@"message"];
            BOOL activation = self.count == 4 && ([message hasPrefix:@"Completed"] || [message hasPrefix:@"Выполнено"]);
            BOOL rawGesture = self.gestures == 1, swiftUI = self.swiftUITaps == 1;
            LCOSOfferRecording();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                UILabel *record = [self recordLabel:self.window.rootViewController.presentedViewController.view];
                CGPoint point = [record convertPoint:CGPointMake(record.bounds.size.width/2, record.bounds.size.height/2) toView:self.window];
                if (record) LCOSTapAtPoint(self.window, point, ^(BOOL delivered) {});
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                LCOSTapAtPoint(self.window, CGPointMake(self.window.bounds.size.width/2, self.window.bounds.size.height*0.7), ^(BOOL delivered) {
                    LCOSStopRecording();
                    NSDictionary *saved = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[self path:@"LCOSAutomations.json"]] options:0 error:nil];
                    NSDictionary *recorded = [saved[@"profiles"] lastObject];
                    BOOL captured = delivered && [recorded[@"steps"] count] == 1 && ![recorded[@"id"] isEqual:identifier];
                    LCOSStartAutomation(recorded[@"id"]);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        BOOL replay = captured && self.count == 6 && self.gestures == 3;
                        NSMutableDictionary *wait = base.mutableCopy; wait[@"kind"] = @"wait"; wait[@"seconds"] = @1;
                        NSMutableDictionary *click = base.mutableCopy; click[@"kind"] = @"button";
                        self.file = saved.mutableCopy;
                        profile[@"steps"] = @[wait, click]; self.file[@"profiles"] = @[profile];
                        [self writeFile]; LCOSStartAutomation(identifier);
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/5), dispatch_get_main_queue(), ^{
                            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:application];
                        });
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                            BOOL cancellation = self.count == 6;
                            self.file[@"enabled"] = @NO; [self writeFile]; LCOSStartAutomation(identifier);
                            LCOSStartRecording();
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                                BOOL disabled = self.count == 6;
                                NSDictionary *evidence = @{@"actual_uikit_button_and_point":@(activation), @"raw_touch_gesture":@(rawGesture), @"swiftui_point":@(swiftUI), @"recorded_profile_replay":@(replay), @"recording_prompt_starts_capture":@(captured), @"background_cancellation":@(cancellation), @"disabled_does_not_execute":@(disabled), @"physical_device_tested":@NO};
                                [[NSJSONSerialization dataWithJSONObject:evidence options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[self path:@"automation-evidence.json"] atomically:YES];
                                self.status.text = activation && replay && cancellation && disabled ? @"Touch and recording checks passed" : @"Touch and recording checks FAILED";
                            });
                        });
                    });
                });
            });
        });
    });
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(FixtureDelegate.class)); }
}
