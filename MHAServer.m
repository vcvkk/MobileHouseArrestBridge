#import "MHAServer.h"
#import "MCMBridge.h"
#import <sys/utsname.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface MHAServer () {
    int _serverSocket;
}
@property (nonatomic, assign, readwrite) BOOL isRunning;
@property (nonatomic, assign, readwrite) uint16_t port;
@end

@implementation MHAServer

+ (instancetype)sharedServer {
    static MHAServer *server = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        server = [[MHAServer alloc] init];
    });
    return server;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _serverSocket = -1;
        _isRunning = NO;
        _port = 8080;
    }
    return self;
}

- (void)log:(NSString *)msg isError:(BOOL)isErr {
    NSLog(@"[MHAServer] %@", msg);
    if ([self.delegate respondsToSelector:@selector(serverDidLogMessage:isError:)]) {
        [self.delegate serverDidLogMessage:msg isError:isErr];
    }
}

- (NSDictionary *)collectSystemMetadata {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"iPhone";

    NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
    NSString *osVersion = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion];

    return @{
        @"device_model": deviceModel,
        @"os_version": osVersion,
        @"process_name": [[NSProcessInfo processInfo] processName],
        @"pid": @([[NSProcessInfo processInfo] processIdentifier]),
        @"server_version": @"1.4.0"
    };
}

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error {
    if (self.isRunning) return YES;

    _serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (_serverSocket < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:strerror(errno)]}];
        return NO;
    }

    int opt = 1;
    setsockopt(_serverSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(_serverSocket, (struct sockaddr *)&address, sizeof(address)) < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:strerror(errno)]}];
        close(_serverSocket);
        _serverSocket = -1;
        return NO;
    }

    if (listen(_serverSocket, 16) < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:strerror(errno)]}];
        close(_serverSocket);
        _serverSocket = -1;
        return NO;
    }

    self.port = port;
    self.isRunning = YES;

    [self log:[NSString stringWithFormat:@"Server daemon listening on 0.0.0.0:%d", port] isError:NO];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self acceptLoop];
    });

    return YES;
}

- (void)stop {
    if (!self.isRunning) return;
    self.isRunning = NO;
    if (_serverSocket >= 0) {
        close(_serverSocket);
        _serverSocket = -1;
    }
    [self log:@"Server daemon stopped" isError:NO];
}

- (void)acceptLoop {
    while (self.isRunning && _serverSocket >= 0) {
        struct sockaddr_in clientAddr;
        socklen_t clientLen = sizeof(clientAddr);
        int clientFd = accept(_serverSocket, (struct sockaddr *)&clientAddr, &clientLen);
        if (clientFd < 0) {
            if (!self.isRunning) break;
            continue;
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self handleClient:clientFd];
        });
    }
}

- (void)handleClient:(int)clientFd {
    @autoreleasepool {
        // Set receive timeout so read loop finishes when client stops sending
        struct timeval tv;
        tv.tv_sec = 2;
        tv.tv_usec = 0;
        setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof(tv));

        NSMutableData *incomingData = [NSMutableData data];
        uint8_t chunk[32768];
        
        while (YES) {
            ssize_t n = read(clientFd, chunk, sizeof(chunk));
            if (n > 0) {
                [incomingData appendBytes:chunk length:n];
                // Check if simple single-line command ended
                if (incomingData.length < 512 && strchr((char *)incomingData.bytes, '\n') && !strstr((char *)incomingData.bytes, "WRITE")) {
                    break;
                }
            } else {
                break;
            }
        }

        if (incomingData.length == 0) {
            close(clientFd);
            return;
        }

        NSString *requestStr = [[NSString alloc] initWithData:incomingData encoding:NSUTF8StringEncoding];
        if (!requestStr || requestStr.length == 0) {
            close(clientFd);
            return;
        }

        NSArray<NSString *> *lines = [requestStr componentsSeparatedByString:@"\n"];
        NSString *firstLine = lines.firstObject ?: @"";
        NSArray<NSString *> *parts = [firstLine componentsSeparatedByString:@" "];
        NSString *command = parts.firstObject ?: @"";

        [self log:[NSString stringWithFormat:@"RPC -> %@", firstLine] isError:NO];

        NSMutableDictionary *response = [NSMutableDictionary dictionary];

        if ([command isEqualToString:@"PING"]) {
            response[@"status"] = @"success";
            response[@"data"] = [self collectSystemMetadata];
        } else if ([command isEqualToString:@"APPS"]) {
            NSString *err = nil;
            NSArray *apps = [MCMBridge listAllApplicationsWithError:&err];
            if (apps && apps.count > 0) {
                response[@"status"] = @"success";
                response[@"data"] = @{@"count": @(apps.count), @"apps": apps};
                [self log:[NSString stringWithFormat:@"Enumerated %lu installed apps", (unsigned long)apps.count] isError:NO];
            } else {
                response[@"status"] = @"error";
                response[@"error"] = err ?: @"No applications resolved";
                [self log:[NSString stringWithFormat:@"App enumeration failed: %@", err] isError:YES];
            }
        } else if ([command isEqualToString:@"CONTAINERS"]) {
            uint64_t cClass = parts.count > 1 ? [parts[1] longLongValue] : 7;
            NSString *err = nil;
            NSArray *containers = [MCMBridge listAllContainersForClass:cClass error:&err];
            response[@"status"] = @"success";
            response[@"data"] = @{@"class": @(cClass), @"count": @(containers.count), @"containers": containers ?: @[]};
            [self log:[NSString stringWithFormat:@"Enumerated %lu containers for class %llu", (unsigned long)containers.count, cClass] isError:NO];
        } else if ([command isEqualToString:@"ACTIVATE"]) {
            if (parts.count >= 4) {
                uint64_t containerClass = [parts[1] longLongValue];
                BOOL isGroup = [parts[2] boolValue];
                NSString *identifier = parts[3];

                NSString *err = nil;
                NSString *resolvedPath = [MCMBridge resolveAndActivateContainerClass:containerClass identifier:identifier isGroup:isGroup error:&err];

                if (resolvedPath) {
                    response[@"status"] = @"success";
                    response[@"data"] = @{
                        @"identifier": identifier,
                        @"class": @(containerClass),
                        @"is_group": @(isGroup),
                        @"path": resolvedPath
                    };
                    [self log:[NSString stringWithFormat:@"Activated %@ -> %@", identifier, resolvedPath] isError:NO];
                } else {
                    response[@"status"] = @"error";
                    response[@"error"] = err ?: @"Activation failed";
                    [self log:[NSString stringWithFormat:@"Failed to activate %@: %@", identifier, err] isError:YES];
                }
            } else {
                response[@"status"] = @"error";
                response[@"error"] = @"Invalid arguments for ACTIVATE";
            }
        } else if ([command isEqualToString:@"LS"]) {
            if (firstLine.length > 3) {
                NSString *path = [firstLine substringFromIndex:3];
                NSFileManager *fm = [NSFileManager defaultManager];
                NSError *err = nil;
                NSArray *items = [fm contentsOfDirectoryAtPath:path error:&err];
                if (items) {
                    NSMutableArray *list = [NSMutableArray array];
                    for (NSString *name in items) {
                        NSString *fullPath = [path stringByAppendingPathComponent:name];
                        NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                        BOOL isDir = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
                        unsigned long long sz = [attrs[NSFileSize] unsignedLongLongValue];
                        NSDate *mod = attrs[NSFileModificationDate];

                        [list addObject:@{
                            @"name": name,
                            @"is_dir": @(isDir),
                            @"size": @(sz),
                            @"modified": mod ? [NSString stringWithFormat:@"%.0f", [mod timeIntervalSince1970]] : @"0"
                        }];
                    }
                    response[@"status"] = @"success";
                    response[@"data"] = @{@"path": path, @"items": list};
                } else {
                    response[@"status"] = @"error";
                    response[@"error"] = err.localizedDescription ?: @"Permission denied or path does not exist";
                }
            }
        } else if ([command isEqualToString:@"READ"]) {
            if (firstLine.length > 5) {
                NSString *filePath = [firstLine substringFromIndex:5];
                NSData *fileData = [NSData dataWithContentsOfFile:filePath];
                if (fileData) {
                    response[@"status"] = @"success";
                    response[@"data"] = @{
                        @"path": filePath,
                        @"size": @(fileData.length),
                        @"content_b64": [fileData base64EncodedStringWithOptions:0]
                    };
                    [self log:[NSString stringWithFormat:@"Read %lu bytes from %@", (unsigned long)fileData.length, filePath.lastPathComponent] isError:NO];
                } else {
                    response[@"status"] = @"error";
                    response[@"error"] = @"Cannot read file";
                }
            }
        } else if ([command isEqualToString:@"WRITE"]) {
            // WRITE <path>\n<base64>
            if (lines.count >= 2) {
                NSString *filePath = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSString *b64 = [lines[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                NSData *fileData = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
                if (fileData && [fileData writeToFile:filePath atomically:YES]) {
                    response[@"status"] = @"success";
                    response[@"data"] = @{@"path": filePath, @"bytes_written": @(fileData.length)};
                    [self log:[NSString stringWithFormat:@"Wrote %lu bytes to %@", (unsigned long)fileData.length, filePath.lastPathComponent] isError:NO];
                } else {
                    response[@"status"] = @"error";
                    response[@"error"] = @"Failed to write data to destination";
                }
            }
        } else {
            response[@"status"] = @"error";
            response[@"error"] = [NSString stringWithFormat:@"Unknown command '%@'", command];
        }

        NSData *payload = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
        if (payload) {
            write(clientFd, payload.bytes, payload.length);
        }
        close(clientFd);
    }
}

@end
