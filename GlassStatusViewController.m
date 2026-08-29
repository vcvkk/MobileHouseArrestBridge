#import "GlassStatusViewController.h"
#import <sys/utsname.h>
#import <objc/message.h>
#import <objc/runtime.h>

@interface GlassStatusViewController () <UIScrollViewDelegate>

// Telegram-iOS Style Folder Tab Bar
@property (nonatomic, strong) UIView *tabBarContainer;
@property (nonatomic, strong) UIVisualEffectView *tabBarBlurView;
@property (nonatomic, strong) UIView *slidingPillIndicator;
@property (nonatomic, strong) UIButton *dashboardTabBtn;
@property (nonatomic, strong) UIButton *consoleTabBtn;
@property (nonatomic, strong) UILabel *consoleBadgeLabel;
@property (nonatomic, strong) UIView *statusDot;

// Interactive Horizontal Paging (Telegram Folder Paging)
@property (nonatomic, strong) UIScrollView *pagingScrollView;
@property (nonatomic, strong) UITableView *dashboardTableView;
@property (nonatomic, strong) UIView *consoleView;
@property (nonatomic, strong) UITextView *consoleTextView;
@property (nonatomic, strong) NSMutableArray<NSString *> *logHistory;

// Host Metadata
@property (nonatomic, strong) NSString *deviceModel;
@property (nonatomic, strong) NSString *osVersion;
@property (nonatomic, assign) NSUInteger activeClientsCount;

@end

@implementation GlassStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HouseArrest";
    self.view.backgroundColor = [UIColor blackColor];
    self.logHistory = [NSMutableArray array];
    
    [self loadSystemInfo];
    [self setupNavigationBar];
    [self setupTelegramFolderTabBar];
    [self setupPagingScrollView];
    
    [MHAServer sharedServer].delegate = self;
    
    NSError *error = nil;
    if (![[MHAServer sharedServer] startOnPort:8080 error:&error]) {
        [self serverDidLogMessage:[NSString stringWithFormat:@"Failed to bind port 8080: %@", error.localizedDescription] isError:YES];
    } else {
        [self serverDidLogMessage:@"HouseArrest daemon listening on 0.0.0.0:8080" isError:NO];
        [self serverDidLogMessage:@"USBMux bridge ready for incoming TCP connections." isError:NO];
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
        self.navigationController.navigationBar.prefersLargeTitles = NO; // Telegram style clean compact top bar
        self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.20 green:0.85 blue:0.55 alpha:1.0];
        
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor blackColor];
        appearance.shadowColor = [UIColor clearColor];
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]
        };
        
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
        self.navigationController.navigationBar.compactAppearance = appearance;
        
        UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareLogs)];
        self.navigationItem.rightBarButtonItem = shareItem;
    }
}

#pragma mark - Telegram-iOS Style Folder Tabs

- (void)setupTelegramFolderTabBar {
    self.tabBarContainer = [[UIView alloc] init];
    self.tabBarContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.tabBarContainer];
    
    // Frosted Capsule Blur
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
    self.tabBarBlurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.tabBarBlurView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tabBarBlurView.layer.cornerRadius = 19;
    self.tabBarBlurView.layer.cornerCurve = kCACornerCurveContinuous;
    self.tabBarBlurView.layer.masksToBounds = YES;
    self.tabBarBlurView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:0.45];
    [self.tabBarContainer addSubview:self.tabBarBlurView];
    
    // Telegram-style Smooth Sliding Pill Indicator
    self.slidingPillIndicator = [[UIView alloc] init];
    self.slidingPillIndicator.backgroundColor = [UIColor colorWithWhite:0.26 alpha:0.80];
    self.slidingPillIndicator.layer.cornerRadius = 15;
    self.slidingPillIndicator.layer.cornerCurve = kCACornerCurveContinuous;
    self.slidingPillIndicator.layer.shadowColor = [UIColor blackColor].CGColor;
    self.slidingPillIndicator.layer.shadowRadius = 4;
    self.slidingPillIndicator.layer.shadowOpacity = 0.3;
    self.slidingPillIndicator.layer.shadowOffset = CGSizeMake(0, 2);
    [self.tabBarBlurView.contentView addSubview:self.slidingPillIndicator];
    
    // Tab 1: Dashboard
    self.dashboardTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dashboardTabBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dashboardTabBtn setTitle:@"Dashboard" forState:UIControlStateNormal];
    [self.dashboardTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.dashboardTabBtn addTarget:self action:@selector(selectDashboardTab) forControlEvents:UIControlEventTouchUpInside];
    [self.tabBarBlurView.contentView addSubview:self.dashboardTabBtn];
    
    // Status Dot inside Dashboard Tab
    self.statusDot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 6)];
    self.statusDot.backgroundColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.55 alpha:1.0];
    self.statusDot.layer.cornerRadius = 3;
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dashboardTabBtn addSubview:self.statusDot];
    
    // Tab 2: Console Logs
    self.consoleTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.consoleTabBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.consoleTabBtn setTitle:@"Console" forState:UIControlStateNormal];
    [self.consoleTabBtn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1.0] forState:UIControlStateNormal];
    self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.consoleTabBtn addTarget:self action:@selector(selectConsoleTab) forControlEvents:UIControlEventTouchUpInside];
    [self.tabBarBlurView.contentView addSubview:self.consoleTabBtn];
    
    // Telegram-style Unread / Event Badge
    self.consoleBadgeLabel = [[UILabel alloc] init];
    self.consoleBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleBadgeLabel.text = @"0";
    self.consoleBadgeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    self.consoleBadgeLabel.textColor = [UIColor whiteColor];
    self.consoleBadgeLabel.textAlignment = NSTextAlignmentCenter;
    self.consoleBadgeLabel.backgroundColor = [UIColor colorWithRed:0.20 green:0.40 blue:0.80 alpha:0.85];
    self.consoleBadgeLabel.layer.cornerRadius = 8;
    self.consoleBadgeLabel.layer.masksToBounds = YES;
    [self.consoleTabBtn addSubview:self.consoleBadgeLabel];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tabBarContainer.topAnchor constraintEqualToAnchor:guide.topAnchor constant:6],
        [self.tabBarContainer.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.tabBarContainer.widthAnchor constraintEqualToConstant:280],
        [self.tabBarContainer.heightAnchor constraintEqualToConstant:38],
        
        [self.tabBarBlurView.leadingAnchor constraintEqualToAnchor:self.tabBarContainer.leadingAnchor],
        [self.tabBarBlurView.trailingAnchor constraintEqualToAnchor:self.tabBarContainer.trailingAnchor],
        [self.tabBarBlurView.topAnchor constraintEqualToAnchor:self.tabBarContainer.topAnchor],
        [self.tabBarBlurView.bottomAnchor constraintEqualToAnchor:self.tabBarContainer.bottomAnchor],
        
        [self.dashboardTabBtn.leadingAnchor constraintEqualToAnchor:self.tabBarBlurView.contentView.leadingAnchor],
        [self.dashboardTabBtn.topAnchor constraintEqualToAnchor:self.tabBarBlurView.contentView.topAnchor],
        [self.dashboardTabBtn.bottomAnchor constraintEqualToAnchor:self.tabBarBlurView.contentView.bottomAnchor],
        [self.dashboardTabBtn.widthAnchor constraintEqualToAnchor:self.tabBarBlurView.contentView.widthAnchor multiplier:0.5],
        
        [self.statusDot.centerYAnchor constraintEqualToAnchor:self.dashboardTabBtn.centerYAnchor],
        [self.statusDot.trailingAnchor constraintEqualToAnchor:self.dashboardTabBtn.titleLabel.leadingAnchor constant:-6],
        [self.statusDot.widthAnchor constraintEqualToConstant:6],
        [self.statusDot.heightAnchor constraintEqualToConstant:6],
        
        [self.consoleTabBtn.trailingAnchor constraintEqualToAnchor:self.tabBarBlurView.contentView.trailingAnchor],
        [self.consoleTabBtn.topAnchor constraintEqualToAnchor:self.tabBarBlurView.contentView.topAnchor],
        [self.consoleTabBtn.bottomAnchor constraintEqualToAnchor:self.tabBarBlurView.contentView.bottomAnchor],
        [self.consoleTabBtn.widthAnchor constraintEqualToAnchor:self.tabBarBlurView.contentView.widthAnchor multiplier:0.5],
        
        [self.consoleBadgeLabel.centerYAnchor constraintEqualToAnchor:self.consoleTabBtn.centerYAnchor],
        [self.consoleBadgeLabel.leadingAnchor constraintEqualToAnchor:self.consoleTabBtn.titleLabel.trailingAnchor constant:6],
        [self.consoleBadgeLabel.heightAnchor constraintEqualToConstant:16],
        [self.consoleBadgeLabel.widthAnchor constraintGreaterThanOrEqualToConstant:18]
    ]];
}

#pragma mark - Telegram-iOS Interactive Horizontal Paging

- (void)setupPagingScrollView {
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    
    self.pagingScrollView = [[UIScrollView alloc] init];
    self.pagingScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.pagingScrollView.pagingEnabled = YES;
    self.pagingScrollView.showsHorizontalScrollIndicator = NO;
    self.pagingScrollView.showsVerticalScrollIndicator = NO;
    self.pagingScrollView.bounces = YES;
    self.pagingScrollView.delegate = self;
    self.pagingScrollView.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.pagingScrollView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.pagingScrollView.topAnchor constraintEqualToAnchor:self.tabBarContainer.bottomAnchor constant:8],
        [self.pagingScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pagingScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.pagingScrollView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];
    
    // Page 1: Dashboard TableView
    self.dashboardTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.dashboardTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dashboardTableView.backgroundColor = [UIColor blackColor];
    self.dashboardTableView.dataSource = self;
    self.dashboardTableView.delegate = self;
    self.dashboardTableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [self.pagingScrollView addSubview:self.dashboardTableView];
    
    // Page 2: Console Log View
    self.consoleView = [[UIView alloc] init];
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleView.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.05 alpha:1.0];
    self.consoleView.layer.cornerRadius = 16;
    self.consoleView.layer.cornerCurve = kCACornerCurveContinuous;
    self.consoleView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    self.consoleView.layer.borderWidth = 1.0;
    self.consoleView.layer.masksToBounds = YES;
    [self.pagingScrollView addSubview:self.consoleView];
    
    // Top Bar inside console with Clear Button
    UIView *topBar = [[UIView alloc] init];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    topBar.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];
    [self.consoleView addSubview:topBar];
    
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
    self.consoleTextView.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.65 alpha:1.0];
    self.consoleTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.consoleTextView.editable = NO;
    self.consoleTextView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.consoleView addSubview:self.consoleTextView];
    
    // Autolayout for 2 horizontal pages
    [NSLayoutConstraint activateConstraints:@[
        // ScrollView Content Layout
        [self.dashboardTableView.topAnchor constraintEqualToAnchor:self.pagingScrollView.topAnchor],
        [self.dashboardTableView.bottomAnchor constraintEqualToAnchor:self.pagingScrollView.bottomAnchor],
        [self.dashboardTableView.leadingAnchor constraintEqualToAnchor:self.pagingScrollView.leadingAnchor],
        [self.dashboardTableView.widthAnchor constraintEqualToAnchor:self.pagingScrollView.widthAnchor],
        [self.dashboardTableView.heightAnchor constraintEqualToAnchor:self.pagingScrollView.heightAnchor],
        
        [self.consoleView.topAnchor constraintEqualToAnchor:self.pagingScrollView.topAnchor constant:8],
        [self.consoleView.bottomAnchor constraintEqualToAnchor:self.pagingScrollView.bottomAnchor constant:-8],
        [self.consoleView.leadingAnchor constraintEqualToAnchor:self.dashboardTableView.trailingAnchor constant:16],
        [self.consoleView.trailingAnchor constraintEqualToAnchor:self.pagingScrollView.trailingAnchor constant:-16],
        [self.consoleView.widthAnchor constraintEqualToAnchor:self.pagingScrollView.widthAnchor constant:-32],
        [self.consoleView.heightAnchor constraintEqualToAnchor:self.pagingScrollView.heightAnchor constant:-16],
        
        [topBar.topAnchor constraintEqualToAnchor:self.consoleView.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:self.consoleView.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:self.consoleView.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:36],
        
        [lbl.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor constant:14],
        [lbl.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        
        [clearBtn.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor constant:-14],
        [clearBtn.centerYAnchor constraintEqualToAnchor:topBar.centerYAnchor],
        
        [self.consoleTextView.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [self.consoleTextView.leadingAnchor constraintEqualToAnchor:self.consoleView.leadingAnchor],
        [self.consoleTextView.trailingAnchor constraintEqualToAnchor:self.consoleView.trailingAnchor],
        [self.consoleTextView.bottomAnchor constraintEqualToAnchor:self.consoleView.bottomAnchor]
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updatePillPositionFromScrollProgress];
}

#pragma mark - Telegram Sliding Pill Dynamic Interpolation

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.pagingScrollView) {
        [self updatePillPositionFromScrollProgress];
    }
}

- (void)updatePillPositionFromScrollProgress {
    CGFloat totalW = self.tabBarBlurView.bounds.size.width;
    CGFloat h = self.tabBarBlurView.bounds.size.height;
    if (totalW <= 0 || h <= 0) return;
    
    CGFloat pageWidth = self.pagingScrollView.bounds.size.width;
    if (pageWidth <= 0) return;
    
    CGFloat progress = self.pagingScrollView.contentOffset.x / pageWidth;
    progress = fmax(0.0, fmin(1.0, progress));
    
    CGFloat padding = 3.0;
    CGFloat pillW = (totalW / 2.0) - (padding * 2);
    CGFloat pillH = h - (padding * 2);
    CGFloat pillX = padding + (progress * (totalW / 2.0));
    
    self.slidingPillIndicator.frame = CGRectMake(pillX, padding, pillW, pillH);
    
    // Dynamic text color interpolation
    if (progress < 0.5) {
        [self.dashboardTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        [self.consoleTabBtn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1.0] forState:UIControlStateNormal];
        self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    } else {
        [self.dashboardTabBtn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1.0] forState:UIControlStateNormal];
        self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [self.consoleTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    }
}

- (void)selectDashboardTab {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    [self.pagingScrollView setContentOffset:CGPointMake(0, 0) animated:YES];
}

- (void)selectConsoleTab {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    CGFloat pageWidth = self.pagingScrollView.bounds.size.width;
    [self.pagingScrollView setContentOffset:CGPointMake(pageWidth, 0) animated:YES];
}

#pragma mark - TableView Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;
    if (section == 1) return 3;
    if (section == 2) return 3;
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"SERVICE STATUS";
    if (section == 1) return @"SANDBOX CAPABILITIES";
    if (section == 2) return @"HOST ENVIRONMENT";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MHATelegramCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"MHATelegramCell"];
        cell.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.09 alpha:1.0];
        cell.layer.cornerRadius = 12;
        cell.layer.cornerCurve = kCACornerCurveContinuous;
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Daemon State";
            cell.detailTextLabel.text = [MHAServer sharedServer].isRunning ? @"Listening" : @"Stopped";
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.55 alpha:1.0];
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
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.60 alpha:1.0];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"App Groups (Class 7)";
            cell.detailTextLabel.text = @"Read / Write";
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.60 alpha:1.0];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"System Groups (Class 13)";
            cell.detailTextLabel.text = @"MobileGestalt Cache";
            cell.detailTextLabel.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.60 alpha:1.0];
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
        self.consoleBadgeLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.logHistory.count];
        self.consoleTextView.text = [self.logHistory componentsJoinedByString:@"\n"];
        if (self.consoleTextView.text.length > 0) {
            NSRange bottom = NSMakeRange(self.consoleTextView.text.length - 1, 1);
            [self.consoleTextView scrollRangeToVisible:bottom];
        }
    });
}

- (void)serverClientCountDidChange:(NSUInteger)count {
    self.activeClientsCount = count;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.dashboardTableView reloadData];
    });
}

- (void)clearLogs {
    [self.logHistory removeAllObjects];
    self.consoleBadgeLabel.text = @"0";
    self.consoleTextView.text = @"";
}

- (void)shareLogs {
    NSString *text = [self.logHistory componentsJoinedByString:@"\n"];
    if (text.length == 0) return;
    
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    [self presentViewController:act animated:YES completion:nil];
}

@end
