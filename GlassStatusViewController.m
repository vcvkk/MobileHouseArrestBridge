#import "GlassStatusViewController.h"
#import <sys/utsname.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

@interface TelegramTitleBar : UIView
@end

@implementation TelegramTitleBar
- (CGSize)intrinsicContentSize {
    return CGSizeMake(236.0, 32.0);
}
@end

@interface GlassStatusViewController () <UIScrollViewDelegate>

// Telegram-iOS LiquidLens TitleView Architecture
@property (nonatomic, strong) TelegramTitleBar *telegramGlassTitleView;
@property (nonatomic, strong) UIVisualEffectView *glassBackdropView;
@property (nonatomic, strong) UIView *liquidLensView;
@property (nonatomic, strong) UIVisualEffectView *slidingPillGlassView;
@property (nonatomic, strong) CAGradientLayer *specularShineLayer;
@property (nonatomic, strong) UIButton *dashboardTabBtn;
@property (nonatomic, strong) UIButton *consoleTabBtn;
@property (nonatomic, strong) UILabel *consoleUnreadBadge;
@property (nonatomic, strong) UIView *liveStatusDot;

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

@implementation GlassStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // OLED True Black Canvas
    self.view.backgroundColor = [UIColor blackColor];
    self.logHistory = [NSMutableArray array];
    
    [self loadSystemInfo];
    [self setupTelegramLiquidLensNavigationBar];
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

#pragma mark - Telegram-iOS Liquid Glass Navigation TitleView

- (void)setupTelegramLiquidLensNavigationBar {
    if (!self.navigationController) return;
    
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:0.22 green:0.53 blue:0.95 alpha:1.0];
    
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [UIColor blackColor];
    appearance.shadowColor = [UIColor clearColor];
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.compactAppearance = appearance;
    
    // Right Action: Export Logs
    UIBarButtonItem *shareItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareLogs)];
    self.navigationItem.rightBarButtonItem = shareItem;
    
    // Telegram-iOS Liquid Lens Container (236 x 32)
    self.telegramGlassTitleView = [[TelegramTitleBar alloc] initWithFrame:CGRectMake(0, 0, 236, 32)];
    self.telegramGlassTitleView.userInteractionEnabled = YES;
    self.telegramGlassTitleView.clipsToBounds = NO;
    
    // 1. Telegram-iOS Resting Background with ColorMatrix CAFilter
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.glassBackdropView = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.glassBackdropView.frame = self.telegramGlassTitleView.bounds;
    self.glassBackdropView.layer.cornerRadius = 16;
    self.glassBackdropView.layer.cornerCurve = kCACornerCurveContinuous;
    self.glassBackdropView.layer.masksToBounds = YES;
    self.glassBackdropView.clipsToBounds = YES;
    self.glassBackdropView.userInteractionEnabled = NO;
    self.glassBackdropView.backgroundColor = [UIColor colorWithWhite:0.16 alpha:0.45];
    self.glassBackdropView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    self.glassBackdropView.layer.borderWidth = 0.5;
    [self.telegramGlassTitleView addSubview:self.glassBackdropView];
    
    // Apply Telegram's exact dark color matrix filter to backdrop layer
    if (self.glassBackdropView.layer.sublayers.count > 0) {
        CALayer *sublayer = self.glassBackdropView.layer.sublayers[0];
        Class caFilterClass = NSClassFromString(@"CAFilter");
        if (caFilterClass && [caFilterClass respondsToSelector:sel_registerName("filterWithName:")]) {
            id filter = ((id (*)(id, SEL, NSString *))objc_msgSend)(caFilterClass, sel_registerName("filterWithName:"), @"colorMatrix");
            if (filter) {
                float matrix[20] = {
                    1.082f, -0.113f, -0.011f, 0.0f, 0.135f,
                    -0.034f, 1.003f, -0.011f, 0.0f, 0.135f,
                    -0.034f, -0.113f, 1.105f, 0.0f, 0.135f,
                    0.0f, 0.0f, 0.0f, 1.0f, 0.0f
                };
                NSValue *val = [NSValue valueWithBytes:matrix objCType:"{CAColorMatrix=ffffffffffffffffffff}"];
                [filter setValue:val forKey:@"inputColorMatrix"];
                sublayer.filters = @[filter];
            }
        }
    }
    
    // 2. Telegram Sliding Frosted Glass Pill (UIVisualEffectView + Specular 45-deg Caustic Gradient)
    UIBlurEffect *pillBlur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    self.slidingPillGlassView = [[UIVisualEffectView alloc] initWithEffect:pillBlur];
    self.slidingPillGlassView.frame = CGRectMake(2, 2, 114, 28);
    self.slidingPillGlassView.layer.cornerRadius = 14;
    self.slidingPillGlassView.layer.cornerCurve = kCACornerCurveContinuous;
    self.slidingPillGlassView.layer.masksToBounds = YES;
    self.slidingPillGlassView.backgroundColor = [UIColor colorWithWhite:0.40 alpha:0.50];
    self.slidingPillGlassView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.40].CGColor;
    self.slidingPillGlassView.layer.borderWidth = 0.8;
    self.slidingPillGlassView.userInteractionEnabled = NO;
    
    // Specular Highlight Layer
    self.specularShineLayer = [CAGradientLayer layer];
    self.specularShineLayer.frame = CGRectMake(0, 0, 114, 28);
    self.specularShineLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:0.55].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.08].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.30].CGColor
    ];
    self.specularShineLayer.startPoint = CGPointMake(0.0, 0.0);
    self.specularShineLayer.endPoint = CGPointMake(1.0, 1.0);
    self.specularShineLayer.cornerRadius = 14;
    self.specularShineLayer.cornerCurve = kCACornerCurveContinuous;
    [self.slidingPillGlassView.contentView.layer addSublayer:self.specularShineLayer];
    
    [self.telegramGlassTitleView addSubview:self.slidingPillGlassView];
    
    // 3. Apple _UILiquidLensView on iOS 26+ (Telegram LiquidLensView exact binding)
    Class liquidLensClass = NSClassFromString(@"_UILiquidLensView");
    if (liquidLensClass) {
        id allocObj = [liquidLensClass alloc];
        SEL initSel = sel_registerName("initWithRestingBackground:");
        if ([allocObj respondsToSelector:initSel]) {
            self.liquidLensView = ((id (*)(id, SEL, id))objc_msgSend)(allocObj, initSel, [[UIView alloc] init]);
            if (self.liquidLensView) {
                self.liquidLensView.frame = CGRectMake(2, 2, 114, 28);
                self.liquidLensView.center = CGPointMake(59, 16);
                self.liquidLensView.userInteractionEnabled = NO;
                
                SEL setLiftedContainerSel = sel_registerName("setLiftedContainerView:");
                if ([self.liquidLensView respondsToSelector:setLiftedContainerSel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(self.liquidLensView, setLiftedContainerSel, self.telegramGlassTitleView);
                }
                SEL setLiftedContentSel = sel_registerName("setLiftedContentView:");
                if ([self.liquidLensView respondsToSelector:setLiftedContentSel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(self.liquidLensView, setLiftedContentSel, self.slidingPillGlassView);
                }
                SEL setOverridePunchSel = sel_registerName("setOverridePunchoutView:");
                if ([self.liquidLensView respondsToSelector:setOverridePunchSel]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(self.liquidLensView, setOverridePunchSel, self.glassBackdropView.contentView);
                }
                SEL setLiftedModeSel = sel_registerName("setLiftedContentMode:");
                if ([self.liquidLensView respondsToSelector:setLiftedModeSel]) {
                    ((void (*)(id, SEL, int32_t))objc_msgSend)(self.liquidLensView, setLiftedModeSel, 1);
                }
                SEL setStyleSel = sel_registerName("setStyle:");
                if ([self.liquidLensView respondsToSelector:setStyleSel]) {
                    ((void (*)(id, SEL, int32_t))objc_msgSend)(self.liquidLensView, setStyleSel, 1);
                }
                SEL setWarpsSel = sel_registerName("setWarpsContentBelow:");
                if ([self.liquidLensView respondsToSelector:setWarpsSel]) {
                    ((void (*)(id, SEL, BOOL))objc_msgSend)(self.liquidLensView, setWarpsSel, YES);
                }
                [self.liquidLensView setValue:[UIColor colorWithWhite:0.0 alpha:0.1] forKey:@"restingBackgroundColor"];
                [self.telegramGlassTitleView addSubview:self.liquidLensView];
            }
        }
    }
    
    // 4. Tab 1: Dashboard (Top-most interactive layer)
    self.dashboardTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dashboardTabBtn.frame = CGRectMake(0, 0, 118, 32);
    [self.dashboardTabBtn setTitle:@"Dashboard" forState:UIControlStateNormal];
    [self.dashboardTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.dashboardTabBtn addTarget:self action:@selector(selectDashboard) forControlEvents:UIControlEventTouchUpInside];
    [self.telegramGlassTitleView addSubview:self.dashboardTabBtn];
    
    // Status Dot inside Dashboard
    self.liveStatusDot = [[UIView alloc] initWithFrame:CGRectMake(12, 13, 6, 6)];
    self.liveStatusDot.backgroundColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.55 alpha:1.0];
    self.liveStatusDot.layer.cornerRadius = 3;
    self.liveStatusDot.userInteractionEnabled = NO;
    [self.dashboardTabBtn addSubview:self.liveStatusDot];
    
    // 5. Tab 2: Console (Top-most interactive layer)
    self.consoleTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.consoleTabBtn.frame = CGRectMake(118, 0, 118, 32);
    [self.consoleTabBtn setTitle:@"Console" forState:UIControlStateNormal];
    [self.consoleTabBtn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1.0] forState:UIControlStateNormal];
    self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.consoleTabBtn addTarget:self action:@selector(selectConsole) forControlEvents:UIControlEventTouchUpInside];
    [self.telegramGlassTitleView addSubview:self.consoleTabBtn];
    
    // Telegram-style Folder Badge Count
    self.consoleUnreadBadge = [[UILabel alloc] initWithFrame:CGRectMake(88, 8, 18, 16)];
    self.consoleUnreadBadge.text = @"0";
    self.consoleUnreadBadge.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    self.consoleUnreadBadge.textColor = [UIColor whiteColor];
    self.consoleUnreadBadge.textAlignment = NSTextAlignmentCenter;
    self.consoleUnreadBadge.backgroundColor = [UIColor colorWithRed:0.22 green:0.53 blue:0.95 alpha:0.90];
    self.consoleUnreadBadge.layer.cornerRadius = 8;
    self.consoleUnreadBadge.layer.masksToBounds = YES;
    self.consoleUnreadBadge.userInteractionEnabled = NO;
    [self.consoleTabBtn addSubview:self.consoleUnreadBadge];
    
    [self.telegramGlassTitleView bringSubviewToFront:self.dashboardTabBtn];
    [self.telegramGlassTitleView bringSubviewToFront:self.consoleTabBtn];
    
    self.navigationItem.titleView = self.telegramGlassTitleView;
}

#pragma mark - Telegram Fullscreen Pager

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
    
    // Page 1: Dashboard TableView
    self.dashboardTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.dashboardTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dashboardTableView.backgroundColor = [UIColor blackColor];
    self.dashboardTableView.dataSource = self;
    self.dashboardTableView.delegate = self;
    self.dashboardTableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [self.pagingScrollView addSubview:self.dashboardTableView];
    
    // Page 2: Console Log View (Full OLED Terminal)
    self.consoleView = [[UIView alloc] init];
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleView.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.05 alpha:1.0];
    self.consoleView.layer.cornerRadius = 18;
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
    
    // Autolayout for horizontal pages
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

#pragma mark - Telegram-iOS Scroll Synchronization & Dynamic Lens Refraction

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == self.pagingScrollView) {
        CGFloat pageWidth = self.pagingScrollView.bounds.size.width;
        if (pageWidth <= 0) return;
        
        CGFloat progress = self.pagingScrollView.contentOffset.x / pageWidth;
        progress = fmax(0.0, fmin(1.0, progress));
        
        CGFloat pillWidth = 114.0;
        CGFloat pillX = 2.0 + (progress * 118.0);
        self.slidingPillGlassView.frame = CGRectMake(pillX, 2.0, pillWidth, 28.0);
        
        if (self.liquidLensView) {
            self.liquidLensView.center = CGPointMake(pillX + (pillWidth / 2.0), 16.0);
        }
        
        if (progress < 0.5) {
            [self.dashboardTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
            [self.consoleTabBtn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1.0] forState:UIControlStateNormal];
            self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        } else {
            [self.dashboardTabBtn setTitleColor:[UIColor colorWithWhite:0.60 alpha:1.0] forState:UIControlStateNormal];
            self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
            [self.consoleTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        }
    }
}

- (void)selectDashboard {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    [self.pagingScrollView setContentOffset:CGPointMake(0, 0) animated:YES];
}

- (void)selectConsole {
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
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MHATelegramGlassCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"MHATelegramGlassCell"];
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
        self.consoleUnreadBadge.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.logHistory.count];
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
