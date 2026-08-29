#import "GlassStatusViewController.h"
#import <sys/utsname.h>

@interface GlassStatusViewController ()

@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *consoleContainer;
@property (nonatomic, strong) UITextView *consoleTextView;
@property (nonatomic, strong) NSMutableArray<NSString *> *logHistory;

@property (nonatomic, strong) NSString *deviceModel;
@property (nonatomic, strong) NSString *osVersion;
@property (nonatomic, assign) NSUInteger activeClientsCount;

@end

@implementation GlassStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HouseArrest";
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.09 alpha:1.0];
    self.logHistory = [NSMutableArray array];
    
    [self loadSystemInfo];
    [self setupNavigationBar];
    [self setupSegmentedControl];
    [self setupTableView];
    [self setupConsoleView];
    
    [MHAServer sharedServer].delegate = self;
    
    NSError *error = nil;
    if (![[MHAServer sharedServer] startOnPort:8080 error:&error]) {
        [self serverDidLogMessage:[NSString stringWithFormat:@"Failed to bind port 8080: %@", error.localizedDescription] isError:YES];
    } else {
        [self serverDidLogMessage:@"MobileHouseArrest daemon listening on 0.0.0.0:8080" isError:NO];
        [self serverDidLogMessage:@"Bridge ready for incoming USB mux / TCP clients." isError:NO];
    }
}

- (void)loadSystemInfo {
    struct utsname systemInfo;
    uname(&systemInfo);
    self.deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"iPhone";
    
    NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
    self.osVersion = [NSString stringWithFormat:@"iOS %ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion];
    self.activeClientsCount = 0;
}

- (void)setupNavigationBar {
    if (self.navigationController) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
        self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
        self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.20 green:0.78 blue:0.55 alpha:1.0];
        
        UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareLogs)];
        self.navigationItem.rightBarButtonItem = shareItem;
    }
}

- (void)setupSegmentedControl {
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Dashboard", @"Console Logs"]];
    self.segmentedControl.selectedSegmentIndex = 0;
    self.segmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    self.segmentedControl.backgroundColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.18 alpha:1.0];
    self.segmentedControl.selectedSegmentTintColor = [UIColor colorWithRed:0.20 green:0.24 blue:0.32 alpha:1.0];
    
    NSDictionary *attr = @{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]};
    [self.segmentedControl setTitleTextAttributes:attr forState:UIControlStateNormal];
    [self.segmentedControl setTitleTextAttributes:attr forState:UIControlStateSelected];
    
    [self.segmentedControl addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.segmentedControl];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.segmentedControl.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8],
        [self.segmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.segmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.segmentedControl.heightAnchor constraintEqualToConstant:32]
    ]];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    [self.view addSubview:self.tableView];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.segmentedControl.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];
}

- (void)setupConsoleView {
    self.consoleContainer = [[UIView alloc] init];
    self.consoleContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleContainer.hidden = YES;
    self.consoleContainer.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.07 alpha:1.0];
    self.consoleContainer.layer.cornerRadius = 16;
    self.consoleContainer.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    self.consoleContainer.layer.borderWidth = 1.0;
    self.consoleContainer.layer.masksToBounds = YES;
    [self.view addSubview:self.consoleContainer];
    
    // Top Bar inside console with Clear Button
    UIView *topBar = [[UIView alloc] init];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    topBar.backgroundColor = [UIColor colorWithRed:0.09 green:0.11 blue:0.14 alpha:1.0];
    [self.consoleContainer addSubview:topBar];
    
    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = @"AUDIT TRAIL";
    lbl.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightBold];
    lbl.textColor = [UIColor colorWithWhite:0.55 alpha:1.0];
    [topBar addSubview:lbl];
    
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [clearBtn setTitle:@"Clear" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor colorWithRed:0.95 green:0.40 blue:0.40 alpha:1.0] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [clearBtn addTarget:self action:@selector(clearLogs) forControlEvents:UIControlEventTouchUpInside];
    [topBar addSubview:clearBtn];
    
    self.consoleTextView = [[UITextView alloc] init];
    self.consoleTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleTextView.backgroundColor = [UIColor clearColor];
    self.consoleTextView.textColor = [UIColor colorWithRed:0.40 green:0.85 blue:0.65 alpha:1.0];
    self.consoleTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.consoleTextView.editable = NO;
    self.consoleTextView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.consoleContainer addSubview:self.consoleTextView];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.consoleContainer.topAnchor constraintEqualToAnchor:self.segmentedControl.bottomAnchor constant:12],
        [self.consoleContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.consoleContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.consoleContainer.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-12],
        
        [topBar.topAnchor constraintEqualToAnchor:self.consoleContainer.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:self.consoleContainer.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:self.consoleContainer.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:36],
        
        [lbl.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:14],
        [lbl.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        
        [clearBtn.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-14],
        [clearBtn.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        
        [self.consoleTextView.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [self.consoleTextView.leadingAnchor constraintEqualToAnchor:self.consoleContainer.leadingAnchor],
        [self.consoleTextView.trailingAnchor constraintEqualToAnchor:self.consoleContainer.trailingAnchor],
        [self.consoleTextView.bottomAnchor constraintEqualToAnchor:self.consoleContainer.bottomAnchor]
    ]];
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 0) {
        self.tableView.hidden = NO;
        self.consoleContainer.hidden = YES;
    } else {
        self.tableView.hidden = YES;
        self.consoleContainer.hidden = NO;
        [self refreshConsoleDisplay];
    }
}

#pragma mark - TableView Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3; // Daemon status, Port, Transport
    if (section == 1) return 3; // Capabilities: Class 2, Class 7, Class 13
    if (section == 2) return 3; // Device Model, OS Version, Mach PID
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"SERVICE STATUS";
    if (section == 1) return @"SANDBOX CAPABILITIES";
    if (section == 2) return @"HOST ENVIRONMENT";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MHAStatusCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"MHAStatusCell"];
        cell.backgroundColor = [UIColor colorWithRed:0.11 green:0.13 blue:0.17 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Daemon State";
            cell.detailTextLabel.text = [MHAServer sharedServer].isRunning ? @"Listening" : @"Stopped";
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.25 green:0.85 blue:0.55 alpha:1.0];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Listen Address";
            cell.detailTextLabel.text = @"0.0.0.0:8080";
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Tunnel Type";
            cell.detailTextLabel.text = @"USBMux TCP Bridge";
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"App Data (Class 2)";
            cell.detailTextLabel.text = @"Read / Write";
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.35 green:0.85 blue:0.55 alpha:1.0];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"App Groups (Class 7)";
            cell.detailTextLabel.text = @"Read / Write";
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.35 green:0.85 blue:0.55 alpha:1.0];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"System Groups (Class 13)";
            cell.detailTextLabel.text = @"MobileGestalt Cache";
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.35 green:0.85 blue:0.55 alpha:1.0];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Target Hardware";
            cell.detailTextLabel.text = self.deviceModel;
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Software Version";
            cell.detailTextLabel.text = self.osVersion;
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Process Identifier";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"PID %d", [[NSProcessInfo processInfo] processIdentifier]];
            cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
        }
    }
    
    return cell;
}

#pragma mark - MHAServerDelegate

- (void)serverDidLogMessage:(NSString *)message isError:(BOOL)isError {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"HH:mm:ss"];
    NSString *ts = [df stringFromDate:[NSDate date]];
    
    NSString *tag = isError ? @"[ERR]" : @"[INFO]";
    NSString *line = [NSString stringWithFormat:@"%@ %@ %@", ts, tag, message];
    
    [self.logHistory addObject:line];
    if (self.logHistory.count > 300) {
        [self.logHistory removeObjectAtIndex:0];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.consoleContainer.hidden) {
            [self refreshConsoleDisplay];
        }
    });
}

- (void)serverClientCountDidChange:(NSUInteger)count {
    self.activeClientsCount = count;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.tableView reloadData];
    });
}

- (void)refreshConsoleDisplay {
    self.consoleTextView.text = [self.logHistory componentsJoinedByString:@"\n"];
    if (self.consoleTextView.text.length > 0) {
        NSRange bottom = NSMakeRange(self.consoleTextView.text.length - 1, 1);
        [self.consoleTextView scrollRangeToVisible:bottom];
    }
}

- (void)clearLogs {
    [self.logHistory removeAllObjects];
    self.consoleTextView.text = @"";
}

- (void)shareLogs {
    NSString *text = [self.logHistory componentsJoinedByString:@"\n"];
    if (text.length == 0) return;
    
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    [self presentViewController:act animated:YES completion:nil];
}

@end
