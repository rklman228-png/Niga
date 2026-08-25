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
    pid = integer0(handle, @"pid", -1);
    return pid;
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
        report[@"bundleID"] = bundleID;
        report[@"requestedFrame"] = NSStringFromCGRect(CGRectMake(x, y, width, height));
        report[@"requestedOrientation"] = @(orientation);
        report[@"alwaysOnTop"] = @(always_on_top);
        report[@"applied"] = @NO;

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

        SEL updateSel = NSSelectorFromString(@"updateSettingsWithBlock:");
        if (![matchedScene respondsToSelector:updateSel]) {
            report[@"error"] = @"Matched scene has no updateSettingsWithBlock:";
            return jsonReturn(report);
        }

        CGRect frame = CGRectMake(x, y, width, height);
        NSInteger interfaceOrientation = orientation;
        if (interfaceOrientation < 1 || interfaceOrientation > 4) interfaceOrientation = 0;

        void (^settingsBlock)(id) = ^(id settings) {
            @try {
                [settings setValue:[NSValue valueWithCGRect:frame] forKey:@"frame"];
                if (interfaceOrientation != 0) {
                    [settings setValue:@(interfaceOrientation) forKey:@"interfaceOrientation"];
                    [settings setValue:@(interfaceOrientation) forKey:@"deviceOrientation"];
                }
                if (always_on_top) {
                    [settings setValue:@(1000) forKey:@"level"];
                }
            } @catch (__unused NSException *exception) {
            }
        };

        @try {
            void (*update)(id, SEL, id) = (void *)objc_msgSend;
            update(matchedScene, updateSel, settingsBlock);
            report[@"applied"] = @YES;
            report[@"note"] = @"FrontBoard accepted the update call. Visual effect still depends on SpringBoard policy and entitlements.";
        } @catch (NSException *exception) {
            report[@"error"] = [NSString stringWithFormat:@"Scene update threw %@: %@", exception.name, exception.reason ?: @""];
        }

        return jsonReturn(report);
    }
}

void niga_scene_control_free(char *value) {
    if (value) free(value);
}
