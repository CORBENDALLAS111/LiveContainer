#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

/// ChatGPTUsage: a self-contained, deliberately non-invasive LiveContainer overlay.
/// No API calls, credential access, traffic interception or private ChatGPT hooks.
static NSArray<NSString *> *CHModels(void) {
    return @[@"GPT-6", @"Thinking", @"Pro", @"Codex"];
}

static UIColor *CHColor(CGFloat r, CGFloat g, CGFloat b) {
    return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1.0];
}

@interface CHUsageOverlay : NSObject
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *details;
@property (nonatomic, strong) UILabel *summary;
@property (nonatomic, strong) UILabel *value;
@property (nonatomic, strong) UILabel *resetLabel;
@property (nonatomic, strong) UIButton *modelButton;
@property (nonatomic, strong) UIButton *usedButton;
@property (nonatomic, weak) UIWindow *attachedWindow;
@property (nonatomic, assign) BOOL expanded;
@property (nonatomic, assign) CGFloat keyboardHeight;
@property (nonatomic, assign) CGPoint dragShift;
@property (nonatomic, assign) NSUInteger selectedModel;
@property (nonatomic, strong) NSTimer *refreshTimer;
@end

@implementation CHUsageOverlay

+ (instancetype)shared {
    static CHUsageOverlay *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (NSString *)storageKey:(NSString *)suffix {
    NSString *model = CHModels()[self.selectedModel];
    return [NSString stringWithFormat:@"CHUsage.v1.%@.%@", model, suffix];
}

- (NSInteger)remaining {
    id number = [[NSUserDefaults standardUserDefaults] objectForKey:[self storageKey:@"remaining"]];
    return number ? [number integerValue] : -1;
}

- (NSDate *)resetDate {
    id time = [[NSUserDefaults standardUserDefaults] objectForKey:[self storageKey:@"reset"]];
    return time ? [NSDate dateWithTimeIntervalSince1970:[time doubleValue]] : nil;
}

- (BOOL)isAppSupported {
    NSString *bundle = [NSBundle mainBundle].bundleIdentifier.lowercaseString ?: @"";
    NSString *display = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"";
    NSString *name = [NSProcessInfo processInfo].processName ?: @"";
    return [bundle hasPrefix:@"com.openai.chat"] ||
           [display.lowercaseString containsString:@"chatgpt"] ||
           [name.lowercaseString containsString:@"chatgpt"];
}

- (void)start {
    if (![self isAppSupported]) {
        NSLog(@"[ChatGPTUsage] Not a ChatGPT guest; HUD disabled.");
        return;
    }
    NSInteger stored = [[NSUserDefaults standardUserDefaults] integerForKey:@"CHUsage.v1.model"];
    self.selectedModel = MIN((NSUInteger)MAX((NSInteger)0, stored), CHModels().count - 1);
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:self selector:@selector(attachIfPossible) name:UIApplicationDidBecomeActiveNotification object:nil];
    [nc addObserver:self selector:@selector(attachIfPossible) name:UIWindowDidBecomeKeyNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [nc addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:30.0
                                                        target:self
                                                      selector:@selector(refresh)
                                                      userInfo:nil
                                                       repeats:YES];
    [self performSelector:@selector(attachIfPossible) withObject:nil afterDelay:1.0];
    [self performSelector:@selector(attachIfPossible) withObject:nil afterDelay:4.0];
}

- (UIWindow *)normalWindow {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (scene.activationState != UISceneActivationStateForegroundActive &&
            scene.activationState != UISceneActivationStateForegroundInactive) continue;
        for (UIWindow *window in ws.windows) {
            if (window.isKeyWindow && !window.isHidden && window.windowLevel == UIWindowLevelNormal) return window;
        }
        for (UIWindow *window in ws.windows) {
            if (!window.isHidden && window.windowLevel == UIWindowLevelNormal) return window;
        }
    }
    return app.keyWindow;
}

- (UILabel *)labelWithSize:(CGFloat)size bold:(BOOL)bold {
    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.whiteColor;
    label.font = bold ? [UIFont systemFontOfSize:size weight:UIFontWeightSemibold]
                      : [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (UIButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = CHColor(57, 57, 59);
    button.layer.cornerRadius = 10;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildPanel {
    self.panel = [[UIView alloc] initWithFrame:CGRectZero];
    self.panel.tag = 48511;
    self.panel.backgroundColor = CHColor(34, 34, 36);
    self.panel.layer.cornerRadius = 19;
    self.panel.layer.borderWidth = 1.0;
    self.panel.layer.borderColor = CHColor(74, 74, 76).CGColor;
    self.panel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity = 0.35;
    self.panel.layer.shadowRadius = 14;
    self.panel.layer.shadowOffset = CGSizeMake(0, 5);
    self.panel.clipsToBounds = NO;

    self.topBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.topBar.backgroundColor = CHColor(34, 34, 36);
    self.topBar.layer.cornerRadius = 19;
    [self.panel addSubview:self.topBar];

    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(12, 15, 9, 9)];
    dot.layer.cornerRadius = 4.5;
    dot.backgroundColor = CHColor(255, 204, 57);
    [self.topBar addSubview:dot];

    self.summary = [self labelWithSize:12 bold:YES];
    self.summary.frame = CGRectMake(29, 4, 222, 30);
    [self.topBar addSubview:self.summary];

    UITapGestureRecognizer *toggle = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleDetails)];
    [self.topBar addGestureRecognizer:toggle];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
    [self.topBar addGestureRecognizer:pan];

    self.details = [[UIView alloc] initWithFrame:CGRectZero];
    self.details.hidden = YES;
    [self.panel addSubview:self.details];

    self.modelButton = [self buttonWithTitle:@"Model" action:@selector(nextModel)];
    [self.details addSubview:self.modelButton];

    UILabel *hint = [self labelWithSize:11 bold:NO];
    hint.text = @"Remaining messages";
    hint.textColor = CHColor(170, 170, 175);
    hint.frame = CGRectMake(14, 46, 220, 18);
    [self.details addSubview:hint];

    self.value = [self labelWithSize:20 bold:YES];
    self.value.frame = CGRectMake(14, 63, 228, 28);
    [self.details addSubview:self.value];

    self.resetLabel = [self labelWithSize:11 bold:NO];
    self.resetLabel.textColor = CHColor(181, 181, 186);
    self.resetLabel.frame = CGRectMake(14, 95, 232, 20);
    [self.details addSubview:self.resetLabel];

    UIButton *set = [self buttonWithTitle:@"Set remaining" action:@selector(setRemaining)];
    set.frame = CGRectMake(14, 125, 114, 34);
    [self.details addSubview:set];

    self.usedButton = [self buttonWithTitle:@"−1 used" action:@selector(subtractOne)];
    self.usedButton.frame = CGRectMake(136, 125, 110, 34);
    [self.details addSubview:self.usedButton];

    UIButton *reset = [self buttonWithTitle:@"Set reset time" action:@selector(setReset)];
    reset.frame = CGRectMake(14, 167, 232, 33);
    [self.details addSubview:reset];
}

- (void)attachIfPossible {
    UIWindow *window = [self normalWindow];
    if (!window || CGRectIsEmpty(window.bounds)) return;
    if (!self.panel) [self buildPanel];
    if (self.attachedWindow != window || self.panel.superview != window) {
        [self.panel removeFromSuperview];
        [window addSubview:self.panel];
        self.attachedWindow = window;
    }
    [window bringSubviewToFront:self.panel];
    [self layoutPanel];
    [self refresh];
}

- (void)layoutPanel {
    UIWindow *window = self.attachedWindow;
    if (!window) return;
    CGFloat width = self.expanded ? 260 : 188;
    CGFloat height = self.expanded ? 248 : 38;
    // Put the HUD just above the composer; when a keyboard is visible, move with it.
    CGFloat bottom = MAX(114.0, self.keyboardHeight + 115.0);
    CGFloat x = (CGRectGetWidth(window.bounds) - width) / 2.0 + self.dragShift.x;
    CGFloat y = CGRectGetHeight(window.bounds) - bottom - height + self.dragShift.y;
    x = MIN(MAX(x, 8), MAX(8, CGRectGetWidth(window.bounds) - width - 8));
    y = MIN(MAX(y, window.safeAreaInsets.top + 6),
            MAX(window.safeAreaInsets.top + 6, CGRectGetHeight(window.bounds) - height - 10));
    self.panel.frame = CGRectMake(x, y, width, height);
    self.topBar.frame = CGRectMake(0, 0, width, 38);
    self.summary.frame = CGRectMake(29, 4, width - 41, 30);
    self.details.frame = CGRectMake(0, 38, width, 210);
    self.details.hidden = !self.expanded;
}

- (void)toggleDetails {
    self.expanded = !self.expanded;
    [UIView animateWithDuration:0.18 animations:^{ [self layoutPanel]; }];
    [self refresh];
}

- (void)pan:(UIPanGestureRecognizer *)pan {
    if (!self.attachedWindow) return;
    CGPoint delta = [pan translationInView:self.attachedWindow];
    self.dragShift = CGPointMake(self.dragShift.x + delta.x, self.dragShift.y + delta.y);
    [pan setTranslation:CGPointZero inView:self.attachedWindow];
    [self layoutPanel];
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect screenFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIWindow *window = self.attachedWindow;
    if (!window) return;
    CGRect converted = [window convertRect:screenFrame fromWindow:nil];
    self.keyboardHeight = CGRectIntersectsRect(converted, window.bounds) ?
        MAX(0, CGRectGetMaxY(window.bounds) - CGRectGetMinY(converted)) : 0;
    [self layoutPanel];
}

- (void)keyboardHidden:(NSNotification *)note {
    self.keyboardHeight = 0;
    [self layoutPanel];
}

- (void)nextModel {
    self.selectedModel = (self.selectedModel + 1) % CHModels().count;
    [[NSUserDefaults standardUserDefaults] setInteger:(NSInteger)self.selectedModel forKey:@"CHUsage.v1.model"];
    [self refresh];
}

- (void)setStoredRemaining:(NSInteger)value {
    [[NSUserDefaults standardUserDefaults] setInteger:MAX(0, value) forKey:[self storageKey:@"remaining"]];
    [self refresh];
}

- (void)setRemaining {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Manual allowance"
        message:@"Enter a remaining count. This is not verified by ChatGPT."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = @"e.g. 40";
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *s = alert.textFields.firstObject.text ?: @"";
        NSScanner *scanner = [NSScanner scannerWithString:s];
        long long n = -1;
        if ([scanner scanLongLong:&n] && scanner.isAtEnd && n >= 0 && n <= INT_MAX)
            [weakSelf setStoredRemaining:(NSInteger)n];
    }]];
    [self present:alert];
}

- (void)subtractOne {
    NSInteger left = [self remaining];
    if (left >= 0) [self setStoredRemaining:MAX(0, left - 1)];
}

- (void)setReset {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Reset reminder"
        message:@"Local timer only; it does not query ChatGPT."
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    NSArray<NSNumber *> *hours = @[@1, @3, @24, @168];
    NSArray<NSString *> *titles = @[@"In 1 hour", @"In 3 hours", @"In 24 hours", @"In 7 days"];
    for (NSUInteger i = 0; i < hours.count; i++) {
        NSTimeInterval seconds = hours[i].doubleValue * 3600.0;
        [sheet addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSTimeInterval timestamp = NSDate.date.timeIntervalSince1970 + seconds;
            [[NSUserDefaults standardUserDefaults] setDouble:timestamp forKey:[weakSelf storageKey:@"reset"]];
            [weakSelf refresh];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Clear" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[weakSelf storageKey:@"reset"]];
        [weakSelf refresh];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.details;
    sheet.popoverPresentationController.sourceRect = CGRectMake(130, 170, 1, 1);
    [self present:sheet];
}

- (void)present:(UIAlertController *)alert {
    UIViewController *root = self.attachedWindow.rootViewController;
    while (root.presentedViewController) root = root.presentedViewController;
    if (root && !root.isBeingDismissed) [root presentViewController:alert animated:YES completion:nil];
}

- (void)refresh {
    if (!self.panel) return;
    NSString *model = CHModels()[self.selectedModel];
    NSInteger count = [self remaining];
    NSDate *reset = [self resetDate];
    NSString *countText = count >= 0 ? [NSString stringWithFormat:@"%ld left", (long)count] : @"—";
    NSString *resetText = @"Reset: unknown";
    if (reset) {
        NSTimeInterval delta = [reset timeIntervalSinceNow];
        if (delta <= 0) resetText = @"Reset time reached (verify in ChatGPT)";
        else if (delta > 86400) resetText = [NSString stringWithFormat:@"Reset in %ldd %ldh", (long)(delta/86400), (long)(((NSInteger)delta%86400)/3600)];
        else resetText = [NSString stringWithFormat:@"Reset in %ldh %ldm", (long)(delta/3600), (long)(((NSInteger)delta%3600)/60)];
    }
    self.summary.text = count >= 0 ? [NSString stringWithFormat:@"%@ · %@ · manual", model, countText]
                                   : [NSString stringWithFormat:@"%@ · limits unavailable", model];
    [self.modelButton setTitle:[NSString stringWithFormat:@"Model: %@  ›", model] forState:UIControlStateNormal];
    self.value.text = count >= 0 ? [NSString stringWithFormat:@"%@ (manual)", countText] : @"Not available";
    self.resetLabel.text = resetText;
    self.usedButton.enabled = count > 0;
    self.usedButton.alpha = count > 0 ? 1.0 : 0.4;
}

@end

__attribute__((constructor))
static void CHUsageInitialize(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CHUsageOverlay shared] start];
    });
}
