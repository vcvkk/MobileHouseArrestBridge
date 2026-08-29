#import "GlassStatusViewController.h"
#import <sys/utsname.h>

@interface GlassStatusViewController ()

@property (nonatomic, strong) UIVisualEffectView *floatingGlassBar;
@property (nonatomic, strong) UIView *segmentSelectionPill;
@property (nonatomic, strong) UIButton *dashboardBtn;
@property (nonatomic, strong) UIButton *consoleBtn;
@property (nonatomic, assign) NSInteger currentSegmentIndex;

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *consoleContainer;
@property (nonatomic, strong) UITextView *consoleTextView;
@property (nonatomic, strong) NSMutableArray<NSString *> *logHistory;

@property (nonatomic, strong) NSString *deviceModel;
@property (nonatomic, strong) NSString *osVersion;
@property (nonatomic, strong) UIImpactFeedbackGenerator *hapticFeedback;

@end

@implementation GlassStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HouseArrest";
    self.view.backgroundColor = [UIColor blackColor]; // True OLED Black
    self.logHistory = [NSMutableArray array];
    self.currentSegmentIndex = 0;
    self.hapticFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    
    [self loadSystemInfo];
    [self setupNavigationBar];
    [self setupTableView];
    [self setupConsoleView];
    [self setupFloatingGlassSegmentedControl];
    
    [MHAServer sharedServer].delegate = self;
    
    NSError *error = nil;
    if (![[MHAServer sharedServer] startOnPort:8080 error:&error]) {
        [self serverDidLogMessage:[NSString stringWithFormat:@"Failed to bind port 8080: %@", error.localizedDescription] isError:YES];
    } else {
        [self serverDidLogMessage:@"MobileHouseArrest daemon online (0.0.0.0:8080)" isError:NO];
        [self serverDidLogMessage:@"OLED Liquid Glass environment ready for USB bridge." isError:NO];
    }
}

- (void)loadSystemInfo {
    struct utsname systemInfo;
    uname(&systemInfo);
    self.deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] ?: @"iPhone";
    
    NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
    self.osVersion = [NSString stringWithFormat:@"iOS %ld.%ld.%ld", (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion];
}

- (void)setupNavigationBar {
    if (self.navigationController) {
        self.navigationController.navigationBar.prefersLargeTitles = YES;
        self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
        self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.25 green:0.85 blue:0.55 alpha:1.0];
        
        UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareLogs)];
        self.navigationItem.rightBarButtonItem = shareItem;
    }
}

#pragma mark - Native iOS 26 Liquid Glass Floating Segmented Picker

- (void)setupFloatingGlassSegmentedControl {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.floatingGlassBar = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.floatingGlassBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.floatingGlassBar.layer.cornerRadius = 20;
    self.floatingGlassBar.layer.masksToBounds = YES;
    self.floatingGlassBar.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    self.floatingGlassBar.layer.borderWidth = 1.0;
    [self.view addSubview:self.floatingGlassBar];
    
    // Sliding Selection Pill
    self.segmentSelectionPill = [[UIView alloc] initWithFrame:CGRectZero];
    self.segmentSelectionPill.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    self.segmentSelectionPill.layer.cornerRadius = 16;
    self.segmentSelectionPill.layer.masksToBounds = YES;
    [self.floatingGlassBar.contentView addSubview:self.segmentSelectionPill];
    
    // Stack for Buttons
    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.distribution = UIStackViewDistributionFillEqually;
    stack.spacing = 4;
    [self.floatingGlassBar.contentView addSubview:stack];
    
    self.dashboardBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.dashboardBtn setTitle:@"Dashboard" forState:UIControlStateNormal];
    [self.dashboardBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.dashboardBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.dashboardBtn addTarget:self action:@selector(selectDashboard) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.dashboardBtn];
    
    self.consoleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.consoleBtn setTitle:@"Console Logs" forState:UIControlStateNormal];
    [self.consoleBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
    self.consoleBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.consoleBtn addTarget:self action:@selector(selectConsole) forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.consoleBtn];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.floatingGlassBar.topAnchor constraintEqualToAnchor:guide.topAnchor constant:6],
        [self.floatingGlassBar.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.floatingGlassBar.widthAnchor constraintEqualToConstant:290],
        [self.floatingGlassBar.heightAnchor constraintEqualToConstant:40],
        
        [stack.topAnchor constraintEqualToAnchor:self.floatingGlassBar.contentView.topAnchor constant:3],
        [stack.leadingAnchor constraintEqualToAnchor:self.floatingGlassBar.contentView.leadingAnchor constant:4],
        [stack.trailingAnchor constraintEqualToAnchor:self.floatingGlassBar.contentView.trailingAnchor constant:-4],
        [stack.bottomAnchor constraintEqualToAnchor:self.floatingGlassBar.contentView.bottomAnchor constant:-3]
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateSelectionPillAnimated:NO];
}

- (void)updateSelectionPillAnimated:(BOOL)animated {
    CGFloat pillWidth = (290 - 8 - 4) / 2.0;
    CGFloat pillHeight = 34;
    CGFloat pillX = 4 + self.currentSegmentIndex * (pillWidth + 4);
    CGRect targetFrame = CGRectMake(pillX, 3, pillWidth, pillHeight);
    
    void (^animations)(void) = ^{
        self.segmentSelectionPill.frame = targetFrame;
        if (self.currentSegmentIndex == 0) {
            [self.dashboardBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.dashboardBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            [self.consoleBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
            self.consoleBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        } else {
            [self.dashboardBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
            self.dashboardBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            [self.consoleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.consoleBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseInOut animations:animations completion:nil];
    } else {
        animations();
    }
}

- (void)selectDashboard {
    if (self.currentSegmentIndex == 0) return;
    self.currentSegmentIndex = 0;
    [self.hapticFeedback impactOccurred];
    [self updateSelectionPillAnimated:YES];
    
    [UIView transitionWithView:self.view duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        self.tableView.hidden = NO;
        self.consoleContainer.hidden = YES;
    } completion:nil];
}

- (void)selectConsole {
    if (self.currentSegmentIndex == 1) return;
    self.currentSegmentIndex = 1;
    [self.hapticFeedback impactOccurred];
    [self updateSelectionPillAnimated:YES];
    
    [self refreshConsoleDisplay];
    [UIView transitionWithView:self.view duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        self.tableView.hidden = YES;
        self.consoleContainer.hidden = NO;
    } completion:nil];
}

#pragma mark - OLED TableView & Console Layout

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor blackColor]; // Pure OLED
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [self.view addSubview:self.tableView];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:54],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];
}

- (void)setupConsoleView {
    self.consoleContainer = [[UIView alloc] init];
    self.consoleContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleContainer.hidden = YES;
    self.consoleContainer.backgroundColor = [UIColor blackColor]; // Pure OLED Black
    self.consoleContainer.layer.cornerRadius = 20;
    self.consoleContainer.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    self.consoleContainer.layer.borderWidth = 1.0;
    self.consoleContainer.layer.masksToBounds = YES;
    [self.view addSubview:self.consoleContainer];
    
    // Top Bar inside console with Liquid Glass Clear Button
    UIView *topBar = [[UIView alloc] init];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    topBar.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:1.0];
    [self.consoleContainer addSubview:topBar];
    
    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.text = @"AUDIT CONSOLE";
    lbl.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightBold];
    lbl.textColor = [UIColor colorWithWhite:0.50 alpha:1.0];
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
    self.consoleTextView.backgroundColor = [UIColor blackColor];
    self.consoleTextView.textColor = [UIColor colorWithRed:0.35 green:0.85 blue:0.60 alpha:1.0];
    self.consoleTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.consoleTextView.editable = NO;
    self.consoleTextView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.consoleContainer addSubview:self.consoleTextView];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.consoleContainer.topAnchor constraintEqualToAnchor:guide.topAnchor constant:54],
        [self.consoleContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.consoleContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.consoleContainer.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-12],
        
        [topBar.topAnchor constraintEqualToAnchor:self.consoleContainer.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:self.consoleContainer.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:self.consoleContainer.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:38],
        
        [lbl.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:16],
        [lbl.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        
        [clearBtn.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-16],
        [clearBtn.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        
        [self.consoleTextView.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [self.consoleTextView.leadingAnchor constraintEqualToAnchor:self.consoleContainer.leadingAnchor],
        [self.consoleTextView.trailingAnchor constraintEqualToAnchor:self.consoleContainer.trailingAnchor],
        [self.consoleTextView.bottomAnchor constraintEqualToAnchor:self.consoleContainer.bottomAnchor]
    ]];
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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MHAOLEDCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"MHAOLEDCell"];
        cell.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:1.0]; // Deep Obsidian OLED Cell
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
