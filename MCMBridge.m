#import "MCMBridge.h"
#import <dlfcn.h>
#import <stdlib.h>
#import <xpc/xpc.h>

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
        api->querySetFlags(query, 0x900000000ULL); // Standard lookup flags
    }

    void *obj = api->queryGetSingle(query);
    if (!obj) {
        void *errObj = api->queryGetLastError ? api->queryGetLastError(query) : NULL;
        int errCode = (errObj && api->errorGetPOSIX) ? api->errorGetPOSIX(errObj) : -1;
        if (error) *error = [NSString stringWithFormat:@"Failed to find container for %@ (posix error %d)", identifier, errCode];
        api->queryFree(query);
        return nil;
    }

    const char *rawPath = api->objectGetPath ? api->objectGetPath(obj) : NULL;
    NSString *path = rawPath ? [NSString stringWithUTF8String:rawPath] : nil;

    // Grab sandbox extension token and consume it
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

@end
