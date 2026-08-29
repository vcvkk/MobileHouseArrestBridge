#import <Foundation/Foundation.h>
#import "MCMBridge.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import <arpa/inet.h>

#define SERVER_PORT 8080
#define BUFFER_SIZE 65536

static void handle_client(int client_fd) {
    uint8_t buffer[BUFFER_SIZE];
    ssize_t bytes_read = read(client_fd, buffer, sizeof(buffer) - 1);
    if (bytes_read <= 0) {
        close(client_fd);
        return;
    }
    buffer[bytes_read] = '\0';

    NSString *requestStr = [[NSString alloc] initWithBytes:buffer length:bytes_read encoding:NSUTF8StringEncoding];
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
        response[@"status"] = @"ok";
        response[@"message"] = @"PONG from iOS MobileHouseArrest Bridge";
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
                response[@"status"] = @"ok";
                response[@"path"] = path;
            } else {
                response[@"status"] = @"error";
                response[@"error"] = error ?: @"Unknown error";
            }
        } else {
            response[@"status"] = @"error";
            response[@"error"] = @"Invalid arguments for ACTIVATE";
        }
    } else if ([cmd isEqualToString:@"LS"]) {
        // Format: LS <path>
        if (parts.count >= 2) {
            NSString *dirPath = [firstLine substringFromIndex:3];
            NSFileManager *fm = [NSFileManager defaultManager];
            NSError *err = nil;
            NSArray *items = [fm contentsOfDirectoryAtPath:dirPath error:&err];
            if (items) {
                response[@"status"] = @"ok";
                response[@"items"] = items;
            } else {
                response[@"status"] = @"error";
                response[@"error"] = err.localizedDescription;
            }
        }
    } else if ([cmd isEqualToString:@"READ"]) {
        // Format: READ <path>
        if (parts.count >= 2) {
            NSString *filePath = [firstLine substringFromIndex:5];
            NSData *data = [NSData dataWithContentsOfFile:filePath];
            if (data) {
                response[@"status"] = @"ok";
                response[@"data"] = [data base64EncodedStringWithOptions:0];
            } else {
                response[@"status"] = @"error";
                response[@"error"] = @"Failed to read file";
            }
        }
    } else if ([cmd isEqualToString:@"WRITE"]) {
        // Format: WRITE <path>\n<base64_data>
        if (lines.count >= 2) {
            NSString *filePath = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *base64Str = [lines[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSData *data = [[NSData alloc] initWithBase64EncodedString:base64Str options:0];
            if (data && [data writeToFile:filePath atomically:YES]) {
                response[@"status"] = @"ok";
                response[@"message"] = @"File written successfully";
            } else {
                response[@"status"] = @"error";
                response[@"error"] = @"Failed to write file";
            }
        }
    } else {
        response[@"status"] = @"error";
        response[@"error"] = @"Unknown command";
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    if (jsonData) {
        write(client_fd, jsonData.bytes, jsonData.length);
    }
    close(client_fd);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"[MobileHouseArrestBridge] Starting server on port %d...", SERVER_PORT);

        int server_fd = socket(AF_INET, SOCK_STREAM, 0);
        if (server_fd < 0) {
            NSLog(@"[MobileHouseArrestBridge] socket creation failed");
            return 1;
        }

        int opt = 1;
        setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

        struct sockaddr_in address;
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = INADDR_ANY;
        address.sin_port = htons(SERVER_PORT);

        if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
            NSLog(@"[MobileHouseArrestBridge] Bind failed on port %d", SERVER_PORT);
            close(server_fd);
            return 1;
        }

        if (listen(server_fd, 5) < 0) {
            NSLog(@"[MobileHouseArrestBridge] Listen failed");
            close(server_fd);
            return 1;
        }

        NSLog(@"[MobileHouseArrestBridge] Server listening on 0.0.0.0:%d", SERVER_PORT);

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
