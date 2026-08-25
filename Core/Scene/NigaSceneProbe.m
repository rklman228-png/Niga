#import "NigaSceneProbe.h"
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static BOOL loadFramework(NSString *path) {
    return dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL) != NULL;
}

static BOOL classHasClassSelector(Class cls, NSString *selectorName) {
    if (!cls) return NO;
    SEL sel = NSSelectorFromString(selectorName);
    return [cls respondsToSelector:sel];
}

static BOOL objectHasSelector(id object, NSString *selectorName) {
    if (!object) return NO;
    return [object respondsToSelector:NSSelectorFromString(selectorName)];
}

static id callClass1(Class cls, NSString *selectorName, id arg) {
    if (!cls) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![cls respondsToSelector:sel]) return nil;
    id (*send)(id, SEL, id) = (void *)objc_msgSend;
    return send(cls, sel, arg);
}

static id callClass0(Class cls, NSString *selectorName) {
    if (!cls) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![cls respondsToSelector:sel]) return nil;
    id (*send)(id, SEL) = (void *)objc_msgSend;
    return send(cls, sel);
}

static id callClass2(Class cls, NSString *selectorName, id arg1, id arg2) {
    if (!cls) return nil;
    SEL sel = NSSelectorFromString(selectorName);
    if (![cls respondsToSelector:sel]) return nil;
    id (*send)(id, SEL, id, id) = (void *)objc_msgSend;
    return send(cls, sel, arg1, arg2);
}

static NSDictionary *entitlementProbe(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW | RTLD_LOCAL);
    if (!security) {
        out[@"securityFramework"] = @NO;
        return out;
    }
    out[@"securityFramework"] = @YES;

    typedef CFTypeRef (*SecTaskCreateFromSelfFn)(CFAllocatorRef allocator);
    typedef CFTypeRef (*SecTaskCopyValueForEntitlementFn)(CFTypeRef task, CFStringRef entitlement, CFErrorRef *error);
    SecTaskCreateFromSelfFn createTask = (SecTaskCreateFromSelfFn)dlsym(security, "SecTaskCreateFromSelf");
    SecTaskCopyValueForEntitlementFn copyEntitlement = (SecTaskCopyValueForEntitlementFn)dlsym(security, "SecTaskCopyValueForEntitlement");
    if (!createTask || !copyEntitlement) {
        out[@"secTaskAPI"] = @NO;
        dlclose(security);
        return out;
    }
    out[@"secTaskAPI"] = @YES;
    CFTypeRef task = createTask(kCFAllocatorDefault);
    if (!task) {
        out[@"task"] = @NO;
        dlclose(security);
        return out;
    }

    NSArray<NSString *> *keys = @[
        @"com.apple.frontboard.launchapplications",
        @"com.apple.runningboard.launchprocess",
        @"com.apple.runningboard.targetidentities",
        @"com.apple.runningboard.process-state",
        @"com.apple.springboard-ui.client",
        @"com.apple.QuartzCore.displayable-context",
        @"platform-application",
        @"com.apple.private.security.no-sandbox"
    ];
    for (NSString *key in keys) {
        CFErrorRef error = NULL;
        CFTypeRef value = copyEntitlement(task, (__bridge CFStringRef)key, &error);
        if (value) {
            out[key] = CFBridgingRelease(value);
        } else {
            out[key] = [NSNull null];
        }
        if (error) CFRelease(error);
    }
    CFRelease(task);
    dlclose(security);
    return out;
}

char *niga_scene_probe_json(const char *bundle_id) {
    @autoreleasepool {
        NSString *bundleID = bundle_id ? [NSString stringWithUTF8String:bundle_id] : @"";
        NSMutableDictionary *report = [NSMutableDictionary dictionary];
        report[@"bundleID"] = bundleID;
        report[@"systemVersion"] = NSProcessInfo.processInfo.operatingSystemVersionString;

        NSDictionary<NSString *, NSString *> *frameworks = @{
            @"FrontBoard": @"/System/Library/PrivateFrameworks/FrontBoard.framework/FrontBoard",
            @"FrontBoardServices": @"/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",
            @"RunningBoardServices": @"/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices",
            @"SpringBoardServices": @"/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices"
        };
        NSMutableDictionary *frameworkReport = [NSMutableDictionary dictionary];
        [frameworks enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *path, BOOL *stop) {
            frameworkReport[name] = @(loadFramework(path));
        }];
        report[@"frameworks"] = frameworkReport;

        NSArray<NSString *> *classNames = @[
            @"FBSceneManager",
            @"FBScene",
            @"FBSMutableSceneDefinition",
            @"FBSMutableSceneParameters",
            @"FBSSceneIdentity",
            @"FBSSceneClientIdentity",
            @"UIApplicationSceneSpecification",
            @"UIMutableApplicationSceneSettings",
            @"UIMutableApplicationSceneClientSettings",
            @"RBSProcessIdentity",
            @"RBSProcessPredicate",
            @"RBSProcessHandle",
            @"LSApplicationWorkspace",
            @"_UISceneHostingController",
            @"_UISceneHostingControllerAdvancedConfiguration"
        ];
        NSMutableDictionary *classes = [NSMutableDictionary dictionary];
        for (NSString *name in classNames) classes[name] = @(NSClassFromString(name) != Nil);
        report[@"classes"] = classes;

        Class sceneManagerClass = NSClassFromString(@"FBSceneManager");
        id sceneManager = callClass0(sceneManagerClass, @"sharedInstance");
        report[@"FBSceneManager.sharedInstance"] = @(sceneManager != nil);
        report[@"FBSceneManager.createScene"] = @(objectHasSelector(sceneManager, @"createSceneWithDefinition:initialParameters:"));
        report[@"FBSceneManager.destroyScene"] = @(objectHasSelector(sceneManager, @"destroyScene:withTransitionContext:"));

        Class rbsIdentityClass = NSClassFromString(@"RBSProcessIdentity");
        report[@"RBS.identitySelector"] = @(classHasClassSelector(rbsIdentityClass, @"identityForEmbeddedApplicationIdentifier:"));
        id identity = bundleID.length ? callClass1(rbsIdentityClass, @"identityForEmbeddedApplicationIdentifier:", bundleID) : nil;
        report[@"RBS.identityCreated"] = @(identity != nil);

        Class predicateClass = NSClassFromString(@"RBSProcessPredicate");
        id predicate = identity ? callClass1(predicateClass, @"predicateMatchingIdentity:", identity) : nil;
        report[@"RBS.predicateCreated"] = @(predicate != nil);

        Class handleClass = NSClassFromString(@"RBSProcessHandle");
        id processHandle = predicate ? callClass2(handleClass, @"handleForPredicate:error:", predicate, nil) : nil;
        report[@"RBS.processHandleForRunningApp"] = @(processHandle != nil);
        if (processHandle && [processHandle respondsToSelector:NSSelectorFromString(@"pid")]) {
            NSInteger (*sendPid)(id, SEL) = (void *)objc_msgSend;
            NSInteger pid = sendPid(processHandle, NSSelectorFromString(@"pid"));
            report[@"RBS.pid"] = @(pid);
        }

        Class sceneDefClass = NSClassFromString(@"FBSMutableSceneDefinition");
        report[@"FBS.definitionFactory"] = @(classHasClassSelector(sceneDefClass, @"definition"));
        Class sceneParamsClass = NSClassFromString(@"FBSMutableSceneParameters");
        report[@"FBS.parametersFactory"] = @(classHasClassSelector(sceneParamsClass, @"parametersForSpecification:"));
        Class sceneSpecClass = NSClassFromString(@"UIApplicationSceneSpecification");
        report[@"UIKit.sceneSpecificationFactory"] = @(classHasClassSelector(sceneSpecClass, @"specification"));

        report[@"entitlements"] = entitlementProbe();
        report[@"note"] = @"Probe is read-only: it only loads frameworks, checks classes/selectors, creates an RBS identity/predicate, and asks whether a handle exists for an already-running target. It does not create, resize, destroy, or modify an external app scene.";

        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) error:&error];
        if (!json || error) {
            NSString *fallback = [NSString stringWithFormat:@"{\"error\":\"%@\"}", error.localizedDescription ?: @"serialization failed"];
            return strdup(fallback.UTF8String);
        }
        NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        return strdup(text.UTF8String);
    }
}

void niga_scene_probe_free(char *value) {
    if (value) free(value);
}
