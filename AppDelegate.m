#import "AppDelegate.h"
#import "MCMBridge.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import <arpa/inet.h>
#import <sys/utsname.h>

#define SERVER_PORT 8080
#define BUFFER_SIZE 131072

static UITextView *gLogTextView = nil;

@implementation AppDelegate

+ (void)appendLog:(NSString *)message {
    NSLog(@"[MHA] %@", message);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gLogTextView) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"HH:mm:ss"];
            NSString *timeStr = [formatter stringFromDate:[NSDate date]];
            NSString *newLog = [NSString stringWithFormat:@"[%@] %@\n%@", timeStr, message, gLogTextView.text];
            gLogTextView.text = newLog;
        }
    });
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.backgroundColor = [UIColor blackColor];

    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];

    // Card View
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, 60, self.window.bounds.size.width - 40, 160)];
    card.backgroundColor = [UIColor colorWithRed:0.14 green:0.14 blue:0.18 alpha:1.0];
    card.layer.cornerRadius = 16;
    card.layer.masksToBounds = YES;
    [rootVC.view addSubview:card];

    // Title
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, card.bounds.size.width - 32, 28)];
    titleLabel.text = @"MobileHouseArrest Bridge";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [card addSubview:titleLabel];

    // Status Badge
    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 52, card.bounds.size.width - 32, 24)];
    statusLabel.text = @"🟢 Daemon Running on port 8080";
    statusLabel.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
    statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [card addSubview:statusLabel];

    // Subtitle
    UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 84, card.bounds.size.width - 32, 60)];
    subLabel.text = @"Connect via PC:\n1. iproxy 8080 8080\n2. python3 client.py apps list";
    subLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    subLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    subLabel.numberOfLines = 3;
    [card addSubview:subLabel];

    // Logs Header
    UILabel *logsHeader = [[UILabel alloc] initWithFrame:CGRectMake(24, 235, self.window.bounds.size.width - 48, 20)];
    logsHeader.text = @"ACTIVITY LOG";
    logsHeader.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    logsHeader.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [rootVC.view addSubview:logsHeader];

    // Log Console TextView
    CGFloat logY = 260;
    CGFloat logHeight = self.window.bounds.size.height - logY - 40;
    gLogTextView = [[UITextView alloc] initWithFrame:CGRectMake(20, logY, self.window.bounds.size.width - 40, logHeight)];
    gLogTextView.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:1.0];
    gLogTextView.textColor = [UIColor colorWithRed:0.2 green:0.85 blue:0.6 alpha:1.0];
    gLogTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    gLogTextView.editable = NO;
    gLogTextView.layer.cornerRadius = 12;
    gLogTextView.layer.borderWidth = 1;
    gLogTextView.layer.borderColor = [UIColor colorWithWhite:0.15 alpha:1.0].CGColor;
    gLogTextView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [rootVC.view addSubview:gLogTextView];

    self.window.rootViewController = rootVC;
    [self.window makeKeyAndVisible];

    [AppDelegate appendLog:@"Daemon initialized."];
    [AppDelegate appendLog:@"Waiting for incoming USB/TCP connections..."];

    // Start server in background thread so main UI thread is NEVER blocked
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self startTCPServer];
    });

    return YES;
}

- (NSDictionary *)deviceMetadata {
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

- (void)handleClient:(int)client_fd {
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

    [AppDelegate appendLog:[NSString stringWithFormat:@"REQ: %@", firstLine]];

    NSMutableDictionary *response = [NSMutableDictionary dictionary];

    if ([cmd isEqualToString:@"PING"]) {
        response[@"status"] = @"success";
        response[@"data"] = [self deviceMetadata];
    } else if ([cmd isEqualToString:@"APPS"]) {
        NSString *err = nil;
        NSArray *apps = [MCMBridge listAllApplicationsWithError:&err];
        if (apps && apps.count > 0) {
            response[@"status"] = @"success";
            response[@"data"] = @{
                @"count": @(apps.count),
                @"apps": apps
            };
            [AppDelegate appendLog:[NSString stringWithFormat:@"Scanned %lu applications", (unsigned long)apps.count]];
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
                [AppDelegate appendLog:[NSString stringWithFormat:@"Activated %@ -> %@", identifier, path]];
            } else {
                response[@"status"] = @"error";
                response[@"error"] = error ?: @"Unknown activation error";
                [AppDelegate appendLog:[NSString stringWithFormat:@"Activation failed for %@", identifier]];
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
                [AppDelegate appendLog:[NSString stringWithFormat:@"Read %lu bytes from %@", (unsigned long)data.length, filePath.lastPathComponent]];
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
                [AppDelegate appendLog:[NSString stringWithFormat:@"Wrote %lu bytes to %@", (unsigned long)data.length, filePath.lastPathComponent]];
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

- (void)startTCPServer {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        [AppDelegate appendLog:@"Failed to create socket"];
        return;
    }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(SERVER_PORT);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        [AppDelegate appendLog:[NSString stringWithFormat:@"Bind failed: %s", strerror(errno)]];
        close(server_fd);
        return;
    }

    if (listen(server_fd, 10) < 0) {
        [AppDelegate appendLog:[NSString stringWithFormat:@"Listen failed: %s", strerror(errno)]];
        close(server_fd);
        return;
    }

    [AppDelegate appendLog:[NSString stringWithFormat:@"Server listening on 0.0.0.0:%d", SERVER_PORT]];

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t addrlen = sizeof(client_addr);
        int client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &addrlen);
        if (client_fd >= 0) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self handleClient:client_fd];
            });
        }
    }
}

@end
