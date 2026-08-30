#import "GlassStatusViewController.h"
#import <sys/utsname.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@interface GlassStatusViewController () <UIScrollViewDelegate>

// Navigation Bar Segmented Container (Telegram Folder Tabs Style)
@property (nonatomic, strong) UIView *tabsContainer;
@property (nonatomic, strong) UIView *capsuleBackground;
@property (nonatomic, strong) UIView *slidingPill;
@property (nonatomic, strong) UIVisualEffectView *pillGlassEffectView;
@property (nonatomic, strong) UIView *pillHighlightView;
@property (nonatomic, strong) UIButton *dashboardTabBtn;
@property (nonatomic, strong) UIButton *consoleTabBtn;
@property (nonatomic, strong) UILabel *consoleUnreadBadge;
@property (nonatomic, strong) UIView *liveStatusDot;

// Dynamic Transition / Lifted State (Telegram isLifted logic)
@property (nonatomic, assign) BOOL isLifted;
@property (nonatomic, strong) NSTimer *liftTimer;

// Fullscreen Page Scroll View
@property (nonatomic, strong) UIScrollView *pagingScrollView;
@property (nonatomic, strong) UITableView *dashboardTableView;
@property (nonatomic, strong) UIView *consoleView;
@property (nonatomic, strong) UITextView *consoleTextView;
@property (nonatomic, strong) NSMutableArray<NSString *> *logHistory;

// System Metadata
@property (nonatomic, strong) NSString *deviceModel;
@property (nonatomic, strong) NSString *osVersion;
@property (nonatomic, assign) NSUInteger activeClientsCount;

@end

static const CGFloat kTotalWidth = 240.0;
static const CGFloat kTotalHeight = 36.0;
static const CGFloat kPadding = 3.0;
static const CGFloat kPillHeight = 30.0;
static const CGFloat kPillWidth = 114.0; // (240 - 2*3) / 2 - 3 = 114

@implementation GlassStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    self.logHistory = [NSMutableArray array];
    self.isLifted = NO;
    
    [self loadSystemInfo];
    [self setupTelegramStyleFolderTabs];
    [self setupFullscreenPaging];
    
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

#pragma mark - Telegram-iOS Style Folder Tabs Navigation

- (UIVisualEffect *)createAppleGlassEffect {
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    if (glassClass) {
        UIVisualEffect *glass = [[glassClass alloc] init];
        if (glass) return glass;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark];
}

- (void)setupTelegramStyleFolderTabs {
    if (!self.navigationController) return;
    
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.22 green:0.53 blue:0.95 alpha:1.0];
    
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.shadowColor = [UIColor clearColor];
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.compactAppearance = appearance;
    
    UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareLogs)];
    self.navigationItem.rightBarButtonItem = shareItem;
    
    // === Main Capsule Container (240 x 36) ===
    self.tabsContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kTotalWidth, kTotalHeight)];
    self.tabsContainer.backgroundColor = [UIColor clearColor];
    
    // === Outer Resting Capsule Background ===
    self.capsuleBackground = [[UIView alloc] initWithFrame:self.tabsContainer.bounds];
    self.capsuleBackground.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:0.85];
    self.capsuleBackground.layer.cornerRadius = kTotalHeight * 0.5;
    self.capsuleBackground.layer.cornerCurve = kCACornerCurveContinuous;
    self.capsuleBackground.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    self.capsuleBackground.layer.borderWidth = 0.5;
    self.capsuleBackground.clipsToBounds = YES;
    self.capsuleBackground.userInteractionEnabled = NO;
    [self.tabsContainer addSubview:self.capsuleBackground];
    
    // === Sliding Indicator Pill (Contains UIGlassEffect for dynamic liquid glass) ===
    self.slidingPill = [[UIView alloc] initWithFrame:CGRectMake(kPadding, kPadding, kPillWidth, kPillHeight)];
    self.slidingPill.layer.cornerRadius = kPillHeight * 0.5;
    self.slidingPill.layer.cornerCurve = kCACornerCurveContinuous;
    self.slidingPill.clipsToBounds = YES;
    self.slidingPill.userInteractionEnabled = NO;
    
    // 1. Apple UIGlassEffect View (Active during transition)
    UIVisualEffect *glassEffect = [self createAppleGlassEffect];
    self.pillGlassEffectView = [[UIVisualEffectView alloc] initWithEffect:glassEffect];
    self.pillGlassEffectView.frame = self.slidingPill.bounds;
    self.pillGlassEffectView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.pillGlassEffectView.alpha = 0.0; // In resting state, subtle highlight is shown instead
    [self.slidingPill addSubview:self.pillGlassEffectView];
    
    // 2. Resting Highlight View (Subtle clean material in resting state)
    self.pillHighlightView = [[UIView alloc] initWithFrame:self.slidingPill.bounds];
    self.pillHighlightView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.pillHighlightView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    self.pillHighlightView.layer.cornerRadius = kPillHeight * 0.5;
    self.pillHighlightView.layer.cornerCurve = kCACornerCurveContinuous;
    self.pillHighlightView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.20].CGColor;
    self.pillHighlightView.layer.borderWidth = 0.5;
    [self.slidingPill addSubview:self.pillHighlightView];
    
    [self.tabsContainer addSubview:self.slidingPill];
    
    // === Interactive Tab 1: Dashboard ===
    self.dashboardTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dashboardTabBtn.frame = CGRectMake(0, 0, kTotalWidth * 0.5, kTotalHeight);
    [self.dashboardTabBtn setTitle:@"Dashboard" forState:UIControlStateNormal];
    [self.dashboardTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.dashboardTabBtn addTarget:self action:@selector(selectDashboard) forControlEvents:UIControlEventTouchUpInside];
    [self.tabsContainer addSubview:self.dashboardTabBtn];
    
    // Green Online Status Dot
    self.liveStatusDot = [[UIView alloc] initWithFrame:CGRectMake(14, 15, 6, 6)];
    self.liveStatusDot.backgroundColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.55 alpha:1.0];
    self.liveStatusDot.layer.cornerRadius = 3;
    self.liveStatusDot.userInteractionEnabled = NO;
    [self.dashboardTabBtn addSubview:self.liveStatusDot];
    
    // === Interactive Tab 2: Console ===
    self.consoleTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.consoleTabBtn.frame = CGRectMake(kTotalWidth * 0.5, 0, kTotalWidth * 0.5, kTotalHeight);
    [self.consoleTabBtn setTitle:@"Console" forState:UIControlStateNormal];
    [self.consoleTabBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
    self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.consoleTabBtn addTarget:self action:@selector(selectConsole) forControlEvents:UIControlEventTouchUpInside];
    [self.tabsContainer addSubview:self.consoleTabBtn];
    
    // Badge
    self.consoleUnreadBadge = [[UILabel alloc] initWithFrame:CGRectMake(86, 10, 18, 16)];
    self.consoleUnreadBadge.text = @"0";
    self.consoleUnreadBadge.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    self.consoleUnreadBadge.textColor = [UIColor whiteColor];
    self.consoleUnreadBadge.textAlignment = NSTextAlignmentCenter;
    self.consoleUnreadBadge.backgroundColor = [UIColor colorWithRed:0.22 green:0.53 blue:0.95 alpha:0.90];
    self.consoleUnreadBadge.layer.cornerRadius = 8;
    self.consoleUnreadBadge.layer.masksToBounds = YES;
    self.consoleUnreadBadge.userInteractionEnabled = NO;
    [self.consoleTabBtn addSubview:self.consoleUnreadBadge];
    
    self.navigationItem.titleView = self.tabsContainer;
}

#pragma mark - Telegram-iOS Lift / Transition Animation

- (void)setLifted:(BOOL)lifted animated:(BOOL)animated {
    if (self.isLifted == lifted) return;
    self.isLifted = lifted;
    
    void (^animations)(void) = ^{
        if (lifted) {
            // Transition state: activate liquid glass refraction, fade out static capsule
            self.pillGlassEffectView.alpha = 1.0;
            self.pillHighlightView.alpha = 0.0;
            self.capsuleBackground.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:0.40];
            self.capsuleBackground.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
            self.slidingPill.transform = CGAffineTransformMakeScale(1.04, 1.04);
        } else {
            // Resting state: settle down to clean resting material
            self.pillGlassEffectView.alpha = 0.0;
            self.pillHighlightView.alpha = 1.0;
            self.capsuleBackground.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:0.85];
            self.capsuleBackground.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
            self.slidingPill.transform = CGAffineTransformIdentity;
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:animations completion:nil];
    } else {
        animations();
    }
}

#pragma mark - Fullscreen Horizontal Pager

- (void)setupFullscreenPaging {
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
        [self.pagingScrollView.topAnchor constraintEqualToAnchor:guide.topAnchor],
        [self.pagingScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.pagingScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.pagingScrollView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];
    
    // Page 1: Dashboard
    self.dashboardTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.dashboardTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dashboardTableView.backgroundColor = [UIColor blackColor];
    self.dashboardTableView.dataSource = self;
    self.dashboardTableView.delegate = self;
    self.dashboardTableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [self.pagingScrollView addSubview:self.dashboardTableView];
    
    // Page 2: Console
    self.consoleView = [[UIView alloc] init];
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleView.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.05 alpha:1.0];
    self.consoleView.layer.cornerRadius = 16;
    self.consoleView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    self.consoleView.layer.borderWidth = 1.0;
    self.consoleView.layer.masksToBounds = YES;
    [self.pagingScrollView addSubview:self.consoleView];
    
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
    
    [NSLayoutConstraint activateConstraints:@[
        [self.dashboardTableView.topAnchor constraintEqualToAnchor:self.pagingScrollView.topAnchor],
        [self.dashboardTableView.bottomAnchor constraintEqualToAnchor:self.pagingScrollView.bottomAnchor],
        [self.dashboardTableView.leadingAnchor constraintEqualToAnchor:self.pagingScrollView.leadingAnchor],
        [self.dashboardTableView.widthAnchor constraintEqualToAnchor:self.pagingScrollView.widthAnchor],
        [self.dashboardTableView.heightAnchor constraintEqualToAnchor:self.pagingScrollView.heightAnchor],
        
        [self.consoleView.topAnchor constraintEqualToAnchor:self.pagingScrollView.topAnchor constant:12],
        [self.consoleView.bottomAnchor constraintEqualToAnchor:self.pagingScrollView.bottomAnchor constant:-12],
        [self.consoleView.leadingAnchor constraintEqualToAnchor:self.dashboardTableView.trailingAnchor constant:16],
        [self.consoleView.trailingAnchor constraintEqualToAnchor:self.pagingScrollView.trailingAnchor constant:-16],
        [self.consoleView.widthAnchor constraintEqualToAnchor:self.pagingScrollView.widthAnchor constant:-32],
        [self.consoleView.heightAnchor constraintEqualToAnchor:self.pagingScrollView.heightAnchor constant:-24],
        
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

#pragma mark - Telegram-iOS Scroll Synchronization & Dynamic Tracking

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == self.pagingScrollView) {
        [self.liftTimer invalidate];
        self.liftTimer = nil;
        [self setLifted:YES animated:YES];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.pagingScrollView) {
        CGFloat pageWidth = self.pagingScrollView.bounds.size.width;
        if (pageWidth <= 0) return;
        
        CGFloat progress = self.pagingScrollView.contentOffset.x / pageWidth;
        progress = fmax(0.0, fmin(1.0, progress));
        
        // Telegram: interpolate indicator position between tab bounds
        CGFloat startX = kPadding;
        CGFloat endX = kTotalWidth * 0.5 + kPadding;
        CGFloat currentX = startX + progress * (endX - startX);
        
        self.slidingPill.frame = CGRectMake(currentX, kPadding, kPillWidth, kPillHeight);
        
        // Update tab text contrast
        if (progress < 0.5) {
            [self.dashboardTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            [self.consoleTabBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
            self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        } else {
            [self.dashboardTabBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
            self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            [self.consoleTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        }
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.pagingScrollView) {
        [self scheduleLiftEnd];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (scrollView == self.pagingScrollView) {
        [self scheduleLiftEnd];
    }
}

- (void)scheduleLiftEnd {
    [self.liftTimer invalidate];
    self.liftTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:NO block:^(NSTimer * _Nonnull timer) {
        [self setLifted:NO animated:YES];
    }];
}

- (void)selectDashboard {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    [self setLifted:YES animated:YES];
    [self.pagingScrollView setContentOffset:CGPointMake(0, 0) animated:YES];
}

- (void)selectConsole {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    [self setLifted:YES animated:YES];
    CGFloat pageWidth = self.pagingScrollView.bounds.size.width;
    [self.pagingScrollView setContentOffset:CGPointMake(pageWidth, 0) animated:YES];
}

#pragma mark - TableView Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 3; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"SERVICE STATUS";
    if (section == 1) return @"SANDBOX CAPABILITIES";
    if (section == 2) return @"HOST ENVIRONMENT";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MHACell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"MHACell"];
        cell.backgroundColor = [UIColor colorWithRed:0.07 green:0.07 blue:0.09 alpha:1.0];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    if (indexPath.section == 0) {
        if (indexPath.row == 0) { cell.textLabel.text = @"Daemon State"; cell.detailTextLabel.text = [MHAServer sharedServer].isRunning ? @"Listening" : @"Stopped"; cell.detailTextLabel.textColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.55 alpha:1.0]; }
        else if (indexPath.row == 1) { cell.textLabel.text = @"Listen Address"; cell.detailTextLabel.text = @"0.0.0.0:8080"; cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0]; }
        else { cell.textLabel.text = @"Tunnel Type"; cell.detailTextLabel.text = @"USBMux TCP Bridge"; cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0]; }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) { cell.textLabel.text = @"App Data (Class 2)"; cell.detailTextLabel.text = @"Read / Write"; cell.detailTextLabel.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.60 alpha:1.0]; }
        else if (indexPath.row == 1) { cell.textLabel.text = @"App Groups (Class 7)"; cell.detailTextLabel.text = @"Read / Write"; cell.detailTextLabel.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.60 alpha:1.0]; }
        else { cell.textLabel.text = @"System Groups (Class 13)"; cell.detailTextLabel.text = @"MobileGestalt Cache"; cell.detailTextLabel.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.60 alpha:1.0]; }
    } else {
        if (indexPath.row == 0) { cell.textLabel.text = @"Target Hardware"; cell.detailTextLabel.text = self.deviceModel; cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0]; }
        else if (indexPath.row == 1) { cell.textLabel.text = @"Software Version"; cell.detailTextLabel.text = self.osVersion; cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0]; }
        else { cell.textLabel.text = @"Process Identifier"; cell.detailTextLabel.text = [NSString stringWithFormat:@"PID %d", [[NSProcessInfo processInfo] processIdentifier]]; cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.75 alpha:1.0]; }
    }
    return cell;
}

#pragma mark - MHAServerDelegate

- (void)serverDidLogMessage:(NSString *)message isError:(BOOL)isError {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"HH:mm:ss"];
    NSString *line = [NSString stringWithFormat:@"%@ %@ %@", [df stringFromDate:[NSDate date]], isError ? @"[ERR]" : @"[INFO]", message];
    [self.logHistory addObject:line];
    if (self.logHistory.count > 300) [self.logHistory removeObjectAtIndex:0];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.consoleUnreadBadge.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.logHistory.count];
        self.consoleTextView.text = [self.logHistory componentsJoinedByString:@"\n"];
        if (self.consoleTextView.text.length > 0)
            [self.consoleTextView scrollRangeToVisible:NSMakeRange(self.consoleTextView.text.length - 1, 1)];
    });
}

- (void)serverClientCountDidChange:(NSUInteger)count {
    self.activeClientsCount = count;
    dispatch_async(dispatch_get_main_queue(), ^{ [self.dashboardTableView reloadData]; });
}

- (void)clearLogs {
    [self.logHistory removeAllObjects];
    self.consoleUnreadBadge.text = @"0";
    self.consoleTextView.text = @"";
}

- (void)shareLogs {
    NSString *text = [self.logHistory componentsJoinedByString:@"\n"];
    if (text.length == 0) return;
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[text] applicationActivities:nil];
    [self presentViewController:act animated:YES completion:nil];
}

@end
