#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MHAServerDelegate <NSObject>
- (void)serverDidLogMessage:(NSString *)message isError:(BOOL)isError;
- (void)serverClientCountDidChange:(NSUInteger)count;
@end

@interface MHAServer : NSObject

@property (nonatomic, weak) id<MHAServerDelegate> delegate;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) BOOL isRunning;

+ (instancetype)sharedServer;
- (BOOL)startOnPort:(uint16_t)port error:(NSError * _Nullable * _Nullable)error;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
