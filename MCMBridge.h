#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern int64_t sandbox_extension_consume(const char *token);
extern int sandbox_extension_release(int64_t token);

@interface MCMBridge : NSObject

/// Resolve and activate a container by class and bundle/group identifier.
/// Classes:
/// 2 = App Data (/private/var/mobile/Containers/Data/Application/<UUID>)
/// 7 = App Group (/private/var/mobile/Containers/Shared/AppGroup/<UUID>)
/// 13 = System Group (/private/var/containers/Shared/SystemGroup/<ID>)
+ (nullable NSString *)resolveAndActivateContainerClass:(uint64_t)containerClass
                                             identifier:(NSString *)identifier
                                                isGroup:(BOOL)isGroup
                                                  error:(NSString * _Nullable * _Nullable)error;

/// Enumerate all installed applications via LaunchServices and resolve their data container paths.
+ (NSArray<NSDictionary *> *)listAllApplicationsWithError:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
