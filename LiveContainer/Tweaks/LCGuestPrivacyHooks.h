#import "LCGuestPrivacyPolicy.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

// These are compatibility/privacy controls in a guest process, not a new
// sandbox. Install before guest code runs; never change TCC, system capture
// protections, privacy indicators, or a host-only SideStore process.
static inline BOOL LCPrivacyReplace(Class cls, SEL sel, IMP replacement) {
    if (!cls) { imp_removeBlock(replacement); return NO; }
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) { imp_removeBlock(replacement); return NO; }
    // Do not replace an inherited implementation on an unrelated superclass.
    if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) {
        class_replaceMethod(cls, sel, replacement, method_getTypeEncoding(method));
    }
    return YES;
}

static inline BOOL LCPrivacyCaptureTypeBlocked(NSString *type, BOOL camera, BOOL microphone) {
    return (camera && [type isEqualToString:AVMediaTypeVideo]) ||
           (microphone && [type isEqualToString:AVMediaTypeAudio]);
}

static inline BOOL LCPrivacyCaptureDeviceBlocked(AVCaptureDevice *device, BOOL camera, BOOL microphone) {
    return device && ((camera && [device hasMediaType:AVMediaTypeVideo]) ||
                      (microphone && [device hasMediaType:AVMediaTypeAudio]));
}

static inline NSError *LCPrivacyDeniedError(void) {
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError
                           userInfo:@{NSLocalizedDescriptionKey: @"Access restricted by LifeContainer+ guest privacy settings."}];
}

static inline void LCPrivacyInstallCapture(BOOL camera, BOOL microphone) {
    if (!camera && !microphone) return;
    Class meta = object_getClass(AVCaptureDevice.class);
    SEL status = @selector(authorizationStatusForMediaType:);
    AVAuthorizationStatus (*originalStatus)(id, SEL, AVMediaType) =
        (void *)class_getMethodImplementation(meta, status);
    LCPrivacyReplace(meta, status, imp_implementationWithBlock(^AVAuthorizationStatus(id self, AVMediaType type) {
        if (LCPrivacyCaptureTypeBlocked(type, camera, microphone)) return AVAuthorizationStatusDenied;
        return originalStatus(self, status, type);
    }));

    SEL access = @selector(requestAccessForMediaType:completionHandler:);
    void (*originalAccess)(id, SEL, AVMediaType, void (^)(BOOL)) =
        (void *)class_getMethodImplementation(meta, access);
    LCPrivacyReplace(meta, access, imp_implementationWithBlock(^(id self, AVMediaType type, void (^completion)(BOOL)) {
        if (LCPrivacyCaptureTypeBlocked(type, camera, microphone)) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            return;
        }
        originalAccess(self, access, type, completion);
    }));

    Class inputMeta = object_getClass(AVCaptureDeviceInput.class);
    SEL factory = @selector(deviceInputWithDevice:error:);
    AVCaptureDeviceInput *(*originalFactory)(id, SEL, AVCaptureDevice *, NSError **) =
        (void *)class_getMethodImplementation(inputMeta, factory);
    LCPrivacyReplace(inputMeta, factory, imp_implementationWithBlock(^AVCaptureDeviceInput *(id self, AVCaptureDevice *device, NSError **error) {
        if (LCPrivacyCaptureDeviceBlocked(device, camera, microphone)) {
            if (error) *error = LCPrivacyDeniedError();
            return nil;
        }
        return originalFactory(self, factory, device, error);
    }));

    Class session = AVCaptureSession.class;
    SEL canAdd = @selector(canAddInput:);
    BOOL (*originalCanAdd)(id, SEL, AVCaptureInput *) =
        (void *)class_getMethodImplementation(session, canAdd);
    LCPrivacyReplace(session, canAdd, imp_implementationWithBlock(^BOOL(id self, AVCaptureInput *input) {
        if ([input isKindOfClass:AVCaptureDeviceInput.class] &&
            LCPrivacyCaptureDeviceBlocked(((AVCaptureDeviceInput *)input).device, camera, microphone)) return NO;
        return originalCanAdd(self, canAdd, input);
    }));
    for (NSString *name in @[@"addInput:", @"addInputWithNoConnections:"]) {
        SEL selector = NSSelectorFromString(name);
        if (!class_getInstanceMethod(session, selector)) continue;
        void (*original)(id, SEL, AVCaptureInput *) =
            (void *)class_getMethodImplementation(session, selector);
        LCPrivacyReplace(session, selector, imp_implementationWithBlock(^(id self, AVCaptureInput *input) {
            if ([input isKindOfClass:AVCaptureDeviceInput.class] &&
                LCPrivacyCaptureDeviceBlocked(((AVCaptureDeviceInput *)input).device, camera, microphone)) return;
            original(self, selector, input);
        }));
    }

    if (camera) {
        Class pickerMeta = object_getClass(UIImagePickerController.class);
        SEL selector = @selector(isSourceTypeAvailable:);
        BOOL (*original)(id, SEL, UIImagePickerControllerSourceType) =
            (void *)class_getMethodImplementation(pickerMeta, selector);
        LCPrivacyReplace(pickerMeta, selector, imp_implementationWithBlock(^BOOL(id self, UIImagePickerControllerSourceType type) {
            return type == UIImagePickerControllerSourceTypeCamera ? NO : original(self, selector, type);
        }));
    }

    if (microphone) {
        // Standard permission APIs and AVAudioRecorder recording methods.
        // Do not disable playback or pretend to control arbitrary audio units.
        Class audioSession = AVAudioSession.class;
        LCPrivacyReplace(audioSession, @selector(recordPermission),
                         imp_implementationWithBlock(^NSUInteger(id self) { return AVAudioSessionRecordPermissionDenied; }));
        LCPrivacyReplace(audioSession, @selector(requestRecordPermission:),
                         imp_implementationWithBlock(^(id self, void (^completion)(BOOL)) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        }));
        Class audioApp = NSClassFromString(@"AVAudioApplication");
        if (audioApp) {
            LCPrivacyReplace(audioApp, NSSelectorFromString(@"recordPermission"),
                             imp_implementationWithBlock(^NSUInteger(id self) { return AVAudioSessionRecordPermissionDenied; }));
            LCPrivacyReplace(object_getClass(audioApp), NSSelectorFromString(@"requestRecordPermissionWithCompletionHandler:"),
                             imp_implementationWithBlock(^(id self, void (^completion)(BOOL)) {
                if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
            }));
        }
        Class recorder = AVAudioRecorder.class;
        for (NSString *name in @[@"prepareToRecord", @"record"]) {
            LCPrivacyReplace(recorder, NSSelectorFromString(name), imp_implementationWithBlock(^BOOL(id self) { return NO; }));
        }
        for (NSString *name in @[@"recordAtTime:", @"recordForDuration:"]) {
            LCPrivacyReplace(recorder, NSSelectorFromString(name), imp_implementationWithBlock(^BOOL(id self, NSTimeInterval value) { return NO; }));
        }
        LCPrivacyReplace(recorder, @selector(recordAtTime:forDuration:),
                         imp_implementationWithBlock(^BOOL(id self, NSTimeInterval time, NSTimeInterval duration) { return NO; }));
    }
}

static inline void LCPrivacyInstallDevice(BOOL battery, BOOL proximity) {
    UIDevice *device = UIDevice.currentDevice;
    Class cls = device.class;
    if (battery) {
        device.batteryMonitoringEnabled = NO;
        LCPrivacyReplace(cls, @selector(setBatteryMonitoringEnabled:),
                         imp_implementationWithBlock(^(id self, BOOL value) {}));
        LCPrivacyReplace(cls, @selector(isBatteryMonitoringEnabled),
                         imp_implementationWithBlock(^BOOL(id self) { return NO; }));
        LCPrivacyReplace(cls, @selector(batteryLevel),
                         imp_implementationWithBlock(^float(id self) { return -1.0f; }));
        LCPrivacyReplace(cls, @selector(batteryState),
                         imp_implementationWithBlock(^UIDeviceBatteryState(id self) { return UIDeviceBatteryStateUnknown; }));
    }
    if (proximity) {
        device.proximityMonitoringEnabled = NO;
        LCPrivacyReplace(cls, @selector(setProximityMonitoringEnabled:),
                         imp_implementationWithBlock(^(id self, BOOL value) {}));
        LCPrivacyReplace(cls, @selector(isProximityMonitoringEnabled),
                         imp_implementationWithBlock(^BOOL(id self) { return NO; }));
        LCPrivacyReplace(cls, @selector(proximityState),
                         imp_implementationWithBlock(^BOOL(id self) { return NO; }));
    }
}

static inline BOOL LCPrivacyEventBlocked(NSString *name, BOOL screenshots, BOOL battery, BOOL proximity) {
    // Explicitly named UIKit subscriptions only. Do not change screen-capture
    // state, secure content, capture indicators, or OS screenshot behavior.
    return (screenshots && [name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) ||
           (battery && ([name isEqualToString:UIDeviceBatteryLevelDidChangeNotification] ||
                        [name isEqualToString:UIDeviceBatteryStateDidChangeNotification])) ||
           (proximity && [name isEqualToString:UIDeviceProximityStateDidChangeNotification]);
}

static inline void LCPrivacyInstallEvents(BOOL screenshots, BOOL battery, BOOL proximity) {
    if (!screenshots && !battery && !proximity) return;
    Class cls = NSNotificationCenter.defaultCenter.class;
    SEL add = @selector(addObserver:selector:name:object:);
    void (*originalAdd)(id, SEL, id, SEL, NSString *, id) =
        (void *)class_getMethodImplementation(cls, add);
    LCPrivacyReplace(cls, add, imp_implementationWithBlock(^(id self, id observer, SEL selector, NSString *name, id object) {
        if (LCPrivacyEventBlocked(name, screenshots, battery, proximity)) return;
        originalAdd(self, add, observer, selector, name, object);
    }));
    SEL addBlock = @selector(addObserverForName:object:queue:usingBlock:);
    id (*originalBlock)(id, SEL, NSString *, id, NSOperationQueue *, void (^)(NSNotification *)) =
        (void *)class_getMethodImplementation(cls, addBlock);
    LCPrivacyReplace(cls, addBlock, imp_implementationWithBlock(^id(id self, NSString *name, id object, NSOperationQueue *queue, void (^handler)(NSNotification *)) {
        if (LCPrivacyEventBlocked(name, screenshots, battery, proximity)) {
            // Keep a valid, removable observer token; do not deliver the event.
            return originalBlock(self, addBlock, name, object, queue, ^(NSNotification *note) {});
        }
        return originalBlock(self, addBlock, name, object, queue, handler);
    }));
}

static inline void LCGuestPrivacyHooksInit(NSDictionary *info) {
    BOOL camera = LCGuestPrivacyEnabled(info, @"camera");
    BOOL microphone = LCGuestPrivacyEnabled(info, @"microphone");
    BOOL battery = LCGuestPrivacyEnabled(info, @"battery");
    BOOL proximity = LCGuestPrivacyEnabled(info, @"proximity");
    BOOL screenshots = LCGuestPrivacyEnabled(info, @"screenshotEvents");
    LCPrivacyInstallCapture(camera, microphone);
    if (battery || proximity) LCPrivacyInstallDevice(battery, proximity);
    LCPrivacyInstallEvents(screenshots, battery, proximity);
}
