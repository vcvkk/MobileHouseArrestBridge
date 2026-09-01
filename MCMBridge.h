#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCMBridge : NSObject

+ (nullable NSString *)resolveAndActivateContainerClass:(uint64_t)containerClass
                                             identifier:(NSString *)identifier
                                                isGroup:(BOOL)isGroup
                                                  error:(NSString * _Nullable * _Nullable)error;

+ (NSArray<NSDictionary *> *)listAllApplicationsWithError:(NSString * _Nullable * _Nullable)error;

+ (NSArray<NSDictionary *> *)listAllContainersForClass:(uint64_t)containerClass
                                                 error:(NSString * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
