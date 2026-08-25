#import "NigaSceneControl.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static void loadSceneFrameworks(void) {
    dlopen("/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard", RTLD_NOW | RTLD_LOCAL);
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_NOW | RTLD_LOCAL);
    dlopen("/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices", RTLD_NOW | RTLD_LOCAL);
}

static id send0(id obj, NSString *selectorName) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    id (*send)(id, SEL) = (void *)objc_msgSend;
    return send(obj, sel);
}

static id send1(id obj, NSString *selectorName, id arg) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    id (*send)(id, SEL, id) = (void *)objc_msgSend;
    return send(obj, sel, arg);
}

static id send2(id obj, NSString *selectorName, id arg1, id arg2) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    id (*send)(id, SEL, id, id) = (void *)objc_msgSend;
    return send(obj, sel, arg1, arg2);
}

static NSInteger integer0(id obj, NSString *selectorName, NSInteger fallback) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!obj || ![obj respondsToSelector:sel]) return fallback;
    NSInteger (*send)(id, SEL) = (void *)objc_msgSend;
    return send(obj, sel);
}

static CGRect rect0(id obj, NSString *selectorName, CGRect fallback) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!obj || ![obj respondsToSelector:sel]) return fallback;
    CGRect (*send)(id, SEL) = (void *)objc_msgSend;
    return send(obj, sel);
}

static BOOL setRect(id obj, NSString *selectorName, CGRect value) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    void (*send)(id, SEL, CGRect) = (void *)objc_msgSend;
    send(obj, sel, value);
    return YES;
}

static BOOL setInteger(id obj, NSString *selectorName, NSInteger value) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    void (*send)(id, SEL, NSInteger) = (void *)objc_msgSend;
    send(obj, sel, value);
    return YES;
}

static BOOL setBool(id obj, NSString *selectorName, BOOL value) {
    SEL sel = NSSelectorFromString(selectorName);
    if (!obj || ![obj respondsToSelector:sel]) return NO;
    void (*send)(id, SEL, BOOL) = (void *)objc_msgSend;
    send(obj, sel, value);
    return YES;
}

static char *jsonReturn(NSDictionary *report) {
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) error:&error];
    if (!json) {
        NSString *fallback = [NSString stringWithFormat:@"{\"error\":\"%@\"}", error.localizedDescription ?: @"serialization failed"];
        return strdup(fallback.UTF8String);
    }
    NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    return strdup(text.UTF8String);
}

static int targetPID(NSString *bundleID, NSMutableDictionary *report) {
    Class identityClass = NSClassFromString(@"RBSProcessIdentity");
    id identity = send1(identityClass, @"identityForEmbeddedApplicationIdentifier:", bundleID);
    if (!identity) {
        report[@"error"] = @"Could not create RBSProcessIdentity";
        return -1;
    }

    Class predicateClass = NSClassFromString(@"RBSProcessPredicate");
    id predicate = send1(predicateClass, @"predicateMatchingIdentity:", identity);
    if (!predicate) {
        report[@"error"] = @"Could not create RBSProcessPredicate";
        return -1;
    }

    Class handleClass = NSClassFromString(@"RBSProcessHandle");
    id handle = send2(handleClass, @"handleForPredicate:error:", predicate, nil);
    if (!handle) {
        report[@"error"] = @"Target is not running or process-handle lookup is blocked";
        return -1;
    }

    NSInteger pid = integer0(handle, @"pid", -1);
    report[@"targetPID"] = @(pid);
    return (int)pid;
}

static NSInteger scenePID(id scene) {
    id process = send0(scene, @"clientProcess");
    NSInteger pid = integer0(process, @"pid", -1);
    if (pid > 0) return pid;

    id handle = send0(scene, @"clientHandle");
    return integer0(handle, @"pid", -1);
}

static NSString *sceneIdentifier(id scene) {
    id value = send0(scene, @"identifier");
    return [value isKindOfClass:NSString.class] ? value : @"";
}

char *niga_scene_apply_profile(const char *bundle_id,
                               double x,
                               double y,
                               double width,
                               double height,
                               int orientation,
                               bool always_on_top) {
    @autoreleasepool {
        NSMutableDictionary *report = [NSMutableDictionary dictionary];
        NSString *bundleID = bundle_id ? [NSString stringWithUTF8String:bundle_id] : @"";
        CGRect requestedFrame = CGRectMake(x, y, width, height);

        report[@"bundleID"] = bundleID;
        report[@"requestedFrame"] = NSStringFromCGRect(requestedFrame);
        report[@"requestedOrientation"] = @(orientation);
        report[@"alwaysOnTop"] = @(always_on_top);
        report[@"applied"] = @NO;
        report[@"frameSetterCalled"] = @NO;
        report[@"orientationSetterCalled"] = @NO;

        if (bundleID.length == 0) {
            report[@"error"] = @"Bundle ID is empty";
            return jsonReturn(report);
        }

        loadSceneFrameworks();
        int pid = targetPID(bundleID, report);
        if (pid <= 0) return jsonReturn(report);

        Class managerClass = NSClassFromString(@"FBSceneManager");
        id manager = send0(managerClass, @"sharedInstance");
        SEL enumerateSel = NSSelectorFromString(@"enumerateScenesWithBlock:");
        if (!manager || ![manager respondsToSelector:enumerateSel]) {
            report[@"error"] = @"FBSceneManager enumeration unavailable in this process";
            return jsonReturn(report);
        }

        __block id matchedScene = nil;
        void (^enumerator)(id, BOOL *) = ^(id scene, BOOL *stop) {
            NSInteger candidatePID = scenePID(scene);
            NSString *identifier = sceneIdentifier(scene);
            if (candidatePID == pid || (identifier.length && [identifier containsString:bundleID])) {
                matchedScene = scene;
                if (stop) *stop = YES;
            }
        };

        @try {
            void (*enumerate)(id, SEL, id) = (void *)objc_msgSend;
            enumerate(manager, enumerateSel, enumerator);
        } @catch (NSException *exception) {
            report[@"error"] = [NSString stringWithFormat:@"Scene enumeration threw %@: %@", exception.name, exception.reason ?: @""];
            return jsonReturn(report);
        }

        if (!matchedScene) {
            report[@"error"] = @"No external FBScene for the running target is visible to this signed process";
            return jsonReturn(report);
        }

        report[@"sceneIdentifier"] = sceneIdentifier(matchedScene);
        report[@"sceneClass"] = NSStringFromClass([matchedScene class]);

        id beforeSettings = send0(matchedScene, @"settings");
        CGRect beforeFrame = rect0(beforeSettings, @"frame", CGRectNull);
        if (!CGRectIsNull(beforeFrame)) report[@"beforeFrame"] = NSStringFromCGRect(beforeFrame);
        NSInteger beforeOrientation = integer0(beforeSettings, @"interfaceOrientation", -1);
        if (beforeOrientation >= 0) report[@"beforeOrientation"] = @(beforeOrientation);

        SEL updateSel = NSSelectorFromString(@"updateSettingsWithBlock:");
        if (![matchedScene respondsToSelector:updateSel]) {
            report[@"error"] = @"Matched scene has no updateSettingsWithBlock:";
            return jsonReturn(report);
        }

        NSInteger interfaceOrientation = orientation;
        if (interfaceOrientation < 1 || interfaceOrientation > 4) interfaceOrientation = 0;

        __block BOOL frameSetterCalled = NO;
        __block BOOL orientationSetterCalled = NO;
        __block NSString *mutationError = nil;

        void (^settingsBlock)(id) = ^(id settings) {
            @try {
                frameSetterCalled = setRect(settings, @"setFrame:", requestedFrame);
                setBool(settings, @"setForeground:", YES);

                if (interfaceOrientation != 0) {
                    BOOL interfaceSet = setInteger(settings, @"setInterfaceOrientation:", interfaceOrientation);
                    BOOL deviceSet = setInteger(settings, @"setDeviceOrientation:", interfaceOrientation);
                    orientationSetterCalled = interfaceSet || deviceSet;
                }

                if (always_on_top) {
                    setInteger(settings, @"setLevel:", 1000);
                }
            } @catch (NSException *exception) {
                mutationError = [NSString stringWithFormat:@"Settings mutation threw %@: %@", exception.name, exception.reason ?: @""];
            }
        };

        @try {
            void (*update)(id, SEL, id) = (void *)objc_msgSend;
            update(matchedScene, updateSel, settingsBlock);
        } @catch (NSException *exception) {
            report[@"error"] = [NSString stringWithFormat:@"Scene update threw %@: %@", exception.name, exception.reason ?: @""];
            return jsonReturn(report);
        }

        report[@"frameSetterCalled"] = @(frameSetterCalled);
        report[@"orientationSetterCalled"] = @(orientationSetterCalled);
        if (mutationError) report[@"mutationError"] = mutationError;

        id afterSettings = send0(matchedScene, @"settings");
        CGRect afterFrame = rect0(afterSettings, @"frame", CGRectNull);
        NSInteger afterOrientation = integer0(afterSettings, @"interfaceOrientation", -1);

        if (!CGRectIsNull(afterFrame)) report[@"afterFrame"] = NSStringFromCGRect(afterFrame);
        if (afterOrientation >= 0) report[@"afterOrientation"] = @(afterOrientation);

        BOOL frameMatches = frameSetterCalled && !CGRectIsNull(afterFrame) && CGRectEqualToRect(afterFrame, requestedFrame);
        BOOL orientationMatches = (interfaceOrientation == 0) || (afterOrientation == interfaceOrientation);

        report[@"frameVerified"] = @(frameMatches);
        report[@"orientationVerified"] = @(orientationMatches);
        report[@"applied"] = @(frameMatches && orientationMatches);

        if (frameMatches && orientationMatches) {
            report[@"note"] = @"FrontBoard re-read matches the requested frame/orientation. SpringBoard may still animate or clamp the visible window afterwards.";
        } else if (!frameSetterCalled) {
            report[@"error"] = @"The mutable scene settings object does not expose setFrame: in this runtime/signature.";
        } else {
            report[@"error"] = @"FrontBoard accepted the update call but the re-read scene settings do not match the requested geometry. SpringBoard policy or signing likely rejected/clamped it.";
        }

        return jsonReturn(report);
    }
}

void niga_scene_control_free(char *value) {
    if (value) free(value);
}
