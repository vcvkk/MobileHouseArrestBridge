#import <Foundation/Foundation.h>
#import "MCMBridge.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import <arpa/inet.h>
#import <sys/utsname.h>

#define SERVER_PORT 8080
#define BUFFER_SIZE 131072

static NSDictionary *get_device_metadata(void) {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    NSOperatingSystemVersion osVer = [[NSProcessInfo processInfo] operatingSystemVersion];
    NSString *osVersionStr = [NSString stringWithFormat:@"%ld.%ld.%ld", (long)osVer.majorVersion, (long)osVer.minorVersion, (long)osVer.patchVersion];

    return @{
        @"device_model": deviceModel ?: @"Unknown",
        @"os_version": osVersionStr,
        @"process_name": [[NSProcessInfo processInfo] processName],
        @"pid": @([[NSProcessInfo processInfo] processIdentifier]),
        @"server_version": @"1.1.0"
    };
}

static void handle_client(int client_fd) {
    uint8_t *buffer = malloc(BUFFER_SIZE);
    if (!buffer) {
        close(client_fd);
        return;
    }

    ssize_t bytes_read = read(client_fd, buffer, BUFFER_SIZE - 1);
    if (bytes_read <= 0) {
        free(buffer);
        close(client_fd);
        return;
    }
    buffer[bytes_read] = '\0';

    NSString *requestStr = [[NSString alloc] initWithBytes:buffer length:bytes_read encoding:NSUTF8StringEncoding];
    free(buffer);

    if (!requestStr) {
        close(client_fd);
        return;
    }

    NSArray *lines = [requestStr componentsSeparatedByString:@"\n"];
    NSString *firstLine = lines.firstObject;
    NSArray *parts = [firstLine componentsSeparatedByString:@" "];
    NSString *cmd = parts.firstObject;

    NSMutableDictionary *response = [NSMutableDictionary dictionary];

    if ([cmd isEqualToString:@"PING"]) {
        response[@"status"] = @"success";
        response[@"data"] = get_device_metadata();
    } else if ([cmd isEqualToString:@"APPS"]) {
        NSString *err = nil;
        NSArray *apps = [MCMBridge listAllApplicationsWithError:&err];
        if (apps && apps.count > 0) {
            response[@"status"] = @"success";
            response[@"data"] = @{
                @"count": @(apps.count),
                @"apps": apps
            };
        } else {
            response[@"status"] = @"error";
            response[@"error"] = err ?: @"No applications found";
        }
    } else if ([cmd isEqualToString:@"ACTIVATE"]) {
        // Format: ACTIVATE <class> <is_group> <identifier>
        if (parts.count >= 4) {
            uint64_t containerClass = [parts[1] longLongValue];
            BOOL isGroup = [parts[2] boolValue];
            NSString *identifier = parts[3];

            NSString *error = nil;
            NSString *path = [MCMBridge resolveAndActivateContainerClass:containerClass
                                                              identifier:identifier
                                                                 isGroup:isGroup
                                                                   error:&error];
            if (path) {
                response[@"status"] = @"success";
                response[@"data"] = @{
                    @"identifier": identifier,
                    @"class": @(containerClass),
                    @"is_group": @(isGroup),
                    @"path": path
                };
            } else {
                response[@"status"] = @"error";
                response[@"error"] = error ?: @"Unknown activation error";
            }
        } else {
            response[@"status"] = @"error";
            response[@"error"] = @"Invalid arguments for ACTIVATE command";
        }
    } else if ([cmd isEqualToString:@"LS"]) {
        // Format: LS <path>
        if (firstLine.length > 3) {
            NSString *dirPath = [firstLine substringFromIndex:3];
            NSFileManager *fm = [NSFileManager defaultManager];
            NSError *err = nil;
            NSArray *contents = [fm contentsOfDirectoryAtPath:dirPath error:&err];
            if (contents) {
                NSMutableArray *items = [NSMutableArray array];
                for (NSString *name in contents) {
                    NSString *fullPath = [dirPath stringByAppendingPathComponent:name];
                    NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
                    BOOL isDir = [attrs[NSFileType] isEqualToString:NSFileTypeDirectory];
                    unsigned long long size = [attrs[NSFileSize] unsignedLongLongValue];
                    NSDate *modDate = attrs[NSFileModificationDate];

                    [items addObject:@{
                        @"name": name,
                        @"is_dir": @(isDir),
                        @"size": @(size),
                        @"modified": modDate ? [NSString stringWithFormat:@"%.0f", [modDate timeIntervalSince1970]] : @"0"
                    }];
                }
                response[@"status"] = @"success";
                response[@"data"] = @{
                    @"path": dirPath,
                    @"items": items
                };
            } else {
                response[@"status"] = @"error";
                response[@"error"] = err.localizedDescription ?: @"Failed to list directory";
            }
        }
    } else if ([cmd isEqualToString:@"READ"]) {
        // Format: READ <path>
        if (firstLine.length > 5) {
            NSString *filePath = [firstLine substringFromIndex:5];
            NSData *data = [NSData dataWithContentsOfFile:filePath];
            if (data) {
                response[@"status"] = @"success";
                response[@"data"] = @{
                    @"path": filePath,
                    @"size": @(data.length),
                    @"content_b64": [data base64EncodedStringWithOptions:0]
                };
            } else {
                response[@"status"] = @"error";
                response[@"error"] = @"Failed to read file or permission denied";
            }
        }
    } else if ([cmd isEqualToString:@"WRITE"]) {
        // Format: WRITE <path>\n<base64_data>
        if (lines.count >= 2) {
            NSString *filePath = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *base64Str = [lines[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSData *data = [[NSData alloc] initWithBase64EncodedString:base64Str options:0];
            if (data && [data writeToFile:filePath atomically:YES]) {
                response[@"status"] = @"success";
                response[@"data"] = @{
                    @"path": filePath,
                    @"bytes_written": @(data.length)
                };
            } else {
                response[@"status"] = @"error";
                response[@"error"] = @"Failed to write data to destination path";
            }
        }
    } else {
        response[@"status"] = @"error";
        response[@"error"] = @"Unsupported command";
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    if (jsonData) {
        write(client_fd, jsonData.bytes, jsonData.length);
    }
    close(client_fd);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[MobileHouseArrestBridge] Starting daemon on port %d...", SERVER_PORT);

        int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd < 0) {
            NSLog(@"[MobileHouseArrestBridge] Failed to create socket: %s", strerror(errno));
            return 1;
        }

        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in address;
        memset(&address, 0, sizeof(address));
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = INADDR_ANY;
        address.sin_port = htons(SERVER_PORT);

        if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
            NSLog(@"[MobileHouseArrestBridge] Bind failed: %s", strerror(errno));
            close(server_fd);
            return 1;
        }

        if (listen(server_fd, 10) < 0) {
            NSLog(@"[MobileHouseArrestBridge] Listen failed: %s", strerror(errno));
            close(server_fd);
            return 1;
        }

        NSLog(@"[MobileHouseArrestBridge] Daemon ready, listening on 0.0.0.0:%d", SERVER_PORT);

        while (1) {
            struct sockaddr_in client_addr;
            socklen_t addrlen = sizeof(client_addr);
            int client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &addrlen);
            if (client_fd >= 0) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    handle_client(client_fd);
                });
            }
        }
    }
    return 0;
}
