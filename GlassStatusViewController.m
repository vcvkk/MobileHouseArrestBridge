#import "GlassStatusViewController.h"
#import <sys/utsname.h>
#import <QuartzCore/QuartzCore.h>

@interface GlassStatusViewController ()

// Apple HIG Liquid Glass Floating Navigation Component
@property (nonatomic, strong) UIVisualEffectView *liquidGlassContainer;
@property (nonatomic, strong) CAGradientLayer *specularRimBorder;
@property (nonatomic, strong) UIVisualEffectView *glassPillEffectView;
@property (nonatomic, strong) UIButton *dashboardTabBtn;
@property (nonatomic, strong) UIButton *consoleTabBtn;
@property (nonatomic, assign) NSInteger selectedTab;

// OLED Content Views
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *consoleContainer;
@property (nonatomic, strong) UITextView *consoleTextView;
@property (nonatomic, strong) NSMutableArray<NSString *> *logHistory;

// Host System Metadata
@property (nonatomic, strong) NSString *deviceModel;
@property (nonatomic, strong) NSString *osVersion;
@property (nonatomic, assign) NSUInteger activeClientsCount;

@end

@implementation GlassStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"HouseArrest";
    
    // OLED True Black Canvas
    self.view.backgroundColor = [UIColor blackColor];
    self.logHistory = [NSMutableArray array];
    self.selectedTab = 0;
    
    [self loadSystemInfo];
    [self setupNavigationBar];
    [self setupNativeLiquidGlassNavigation];
    [self setupTableView];
    [self setupConsoleView];
    
    [MHAServer sharedServer].delegate = self;
    
    NSError *error = nil;
    if (![[MHAServer sharedServer] startOnPort:8080 error:&error]) {
        [self serverDidLogMessage:[NSString stringWithFormat:@"Failed to bind port 8080: %@", error.localizedDescription] isError:YES];
    } else {
        [self serverDidLogMessage:@"HouseArrest daemon active on 0.0.0.0:8080" isError:NO];
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
        self.navigationController.navigationBar.prefersLargeTitles = YES;
        self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.20 green:0.85 blue:0.55 alpha:1.0];
        
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor blackColor];
        appearance.shadowColor = [UIColor clearColor];
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightBold]
        };
        appearance.largeTitleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont systemFontOfSize:34 weight:UIFontWeightHeavy]
        };
        
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
        self.navigationController.navigationBar.compactAppearance = appearance;
        
        UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareLogs)];
        self.navigationItem.rightBarButtonItem = shareItem;
    }
}

#pragma mark - Native Apple HIG Liquid Glass Navigation (iOS 26 Architecture)

- (void)setupNativeLiquidGlassNavigation {
    // 1. Dynamic Glass Effect Lookup (UIGlassEffect on iOS 26+ with fallback to UltraThinMaterial)
    UIVisualEffect *glassEffect = nil;
    Class glassClass = NSClassFromString(@"UIGlassEffect");
    if (glassClass && [glassClass respondsToSelector:sel_registerName("effectWithStyle:")]) {
        glassEffect = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassClass, sel_registerName("effectWithStyle:"), 0);
    }
    if (!glassEffect) {
        glassEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    }
    
    // 2. Outer Liquid Glass Capsule Container (concentric continuous capsule)
    self.liquidGlassContainer = [[UIVisualEffectView alloc] initWithEffect:glassEffect];
    self.liquidGlassContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.liquidGlassContainer.layer.cornerRadius = 24;
    self.liquidGlassContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.liquidGlassContainer.layer.masksToBounds = YES;
    self.liquidGlassContainer.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.40];
    [self.view addSubview:self.liquidGlassContainer];
    
    // 3. Specular Incident Light Rim (Apple HIG 45° refraction highlight)
    self.specularRimBorder = [CAGradientLayer layer];
    self.specularRimBorder.cornerRadius = 24;
    self.specularRimBorder.cornerCurve = kCACornerCurveContinuous;
    self.specularRimBorder.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.40].CGColor, // Top-left specular highlight
        (id)[UIColor colorWithWhite:1.0 alpha:0.12].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.04].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.20].CGColor  // Bottom-right caustic reflection
    ];
    self.specularRimBorder.startPoint = CGPointMake(0.0, 0.0);
    self.specularRimBorder.endPoint = CGPointMake(1.0, 1.0);
    
    CAShapeLayer *rimMask = [CAShapeLayer layer];
    rimMask.lineWidth = 1.2;
    rimMask.fillColor = [UIColor clearColor].CGColor;
    rimMask.strokeColor = [UIColor whiteColor].CGColor;
    self.specularRimBorder.mask = rimMask;
    [self.liquidGlassContainer.layer addSublayer:self.specularRimBorder];
    
    // 4. Morphing Glass Selection Pill (Concentric Geometry: r_inner = r_outer - padding = 24 - 4 = 20)
    UIBlurEffect *pillBlur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    self.glassPillEffectView = [[UIVisualEffectView alloc] initWithEffect:pillBlur];
    self.glassPillEffectView.layer.cornerRadius = 20;
    self.glassPillEffectView.layer.cornerCurve = kCACornerCurveContinuous;
    self.glassPillEffectView.layer.masksToBounds = YES;
    self.glassPillEffectView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    self.glassPillEffectView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
    self.glassPillEffectView.layer.borderWidth = 1.0;
    [self.liquidGlassContainer.contentView addSubview:self.glassPillEffectView];
    
    // 5. Interactive Touch Targets (HIG Touch Area >= 44pt)
    self.dashboardTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dashboardTabBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.dashboardTabBtn setTitle:@"Dashboard" forState:UIControlStateNormal];
    [self.dashboardTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.dashboardTabBtn addTarget:self action:@selector(dashboardTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.dashboardTabBtn addTarget:self action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown];
    [self.dashboardTabBtn addTarget:self action:@selector(touchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.liquidGlassContainer.contentView addSubview:self.dashboardTabBtn];
    
    self.consoleTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.consoleTabBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.consoleTabBtn setTitle:@"Console Logs" forState:UIControlStateNormal];
    [self.consoleTabBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
    self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self.consoleTabBtn addTarget:self action:@selector(consoleTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.consoleTabBtn addTarget:self action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown];
    [self.consoleTabBtn addTarget:self action:@selector(touchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.liquidGlassContainer.contentView addSubview:self.consoleTabBtn];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.liquidGlassContainer.topAnchor constraintEqualToAnchor:guide.topAnchor constant:4],
        [self.liquidGlassContainer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.liquidGlassContainer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.liquidGlassContainer.heightAnchor constraintEqualToConstant:48],
        
        [self.dashboardTabBtn.leadingAnchor constraintEqualToAnchor:self.liquidGlassContainer.contentView.leadingAnchor],
        [self.dashboardTabBtn.topAnchor constraintEqualToAnchor:self.liquidGlassContainer.contentView.topAnchor],
        [self.dashboardTabBtn.bottomAnchor constraintEqualToAnchor:self.liquidGlassContainer.contentView.bottomAnchor],
        [self.dashboardTabBtn.widthAnchor constraintEqualToAnchor:self.liquidGlassContainer.contentView.widthAnchor multiplier:0.5],
        
        [self.consoleTabBtn.trailingAnchor constraintEqualToAnchor:self.liquidGlassContainer.contentView.trailingAnchor],
        [self.consoleTabBtn.topAnchor constraintEqualToAnchor:self.liquidGlassContainer.contentView.topAnchor],
        [self.consoleTabBtn.bottomAnchor constraintEqualToAnchor:self.liquidGlassContainer.contentView.bottomAnchor],
        [self.consoleTabBtn.widthAnchor constraintEqualToAnchor:self.liquidGlassContainer.contentView.widthAnchor multiplier:0.5]
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // Update specular rim border geometry
    self.specularRimBorder.frame = self.liquidGlassContainer.bounds;
    CAShapeLayer *mask = (CAShapeLayer *)self.specularRimBorder.mask;
    if (mask) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.liquidGlassContainer.bounds, 0.6, 0.6)
                                                        cornerRadius:24];
        mask.path = path.CGPath;
    }
    
    [self updatePillFrameAnimated:NO];
}

- (void)updatePillFrameAnimated:(BOOL)animated {
    CGFloat totalW = self.liquidGlassContainer.bounds.size.width;
    CGFloat h = self.liquidGlassContainer.bounds.size.height;
    if (totalW <= 0 || h <= 0) return;
    
    CGFloat padding = 4.0;
    CGFloat pillW = (totalW / 2.0) - (padding * 2);
    CGFloat pillH = h - (padding * 2);
    CGFloat pillX = (self.selectedTab == 0) ? padding : (totalW / 2.0) + padding;
    CGRect targetRect = CGRectMake(pillX, padding, pillW, pillH);
    
    void (^animations)(void) = ^{
        self.glassPillEffectView.frame = targetRect;
        if (self.selectedTab == 0) {
            [self.dashboardTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
            [self.consoleTabBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
            self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        } else {
            [self.dashboardTabBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
            self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
            [self.consoleTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        }
    };
    
    if (animated) {
        UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [haptic impactOccurred];
        [UIView animateWithDuration:0.38
                              delay:0
             usingSpringWithDamping:0.75
              initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:animations
                         completion:nil];
    } else {
        animations();
    }
}

- (void)touchDown:(UIButton *)btn {
    [UIView animateWithDuration:0.15 animations:^{
        self.liquidGlassContainer.transform = CGAffineTransformMakeScale(0.985, 0.985);
    }];
}

- (void)touchUp:(UIButton *)btn {
    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.5 options:0 animations:^{
        self.liquidGlassContainer.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dashboardTapped {
    if (self.selectedTab == 0) return;
    self.selectedTab = 0;
    [self updatePillFrameAnimated:YES];
    self.tableView.hidden = NO;
    self.consoleContainer.hidden = YES;
}

- (void)consoleTapped {
    if (self.selectedTab == 1) return;
    self.selectedTab = 1;
    [self updatePillFrameAnimated:YES];
    self.tableView.hidden = YES;
    self.consoleContainer.hidden = NO;
    [self refreshConsoleDisplay];
}

#pragma mark - True Black OLED TableView

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [self.view addSubview:self.tableView];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.liquidGlassContainer.bottomAnchor constant:8],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor]
    ]];
}

#pragma mark - True Black OLED Console View

- (void)setupConsoleView {
    self.consoleContainer = [[UIView alloc] init];
    self.consoleContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleContainer.hidden = YES;
    self.consoleContainer.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.05 alpha:1.0];
    self.consoleContainer.layer.cornerRadius = 20;
    self.consoleContainer.layer.cornerCurve = kCACornerCurveContinuous;
    self.consoleContainer.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    self.consoleContainer.layer.borderWidth = 1.0;
    self.consoleContainer.layer.masksToBounds = YES;
    [self.view addSubview:self.consoleContainer];
    
    // Top Bar inside console with Clear Button
    UIView *topBar = [[UIView alloc] init];
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    topBar.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0];
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
    self.consoleTextView.textColor = [UIColor colorWithRed:0.35 green:0.90 blue:0.65 alpha:1.0];
    self.consoleTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.consoleTextView.editable = NO;
    self.consoleTextView.textContainerInset = UIEdgeInsetsMake(14, 14, 14, 14);
    [self.consoleContainer addSubview:self.consoleTextView];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.consoleContainer.topAnchor constraintEqualToAnchor:self.liquidGlassContainer.bottomAnchor constant:12],
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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MHAAppleCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"MHAAppleCell"];
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
