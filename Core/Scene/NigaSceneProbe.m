#import "NigaSceneProbe.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>

static BOOL loadFramework(NSString *path) {
    return dlopen(path.UTF8String, RTLD_NOW | RTLD_LOCAL) != NULL;
}

static BOOL classHasClassSelector(Class cls, NSString *selectorName) {
    if (!cls) return NO;
    return [cls respondsToSelector:NSSelectorFromString(selectorName)];
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

static BOOL selectorInteresting(NSString *name) {
    NSArray<NSString *> *needles = @[
        @"scene", @"frame", @"size", @"orientation", @"setting", @"host",
        @"present", @"window", @"display", @"geometry", @"update", @"create",
        @"activate", @"workspace", @"stage", @"multitask", @"application"
    ];
    NSString *lower = name.lowercaseString;
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) return YES;
    }
    return NO;
}

static NSArray<NSString *> *filteredMethodsForClass(Class cls, BOOL classMethods) {
    if (!cls) return @[];
    Class target = classMethods ? object_getClass(cls) : cls;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    if (!methods) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        if (selectorInteresting(name)) [out addObject:name];
        if (out.count >= 100) break;
    }
    free(methods);
    [out sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return out;
}

static NSDictionary *currentAppReport(void) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    UIDevice *device = UIDevice.currentDevice;
    out[@"userInterfaceIdiom"] = @(device.userInterfaceIdiom);
    out[@"model"] = device.model ?: @"";
    out[@"systemVersion"] = device.systemVersion ?: @"";
    out[@"screenBounds"] = NSStringFromCGRect(UIScreen.mainScreen.bounds);
    out[@"screenScale"] = @(UIScreen.mainScreen.scale);

    NSMutableArray *scenes = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        item[@"class"] = NSStringFromClass(scene.class);
        item[@"activationState"] = @(scene.activationState);
        item[@"sessionRole"] = scene.session.role ?: @"";
        item[@"persistentIdentifier"] = scene.session.persistentIdentifier ?: @"";
        if ([scene isKindOfClass:UIWindowScene.class]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            item[@"interfaceOrientation"] = @(ws.interfaceOrientation);
            item[@"coordinateBounds"] = NSStringFromCGRect(ws.coordinateSpace.bounds);
            item[@"windowCount"] = @(ws.windows.count);
            UIWindow *key = nil;
            for (UIWindow *window in ws.windows) {
                if (window.isKeyWindow) { key = window; break; }
            }
            if (key) {
                item[@"keyWindowFrame"] = NSStringFromCGRect(key.frame);
                item[@"keyWindowSafeArea"] = NSStringFromUIEdgeInsets(key.safeAreaInsets);
            }
        }
        [scenes addObject:item];
    }
    out[@"connectedScenes"] = scenes;
    return out;
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
        @"com.apple.runningboard.assertions.frontboard",
        @"com.apple.runningboard.terminateprocess",
        @"com.apple.springboard-ui.client",
        @"com.apple.QuartzCore.displayable-context",
        @"com.apple.QuartzCore.secure-mode",
        @"com.apple.backboard.client",
        @"platform-application",
        @"com.apple.private.security.no-sandbox"
    ];

    for (NSString *key in keys) {
        CFErrorRef error = NULL;
        CFTypeRef value = copyEntitlement(task, (__bridge CFStringRef)key, &error);
        out[key] = value ? CFBridgingRelease(value) : [NSNull null];
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
        report[@"currentApp"] = currentAppReport();

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
            @"FBSceneManager", @"FBScene", @"FBSMutableSceneDefinition", @"FBSMutableSceneParameters",
            @"FBSSceneIdentity", @"FBSSceneClientIdentity", @"UIApplicationSceneSpecification",
            @"UIMutableApplicationSceneSettings", @"UIMutableApplicationSceneClientSettings",
            @"UIMutableScenePresentationContext", @"RBSProcessIdentity", @"RBSProcessPredicate",
            @"RBSProcessHandle", @"LSApplicationWorkspace", @"_UIScenePresenter",
            @"_UISceneHostingController", @"_UISceneHostingControllerAdvancedConfiguration"
        ];

        NSMutableDictionary *classes = [NSMutableDictionary dictionary];
        NSMutableDictionary *methods = [NSMutableDictionary dictionary];
        for (NSString *name in classNames) {
            Class cls = NSClassFromString(name);
            classes[name] = @(cls != Nil);
            if (cls) {
                methods[name] = @{
                    @"instance": filteredMethodsForClass(cls, NO),
                    @"class": filteredMethodsForClass(cls, YES)
                };
            }
        }
        report[@"classes"] = classes;
        report[@"interestingMethods"] = methods;

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
            report[@"RBS.pid"] = @(sendPid(processHandle, NSSelectorFromString(@"pid")));
        }

        Class sceneDefClass = NSClassFromString(@"FBSMutableSceneDefinition");
        report[@"FBS.definitionFactory"] = @(classHasClassSelector(sceneDefClass, @"definition"));
        Class sceneParamsClass = NSClassFromString(@"FBSMutableSceneParameters");
        report[@"FBS.parametersFactory"] = @(classHasClassSelector(sceneParamsClass, @"parametersForSpecification:"));
        Class sceneSpecClass = NSClassFromString(@"UIApplicationSceneSpecification");
        report[@"UIKit.sceneSpecificationFactory"] = @(classHasClassSelector(sceneSpecClass, @"specification"));

        report[@"entitlements"] = entitlementProbe();
        report[@"note"] = @"Read-only probe. It does not create, resize, destroy, launch, terminate, or modify an external app scene.";

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
