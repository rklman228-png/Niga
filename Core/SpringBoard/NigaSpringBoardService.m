#import "NigaSpringBoardService.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

static void *gSpringBoardServicesHandle;
static void *gSpringBoardFoundationHandle;
static void *gFrontBoardServicesHandle;

typedef void (*SBSUpdateWindowingModeFn)(uint64_t mode, void (^completion)(void));
typedef void (*SBSResetLayoutAttributesFn)(void (^completion)(void));
typedef uint64_t (*SBFEffectiveDeviceClassFn)(void);
typedef bool (*SBFBoolFunctionFn)(void);
typedef bool (*OSVariantInternalDiagnosticsFn)(const char *subsystem);

static void *NigaLoadSpringBoardServices(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSpringBoardServicesHandle = dlopen(
            "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
            RTLD_NOW | RTLD_LOCAL
        );
    });
    return gSpringBoardServicesHandle;
}

static void *NigaLoadSpringBoardFoundation(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gSpringBoardFoundationHandle = dlopen(
            "/System/Library/PrivateFrameworks/SpringBoardFoundation.framework/SpringBoardFoundation",
            RTLD_NOW | RTLD_LOCAL
        );
    });
    return gSpringBoardFoundationHandle;
}

static void *NigaLoadFrontBoardServices(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gFrontBoardServicesHandle = dlopen(
            "/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",
            RTLD_NOW | RTLD_LOCAL
        );
    });
    return gFrontBoardServicesHandle;
}

static SBSUpdateWindowingModeFn NigaUpdateFunction(void)
{
    void *handle = NigaLoadSpringBoardServices();
    if (!handle) return NULL;
    return (SBSUpdateWindowingModeFn)dlsym(handle, "SBSRequestUpdateSwitcherWindowingMode");
}

static SBSResetLayoutAttributesFn NigaResetFunction(void)
{
    void *handle = NigaLoadSpringBoardServices();
    if (!handle) return NULL;
    return (SBSResetLayoutAttributesFn)dlsym(handle, "SBSRequestResetLayoutAttributes");
}

static SBFEffectiveDeviceClassFn NigaEffectiveDeviceClassFunction(void)
{
    void *handle = NigaLoadSpringBoardFoundation();
    if (!handle) return NULL;
    return (SBFEffectiveDeviceClassFn)dlsym(handle, "SBFEffectiveDeviceClass");
}

static BOOL NigaClassFallbackAvailable(void)
{
    NigaLoadSpringBoardServices();
    Class cls = NSClassFromString(@"SBSAppSwitcherSystemService");
    if (!cls) return NO;
    id instance = [[cls alloc] init];
    return instance && [instance respondsToSelector:NSSelectorFromString(@"requestUpdateWindowingMode:withCompletion:")];
}

bool niga_sbs_windowing_service_available(void)
{
    return NigaUpdateFunction() != NULL || NigaClassFallbackAvailable();
}

int64_t niga_sbs_effective_device_class(void)
{
    @autoreleasepool {
        SBFEffectiveDeviceClassFn fn = NigaEffectiveDeviceClassFunction();
        if (!fn) return -999;
        return (int64_t)fn();
    }
}

static void NigaFinish(NigaSpringBoardCompletion completion, bool completed)
{
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(completed);
    });
}

void niga_sbs_request_windowing_mode(int mode, NigaSpringBoardCompletion completion)
{
    @autoreleasepool {
        if (mode < 0 || mode > 2) {
            NigaFinish(completion, false);
            return;
        }

        SBSUpdateWindowingModeFn fn = NigaUpdateFunction();
        if (fn) {
            @try {
                fn((uint64_t)mode, ^{
                    NigaFinish(completion, true);
                });
            } @catch (__unused NSException *exception) {
                NigaFinish(completion, false);
            }
            return;
        }

        NigaLoadSpringBoardServices();
        Class cls = NSClassFromString(@"SBSAppSwitcherSystemService");
        SEL selector = NSSelectorFromString(@"requestUpdateWindowingMode:withCompletion:");
        id service = cls ? [[cls alloc] init] : nil;
        if (!service || ![service respondsToSelector:selector]) {
            NigaFinish(completion, false);
            return;
        }

        @try {
            __block id retainedService = service;
            void (^serverCompletion)(void) = ^{
                retainedService = nil;
                NigaFinish(completion, true);
            };
            void (*send)(id, SEL, int, id) = (void *)objc_msgSend;
            send(service, selector, mode, serverCompletion);
        } @catch (__unused NSException *exception) {
            NigaFinish(completion, false);
        }
    }
}

void niga_sbs_request_reset_layout(NigaSpringBoardCompletion completion)
{
    @autoreleasepool {
        SBSResetLayoutAttributesFn fn = NigaResetFunction();
        if (fn) {
            @try {
                fn(^{
                    NigaFinish(completion, true);
                });
            } @catch (__unused NSException *exception) {
                NigaFinish(completion, false);
            }
            return;
        }

        NigaLoadSpringBoardServices();
        Class cls = NSClassFromString(@"SBSAppSwitcherSystemService");
        SEL selector = NSSelectorFromString(@"requestResetLayoutAttributesWithCompletion:");
        id service = cls ? [[cls alloc] init] : nil;
        if (!service || ![service respondsToSelector:selector]) {
            NigaFinish(completion, false);
            return;
        }

        @try {
            __block id retainedService = service;
            void (^serverCompletion)(void) = ^{
                retainedService = nil;
                NigaFinish(completion, true);
            };
            void (*send)(id, SEL, id) = (void *)objc_msgSend;
            send(service, selector, serverCompletion);
        } @catch (__unused NSException *exception) {
            NigaFinish(completion, false);
        }
    }
}

char *niga_sbs_copy_diagnostics(void)
{
    @autoreleasepool {
        void *handle = NigaLoadSpringBoardServices();
        SBSUpdateWindowingModeFn update = NigaUpdateFunction();
        SBSResetLayoutAttributesFn reset = NigaResetFunction();
        Class cls = NSClassFromString(@"SBSAppSwitcherSystemService");
        id service = cls ? [[cls alloc] init] : nil;
        BOOL classUpdate = service && [service respondsToSelector:NSSelectorFromString(@"requestUpdateWindowingMode:withCompletion:")];
        BOOL classReset = service && [service respondsToSelector:NSSelectorFromString(@"requestResetLayoutAttributesWithCompletion:")];

        NSString *text = [NSString stringWithFormat:
            @"SpringBoardServices dlopen: %@\n"
             "SBSRequestUpdateSwitcherWindowingMode: %@\n"
             "SBSRequestResetLayoutAttributes: %@\n"
             "SBSAppSwitcherSystemService class: %@\n"
             "class update selector: %@\n"
             "class reset selector: %@",
            handle ? @"yes" : @"NO",
            update ? @"yes" : @"NO",
            reset ? @"yes" : @"NO",
            cls ? @"yes" : @"NO",
            classUpdate ? @"yes" : @"NO",
            classReset ? @"yes" : @"NO"
        ];
        return strdup(text.UTF8String ?: "diagnostics unavailable");
    }
}

char *niga_sbs_copy_gate_diagnostics(void)
{
    @autoreleasepool {
        void *sbs = NigaLoadSpringBoardServices();
        void *sbf = NigaLoadSpringBoardFoundation();
        void *fbs = NigaLoadFrontBoardServices();

        SBFEffectiveDeviceClassFn effectiveClassFn = NigaEffectiveDeviceClassFunction();
        SBFBoolFunctionFn flexibleUIFn = sbf
            ? (SBFBoolFunctionFn)dlsym(sbf, "SBFIsFlexibleWindowingUIAvailable")
            : NULL;

        NSInteger effectiveClass = effectiveClassFn ? (NSInteger)effectiveClassFn() : -999;
        NSInteger flexibleUI = flexibleUIFn ? (flexibleUIFn() ? 1 : 0) : -1;

        Class emulationClass = NSClassFromString(@"FBSDeviceEmulationConfiguration");
        SEL isEmulatedSEL = NSSelectorFromString(@"isEmulatedDevice");
        SEL emulatedClassSEL = NSSelectorFromString(@"emulatedDeviceClass");
        BOOL canReadEmulation = emulationClass && [emulationClass respondsToSelector:isEmulatedSEL];
        BOOL canReadEmulatedClass = emulationClass && [emulationClass respondsToSelector:emulatedClassSEL];

        NSInteger isEmulated = -1;
        NSInteger emulatedClass = -999;
        if (canReadEmulation) {
            BOOL (*sendBool)(id, SEL) = (void *)objc_msgSend;
            isEmulated = sendBool((id)emulationClass, isEmulatedSEL) ? 1 : 0;
        }
        if (canReadEmulatedClass) {
            int (*sendInt)(id, SEL) = (void *)objc_msgSend;
            emulatedClass = sendInt((id)emulationClass, emulatedClassSEL);
        }

        OSVariantInternalDiagnosticsFn internalFn =
            (OSVariantInternalDiagnosticsFn)dlsym(RTLD_DEFAULT, "os_variant_has_internal_diagnostics");
        NSInteger internalDiagnostics = -1;
        if (internalFn) {
            internalDiagnostics = internalFn("com.apple.frontboardservices") ? 1 : 0;
        }

        // Probe Apple's native relaunch route WITHOUT sending anything.
        Class fbsSystemServiceClass = NSClassFromString(@"FBSSystemService");
        SEL sharedServiceSEL = NSSelectorFromString(@"sharedService");
        BOOL hasSharedService = fbsSystemServiceClass && [fbsSystemServiceClass respondsToSelector:sharedServiceSEL];
        id fbsSystemService = nil;
        if (hasSharedService) {
            id (*sendID)(id, SEL) = (void *)objc_msgSend;
            @try {
                fbsSystemService = sendID((id)fbsSystemServiceClass, sharedServiceSEL);
            } @catch (__unused NSException *exception) {
                fbsSystemService = nil;
            }
        }
        BOOL hasSendActions = fbsSystemService && [fbsSystemService respondsToSelector:NSSelectorFromString(@"sendActions:withResult:")];

        Class relaunchActionClass = NSClassFromString(@"SBSRelaunchAction");
        BOOL hasRelaunchFactory = relaunchActionClass && [relaunchActionClass respondsToSelector:NSSelectorFromString(@"actionWithReason:options:targetURL:")];

        NSString *effectiveClassText = effectiveClassFn
            ? [NSString stringWithFormat:@"%ld%@", (long)effectiveClass,
               effectiveClass == 2 ? @" (iPad-class)" : @" (not iPad-class)"]
            : @"symbol unavailable";
        NSString *flexibleText = flexibleUIFn
            ? (flexibleUI ? @"YES" : @"NO")
            : @"symbol unavailable";
        NSString *emulatedText = isEmulated < 0 ? @"unavailable" : (isEmulated ? @"YES" : @"NO");
        NSString *emulatedClassText = canReadEmulatedClass
            ? [NSString stringWithFormat:@"%ld", (long)emulatedClass]
            : @"unavailable";
        NSString *internalText = internalDiagnostics < 0
            ? @"symbol unavailable"
            : (internalDiagnostics ? @"YES" : @"NO");

        NSString *text = [NSString stringWithFormat:
            @"PROCESS-SIDE PROBE (not SpringBoard itself)\n"
             "SpringBoardFoundation dlopen: %@\n"
             "SBFEffectiveDeviceClass: %@\n"
             "SBFIsFlexibleWindowingUIAvailable: %@\n"
             "FrontBoardServices dlopen: %@\n"
             "FBSDeviceEmulationConfiguration class: %@\n"
             "FBS isEmulatedDevice: %@\n"
             "FBS emulatedDeviceClass: %@\n"
             "os_variant_has_internal_diagnostics: %@\n\n"
             "NATIVE SPRINGBOARD RELAUNCH ROUTE (probe only)\n"
             "SpringBoardServices dlopen: %@\n"
             "FBSSystemService class: %@\n"
             "+sharedService: %@\n"
             "-sendActions:withResult:: %@\n"
             "SBSRelaunchAction class: %@\n"
             "+actionWithReason:options:targetURL:: %@\n\n"
             "Known SpringBoard hard gate from the restore image:\n"
             "SBPlatformController keeps Medusa capabilities only when SBFEffectiveDeviceClass() == 2.\n"
             "SBWindowScene then returns supportsMultitasking=NO when Medusa capability is zero, forcing the single-app context.",
            sbf ? @"yes" : @"NO",
            effectiveClassText,
            flexibleText,
            fbs ? @"yes" : @"NO",
            emulationClass ? @"yes" : @"NO",
            emulatedText,
            emulatedClassText,
            internalText,
            sbs ? @"yes" : @"NO",
            fbsSystemServiceClass ? @"yes" : @"NO",
            hasSharedService ? @"yes" : @"NO",
            hasSendActions ? @"yes" : @"NO",
            relaunchActionClass ? @"yes" : @"NO",
            hasRelaunchFactory ? @"yes" : @"NO"
        ];

        return strdup(text.UTF8String ?: "gate diagnostics unavailable");
    }
}

void niga_sbs_free_string(char *value)
{
    if (value) free(value);
}
