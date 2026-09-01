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

#define MHA_BUFFER_SIZE (512 * 1024)

@interface MHAServer () {
    int _serverSocket;
}
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
        @"server_version": @"1.3.0"
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
        uint8_t *buffer = malloc(MHA_BUFFER_SIZE);
        if (!buffer) {
            close(clientFd);
            return;
        }

        ssize_t bytesRead = read(clientFd, buffer, MHA_BUFFER_SIZE - 1);
        if (bytesRead <= 0) {
            free(buffer);
            close(clientFd);
            return;
        }
        buffer[bytesRead] = '\0';

        NSString *requestStr = [[NSString alloc] initWithBytes:buffer length:bytesRead encoding:NSUTF8StringEncoding];
        free(buffer);

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
            // CONTAINERS <class_id>
            uint64_t cClass = parts.count > 1 ? [parts[1] longLongValue] : 7;
            NSString *err = nil;
            NSArray *containers = [MCMBridge listAllContainersForClass:cClass error:&err];
            response[@"status"] = @"success";
            response[@"data"] = @{@"class": @(cClass), @"count": @(containers.count), @"containers": containers ?: @[]};
            [self log:[NSString stringWithFormat:@"Enumerated %lu containers for class %llu", (unsigned long)containers.count, cClass] isError:NO];
        } else if ([command isEqualToString:@"SHORTCUTS"]) {
            // Interrogate VoiceShortcutClient, WorkflowKit, and Intents
            dlopen("/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient", RTLD_NOW);
            dlopen("/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit", RTLD_NOW);
            dlopen("/System/Library/Frameworks/Intents.framework/Intents", RTLD_NOW);

            NSMutableArray *shortcutList = [NSMutableArray array];
            NSString *dbPath = @"";

            // 1. Check WFDatabase defaultDatabase
            Class wfDbClass = NSClassFromString(@"WFDatabase");
            if (wfDbClass) {
                if ([wfDbClass respondsToSelector:sel_registerName("defaultDatabaseURL")]) {
                    NSURL *url = ((NSURL *(*)(id, SEL))objc_msgSend)(wfDbClass, sel_registerName("defaultDatabaseURL"));
                    if (url) dbPath = url.path ?: url.absoluteString;
                }
                if ([wfDbClass respondsToSelector:sel_registerName("defaultDatabase")]) {
                    id db = ((id (*)(id, SEL))objc_msgSend)(wfDbClass, sel_registerName("defaultDatabase"));
                    if (db && [db respondsToSelector:sel_registerName("visibleWorkflows")]) {
                        NSArray *workflows = ((NSArray *(*)(id, SEL))objc_msgSend)(db, sel_registerName("visibleWorkflows"));
                        for (id wf in workflows) {
                            NSString *name = [wf respondsToSelector:sel_registerName("name")] ? ((NSString *(*)(id, SEL))objc_msgSend)(wf, sel_registerName("name")) : @"";
                            NSString *wfId = [wf respondsToSelector:sel_registerName("workflowID")] ? ((NSString *(*)(id, SEL))objc_msgSend)(wf, sel_registerName("workflowID")) : @"";
                            NSUInteger actionsCount = [wf respondsToSelector:sel_registerName("actions")] ? [((NSArray *(*)(id, SEL))objc_msgSend)(wf, sel_registerName("actions")) count] : 0;
                            [shortcutList addObject:@{
                                @"name": name ?: @"Unnamed",
                                @"id": wfId ?: @"",
                                @"actions_count": @(actionsCount)
                            }];
                        }
                    }
                }
            }

            // 2. Query VCVoiceShortcutClient
            Class vcClientClass = NSClassFromString(@"VCVoiceShortcutClient");
            if (vcClientClass) {
                id client = ((id (*)(id, SEL))objc_msgSend)(vcClientClass, sel_registerName("standardClient"));
                if (client) {
                    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                    if ([client respondsToSelector:sel_registerName("getVoiceShortcutsWithCompletion:")]) {
                        ((void (*)(id, SEL, void (^)(NSArray *, NSError *)))objc_msgSend)(client, sel_registerName("getVoiceShortcutsWithCompletion:"), ^(NSArray *shortcuts, NSError *error) {
                            if (shortcuts) {
                                for (id sc in shortcuts) {
                                    NSString *phrase = [sc respondsToSelector:sel_registerName("phrase")] ? ((NSString *(*)(id, SEL))objc_msgSend)(sc, sel_registerName("phrase")) : @"";
                                    NSString *name = [sc respondsToSelector:sel_registerName("shortcutName")] ? ((NSString *(*)(id, SEL))objc_msgSend)(sc, sel_registerName("shortcutName")) : phrase;
                                    NSString *scId = [sc respondsToSelector:sel_registerName("identifier")] ? [((NSUUID *(*)(id, SEL))objc_msgSend)(sc, sel_registerName("identifier")) UUIDString] : @"";
                                    [shortcutList addObject:@{
                                        @"name": name ?: @"Unnamed",
                                        @"id": scId ?: @"",
                                        @"phrase": phrase ?: @""
                                    }];
                                }
                            }
                            dispatch_semaphore_signal(sem);
                        });
                        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC));
                    }
                }
            }

            // 3. Query INVoiceShortcutCenter
            Class centerClass = NSClassFromString(@"INVoiceShortcutCenter");
            if (centerClass && shortcutList.count == 0) {
                id center = ((id (*)(id, SEL))objc_msgSend)(centerClass, sel_registerName("sharedCenter"));
                if (center && [center respondsToSelector:sel_registerName("getAllVoiceShortcutsWithCompletion:")]) {
                    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                    ((void (*)(id, SEL, void (^)(NSArray *, NSError *)))objc_msgSend)(center, sel_registerName("getAllVoiceShortcutsWithCompletion:"), ^(NSArray *voiceShortcuts, NSError *error) {
                        if (voiceShortcuts) {
                            for (id sc in voiceShortcuts) {
                                NSString *phrase = [sc respondsToSelector:sel_registerName("invocationPhrase")] ? ((NSString *(*)(id, SEL))objc_msgSend)(sc, sel_registerName("invocationPhrase")) : @"";
                                NSString *scId = [sc respondsToSelector:sel_registerName("identifier")] ? [((NSUUID *(*)(id, SEL))objc_msgSend)(sc, sel_registerName("identifier")) UUIDString] : @"";
                                [shortcutList addObject:@{
                                    @"name": phrase ?: @"Unnamed Shortcut",
                                    @"id": scId ?: @"",
                                    @"phrase": phrase ?: @""
                                }];
                            }
                        }
                        dispatch_semaphore_signal(sem);
                    });
                    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC));
                }
            }

            response[@"status"] = @"success";
            response[@"data"] = @{
                @"count": @(shortcutList.count),
                @"database_path": dbPath ?: @"",
                @"shortcuts": shortcutList
            };
            [self log:[NSString stringWithFormat:@"Found %lu user shortcuts (DB: %@)", (unsigned long)shortcutList.count, dbPath] isError:NO];
        } else if ([command isEqualToString:@"ACTIVATE"]) {
            // ACTIVATE <class> <is_group> <identifier>
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
            // LS <path>
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
            // READ <path>
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
