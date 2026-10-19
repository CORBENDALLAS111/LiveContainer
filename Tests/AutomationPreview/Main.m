#import <UIKit/UIKit.h>
#import "../../TweakLoader/LCOSAutomation.h"

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
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) NSMutableDictionary *file;
@end
@implementation FixtureDelegate
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
    button.frame = CGRectMake(50, self.window.bounds.size.height/2-30, self.window.bounds.size.width-100, 60);
    button.accessibilityIdentifier = @"fixture.button";
    [button setTitle:@"Continue" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(pressed) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:button];
    [self.window makeKeyAndVisible];
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSDictionary *base = @{@"id":NSUUID.UUID.UUIDString, @"seconds":@0.2, @"target":@"fixture.button", @"x":@0.5, @"y":@0.5};
    NSMutableArray *steps = [NSMutableArray new];
    for (NSString *kind in @[@"button", @"wait", @"point"]) {
        NSMutableDictionary *step = base.mutableCopy; step[@"kind"] = kind; [steps addObject:step];
    }
    NSMutableDictionary *profile = [@{@"id":identifier, @"name":@"SDK fixture", @"app":NSBundle.mainBundle.bundlePath.lastPathComponent, @"steps":steps} mutableCopy];
    self.file = [@{@"version":@1, @"enabled":@YES, @"apps":@[], @"profiles":@[profile]} mutableCopy];
    [self writeFile];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        LCOSStartAutomation(identifier);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            BOOL activation = self.count == 2 && [[NSUserDefaults.standardUserDefaults dictionaryForKey:@"LCOSAutomationLastResult"][@"message"] hasPrefix:@"Completed"];
            NSMutableDictionary *wait = base.mutableCopy; wait[@"kind"] = @"wait"; wait[@"seconds"] = @1;
            NSMutableDictionary *click = base.mutableCopy; click[@"kind"] = @"button";
            profile[@"steps"] = @[wait, click]; [self writeFile]; LCOSStartAutomation(identifier);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC/5), dispatch_get_main_queue(), ^{
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:application];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                BOOL cancellation = self.count == 2;
                self.file[@"enabled"] = @NO; [self writeFile]; LCOSStartAutomation(identifier);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    BOOL disabled = self.count == 2;
                    NSDictionary *evidence = @{@"actual_uikit_button_and_point":@(activation), @"background_cancellation":@(cancellation), @"disabled_does_not_execute":@(disabled), @"physical_device_tested":@NO};
                    [[NSJSONSerialization dataWithJSONObject:evidence options:NSJSONWritingPrettyPrinted error:nil] writeToFile:[self path:@"automation-evidence.json"] atomically:YES];
                    self.status.text = activation && cancellation && disabled ? @"Automation runner checks passed" : @"Automation runner checks FAILED";
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
