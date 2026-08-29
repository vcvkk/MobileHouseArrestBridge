#import "MCMBridge.h"
#import <dlfcn.h>
#import <stdlib.h>
#import <xpc/xpc.h>
#import <objc/runtime.h>
#import <objc/message.h>

typedef void *(*MCMQueryCreate)(void);
typedef void (*MCMQuerySetU64)(void *, uint64_t);
typedef void (*MCMQuerySetXPC)(void *, xpc_object_t);
typedef void (*MCMQuerySetCString)(void *, const char *);
typedef void *(*MCMQueryGetPointer)(void *);
typedef void (*MCMQueryFree)(void *);
typedef const char *(*MCMObjectGetPath)(void *);
typedef char *(*MCMObjectCopyToken)(void *);
typedef void (*MCMObjectFree)(void *);
typedef int (*MCMErrorGetInt)(void *);
typedef const char *(*MCMErrorGetString)(void *);

typedef struct {
    void *handle;
    MCMQueryCreate queryCreate;
    MCMQuerySetU64 querySetClass;
    MCMQuerySetXPC querySetIdentifiers;
    MCMQuerySetXPC querySetGroupIdentifiers;
    MCMQuerySetU64 querySetFlags;
    MCMQuerySetU64 querySetPart;
    MCMQueryGetPointer queryGetSingle;
    MCMQueryGetPointer queryGetLastError;
    MCMQueryFree queryFree;
    MCMObjectGetPath objectGetPath;
    MCMObjectCopyToken objectCopyToken;
    MCMObjectFree objectFree;
    MCMErrorGetInt errorGetPOSIX;
    MCMErrorGetString errorGetMessage;
} MCMAPI;

static MCMAPI *MCMGetAPI(void) {
    static MCMAPI api;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        api.handle = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
        void *h = api.handle ? api.handle : RTLD_DEFAULT;
        api.queryCreate = (MCMQueryCreate)dlsym(h, "container_query_create");
        api.querySetClass = (MCMQuerySetU64)dlsym(h, "container_query_set_class");
        api.querySetIdentifiers = (MCMQuerySetXPC)dlsym(h, "container_query_set_identifiers");
        api.querySetGroupIdentifiers = (MCMQuerySetXPC)dlsym(h, "container_query_set_group_identifiers");
        api.querySetFlags = (MCMQuerySetU64)dlsym(h, "container_query_operation_set_flags");
        api.querySetPart = (MCMQuerySetU64)dlsym(h, "container_query_operation_set_part");
        api.queryGetSingle = (MCMQueryGetPointer)dlsym(h, "container_query_get_single_result");
        api.queryGetLastError = (MCMQueryGetPointer)dlsym(h, "container_query_get_last_error");
        api.queryFree = (MCMQueryFree)dlsym(h, "container_query_free");
        api.objectGetPath = (MCMObjectGetPath)dlsym(h, "container_object_get_path");
        api.objectCopyToken = (MCMObjectCopyToken)dlsym(h, "container_object_copy_sandbox_token");
        api.objectFree = (MCMObjectFree)dlsym(h, "container_free_object");
        api.errorGetPOSIX = (MCMErrorGetInt)dlsym(h, "container_error_get_posix_errno");
        api.errorGetMessage = (MCMErrorGetString)dlsym(h, "container_error_get_path");
    });
    return &api;
}

@implementation MCMBridge

+ (nullable NSString *)resolveAndActivateContainerClass:(uint64_t)containerClass
                                             identifier:(NSString *)identifier
                                                isGroup:(BOOL)isGroup
                                                  error:(NSString * _Nullable * _Nullable)error {
    MCMAPI *api = MCMGetAPI();
    if (!api->queryCreate) {
        if (error) *error = @"Failed to load libsystem_containermanager.dylib";
        return nil;
    }

    void *query = api->queryCreate();
    if (!query) {
        if (error) *error = @"container_query_create returned NULL";
        return nil;
    }

    api->querySetClass(query, containerClass);

    xpc_object_t ids = xpc_array_create(NULL, 0);
    xpc_array_set_string(ids, XPC_ARRAY_APPEND, identifier.UTF8String);
    if (isGroup && api->querySetGroupIdentifiers) {
        api->querySetGroupIdentifiers(query, ids);
    } else {
        api->querySetIdentifiers(query, ids);
    }

    if (api->querySetFlags) {
        api->querySetFlags(query, 0x900000000ULL);
    }

    void *obj = api->queryGetSingle(query);
    if (!obj) {
        void *errObj = api->queryGetLastError ? api->queryGetLastError(query) : NULL;
        int errCode = (errObj && api->errorGetPOSIX) ? api->errorGetPOSIX(errObj) : -1;
        if (error) *error = [NSString stringWithFormat:@"Container not found for %@ (posix errno %d)", identifier, errCode];
        api->queryFree(query);
        return nil;
    }

    const char *rawPath = api->objectGetPath ? api->objectGetPath(obj) : NULL;
    NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : nil;

    if (api->objectCopyToken) {
        char *token = api->objectCopyToken(obj);
        if (token) {
            int64_t handle = sandbox_extension_consume(token);
            NSLog(@"[MCMBridge] Consumed sandbox extension for %@, handle=%lld", identifier, handle);
            free(token);
        }
    }

    api->objectFree(obj);
    api->queryFree(query);

    return path;
}

+ (NSArray<NSDictionary *> *)listAllApplicationsWithError:(NSString * _Nullable * _Nullable)error {
    NSMutableArray<NSDictionary *> *results = [NSMutableArray array];

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        // Fallback: try loading MobileCoreServices framework
        dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_NOW);
        dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
        workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    }

    if (!workspaceClass) {
        if (error) *error = @"LSApplicationWorkspace class not available on this iOS build";
        return @[];
    }

    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, sel_registerName("defaultWorkspace"));
    if (!workspace) {
        if (error) *error = @"Failed to obtain default LSApplicationWorkspace instance";
        return @[];
    }

    NSArray *apps = ((id (*)(id, SEL))objc_msgSend)(workspace, sel_registerName("allApplications"));
    if (!apps || ![apps isKindOfClass:[NSArray class]]) {
        if (error) *error = @"allApplications query returned empty or invalid result";
        return @[];
    }

    for (id proxy in apps) {
        NSString *bundleId = nil;
        if ([proxy respondsToSelector:sel_registerName("applicationIdentifier")]) {
            bundleId = ((id (*)(id, SEL))objc_msgSend)(proxy, sel_registerName("applicationIdentifier"));
        } else if ([proxy respondsToSelector:sel_registerName("bundleIdentifier")]) {
            bundleId = ((id (*)(id, SEL))objc_msgSend)(proxy, sel_registerName("bundleIdentifier"));
        }

        if (!bundleId || bundleId.length == 0) continue;

        NSString *name = nil;
        if ([proxy respondsToSelector:sel_registerName("localizedName")]) {
            name = ((id (*)(id, SEL))objc_msgSend)(proxy, sel_registerName("localizedName"));
        }
        if (!name || name.length == 0) {
            name = bundleId;
        }

        NSString *version = @"";
        if ([proxy respondsToSelector:sel_registerName("shortVersionString")]) {
            version = ((id (*)(id, SEL))objc_msgSend)(proxy, sel_registerName("shortVersionString")) ?: @"";
        }

        NSString *appType = @"User";
        if ([proxy respondsToSelector:sel_registerName("bundleType")]) {
            NSString *bt = ((id (*)(id, SEL))objc_msgSend)(proxy, sel_registerName("bundleType"));
            if ([bt isEqualToString:@"System"] || [bt isEqualToString:@"Hidden"]) {
                appType = bt;
            }
        }

        // Try to obtain the data container path using MCM
        NSString *containerPath = [self resolveAndActivateContainerClass:2 identifier:bundleId isGroup:NO error:nil] ?: @"";

        [results addObject:@{
            @"name": name,
            @"bundle_id": bundleId,
            @"version": version,
            @"type": appType,
            @"container_path": containerPath
        }];
    }

    [results sortUsingComparator:^NSComparisonResult(NSDictionary *obj1, NSDictionary *obj2) {
        return [obj1[@"name"] localizedCaseInsensitiveCompare:obj2[@"name"]];
    }];

    return results;
}

@end
