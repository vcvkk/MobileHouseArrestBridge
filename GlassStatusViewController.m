#import "GlassStatusViewController.h"
#import <sys/utsname.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

/*
 Telegram-iOS Architecture (LiquidLensView.swift):
 
 1. RestingBackgroundView = UIVisualEffectView(.light) with hidden VisualEffectSubview
    + CAFilter colorMatrix on sublayer[0]. This creates a tinted translucent capsule.
    Alpha = isLifted ? 0.0 : 1.0
 
 2. _UILiquidLensView (iOS 26+):
    - initWithRestingBackground: UIView()
    - setLiftedContainerView: containerView
    - setLiftedContentView: liftedContainerView (contains restingBackgroundView)
    - setOverridePunchoutView: contentView (tab labels)
    - setLiftedContentMode: 1
    - setStyle: 1
    - setWarpsContentBelow: YES
    - restingBackgroundColor: (0,0,0, 0.1)
    - setLifted:animated:alongsideAnimations:completion: for transitions
 
 3. The "pill" IS the lens itself — its bounds expand by liftedInset (+6pt) when lifted,
    and contract by inset when resting. Center tracks the selected tab position.
 
 4. HorizontalTabsComponent passes isLifted=true only during tap transitions
    (temporaryLiftTimer 0.3s). During scroll, isLifted stays false on iOS 26.
*/

@interface GlassStatusViewController () <UIScrollViewDelegate>

// Telegram-iOS LiquidLensView hierarchy
@property (nonatomic, strong) UIView *titleRootView;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIVisualEffectView *restingBackgroundView;
@property (nonatomic, strong) UIView *liftedContainerView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIView *lensView; // _UILiquidLensView

// Tab buttons (inside contentView)
@property (nonatomic, strong) UIButton *dashboardTabBtn;
@property (nonatomic, strong) UIButton *consoleTabBtn;
@property (nonatomic, strong) UILabel *consoleUnreadBadge;
@property (nonatomic, strong) UIView *liveStatusDot;

// isLifted state (Telegram: temporaryLiftTimer)
@property (nonatomic, assign) BOOL isLifted;
@property (nonatomic, strong) NSTimer *liftTimer;
@property (nonatomic, assign) CGRect currentLensBaseFrame;

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

static const CGFloat kTitleWidth = 240.0;
static const CGFloat kTitleHeight = 36.0;
static const CGFloat kInset = 3.0;        // Telegram: 3pt padding
static const CGFloat kLiftedInset = 6.0;   // Telegram: 6pt expansion when lifted
static const CGFloat kInnerHeight = 30.0;  // kTitleHeight - 2*kInset
static const CGFloat kInnerWidth = 234.0;  // kTitleWidth - 2*kInset
static const CGFloat kTabWidth = 117.0;    // kInnerWidth / 2

@implementation GlassStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    self.logHistory = [NSMutableArray array];
    self.isLifted = NO;
    
    [self loadSystemInfo];
    [self setupTelegramLiquidLensNavigation];
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

#pragma mark - Telegram RestingBackgroundView (UIVisualEffectView + CAFilter colorMatrix)

- (UIVisualEffectView *)createRestingBackgroundView {
    UIVisualEffectView *view = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]];
    
    // Telegram: hide VisualEffectSubview children
    for (UIView *sub in view.subviews) {
        NSString *desc = NSStringFromClass([sub class]);
        if ([desc containsString:@"VisualEffectSubview"]) {
            sub.hidden = YES;
        }
    }
    view.clipsToBounds = YES;
    
    // Apply Telegram dark colorMatrix CAFilter on sublayer[0]
    if (view.layer.sublayers.count > 0) {
        CALayer *sublayer = view.layer.sublayers[0];
        sublayer.backgroundColor = nil;
        sublayer.opaque = NO;
        
        Class caFilterClass = NSClassFromString(@"CAFilter");
        if (caFilterClass) {
            id filter = ((id (*)(id, SEL, NSString *))objc_msgSend)(caFilterClass, sel_registerName("filterWithName:"), @"colorMatrix");
            if (filter) {
                // Telegram dark mode colorMatrix
                float matrix[20] = {
                    1.082f, -0.113f, -0.011f, 0.0f, 0.135f,
                    -0.034f, 1.003f, -0.011f, 0.0f, 0.135f,
                    -0.034f, -0.113f, 1.105f, 0.0f, 0.135f,
                    0.0f, 0.0f, 0.0f, 1.0f, 0.0f
                };
                NSValue *val = [NSValue valueWithBytes:matrix objCType:"{CAColorMatrix=ffffffffffffffffffff}"];
                [filter setValue:val forKey:@"inputColorMatrix"];
                sublayer.filters = @[filter];
                [sublayer setValue:@(1.0) forKey:@"scale"];
            }
        }
    }
    return view;
}

#pragma mark - Telegram-iOS LiquidLensView Setup

- (void)setupTelegramLiquidLensNavigation {
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
    
    // === Root Title View ===
    self.titleRootView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kTitleWidth, kTitleHeight)];
    self.titleRootView.userInteractionEnabled = YES;
    
    // === Container View (Telegram: containerView, size = innerSize) ===
    self.containerView = [[UIView alloc] initWithFrame:CGRectMake(kInset, 0, kInnerWidth, kInnerHeight)];
    self.containerView.userInteractionEnabled = NO;
    [self.titleRootView addSubview:self.containerView];
    
    // === LiftedContainerView (Telegram: holds restingBackgroundView, clipped to capsule) ===
    self.liftedContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kInnerWidth, kInnerHeight)];
    self.liftedContainerView.clipsToBounds = YES;
    self.liftedContainerView.layer.cornerRadius = kInnerHeight * 0.5;
    self.liftedContainerView.layer.cornerCurve = kCACornerCurveContinuous;
    
    // === RestingBackgroundView (Telegram: UIVisualEffectView + CAFilter colorMatrix) ===
    self.restingBackgroundView = [self createRestingBackgroundView];
    self.restingBackgroundView.frame = CGRectMake(0, 0, kInnerWidth, kInnerHeight);
    self.restingBackgroundView.layer.cornerRadius = kInnerHeight * 0.5;
    self.restingBackgroundView.layer.cornerCurve = kCACornerCurveContinuous;
    [self.liftedContainerView addSubview:self.restingBackgroundView];
    
    // === ContentView (Telegram: tab buttons overlay, gets punchout mask) ===
    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kInnerWidth, kInnerHeight)];
    self.contentView.userInteractionEnabled = YES;
    
    // === _UILiquidLensView (iOS 26+) ===
    Class liquidLensClass = NSClassFromString(@"_UILiquidLensView");
    if (liquidLensClass) {
        SEL allocSel = sel_registerName("alloc");
        SEL initSel = sel_registerName("initWithRestingBackground:");
        id allocObj = ((id (*)(id, SEL))objc_msgSend)(liquidLensClass, allocSel);
        UIView *restingBg = [[UIView alloc] init];
        self.lensView = ((id (*)(id, SEL, id))objc_msgSend)(allocObj, initSel, restingBg);
    }
    
    if (self.lensView) {
        self.lensView.layer.zPosition = 10.0;
        
        // Telegram view hierarchy: containerView → [liftedContainerView, lensView, contentView]
        [self.containerView addSubview:self.liftedContainerView];
        [self.containerView addSubview:self.lensView];
        [self.containerView addSubview:self.contentView];
        
        // Bind _UILiquidLensView selectors exactly as Telegram does
        SEL setLiftedContainer = sel_registerName("setLiftedContainerView:");
        SEL setLiftedContent = sel_registerName("setLiftedContentView:");
        SEL setOverridePunchout = sel_registerName("setOverridePunchoutView:");
        
        if ([self.lensView respondsToSelector:setLiftedContainer])
            ((void (*)(id, SEL, id))objc_msgSend)(self.lensView, setLiftedContainer, self.containerView);
        if ([self.lensView respondsToSelector:setLiftedContent])
            ((void (*)(id, SEL, id))objc_msgSend)(self.lensView, setLiftedContent, self.liftedContainerView);
        if ([self.lensView respondsToSelector:setOverridePunchout])
            ((void (*)(id, SEL, id))objc_msgSend)(self.lensView, setOverridePunchout, self.contentView);
        
        // setLiftedContentMode: 1
        SEL setLiftedModeSel = sel_registerName("setLiftedContentMode:");
        if ([self.lensView respondsToSelector:setLiftedModeSel])
            ((void (*)(id, SEL, int32_t))objc_msgSend)(self.lensView, setLiftedModeSel, 1);
        
        // setStyle: 1
        SEL setStyleSel = sel_registerName("setStyle:");
        if ([self.lensView respondsToSelector:setStyleSel])
            ((void (*)(id, SEL, int32_t))objc_msgSend)(self.lensView, setStyleSel, 1);
        
        // setWarpsContentBelow: YES
        SEL setWarpsSel = sel_registerName("setWarpsContentBelow:");
        if ([self.lensView respondsToSelector:setWarpsSel])
            ((void (*)(id, SEL, BOOL))objc_msgSend)(self.lensView, setWarpsSel, YES);
        
        // restingBackgroundColor
        @try {
            [self.lensView setValue:[UIColor colorWithWhite:0.0 alpha:0.1] forKey:@"restingBackgroundColor"];
        } @catch (NSException *e) {}
        
        // Initial lens position (Dashboard selected)
        self.currentLensBaseFrame = CGRectMake(0, 0, kTabWidth, kInnerHeight);
        CGFloat inset = -0.0; // Telegram: inset=0 for .noContainer
        self.lensView.bounds = CGRectMake(0, 0, kTabWidth + inset * 2, kInnerHeight + inset * 2);
        self.lensView.center = CGPointMake(CGRectGetMidX(self.currentLensBaseFrame), CGRectGetMidY(self.currentLensBaseFrame));
    } else {
        // Fallback: no _UILiquidLensView
        [self.containerView addSubview:self.liftedContainerView];
        [self.containerView addSubview:self.contentView];
    }
    
    // === Tab Buttons (inside contentView — Telegram's punchout layer) ===
    self.dashboardTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dashboardTabBtn.frame = CGRectMake(0, 0, kTabWidth, kInnerHeight);
    [self.dashboardTabBtn setTitle:@"Dashboard" forState:UIControlStateNormal];
    [self.dashboardTabBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.dashboardTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.dashboardTabBtn addTarget:self action:@selector(selectDashboard) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.dashboardTabBtn];
    
    self.liveStatusDot = [[UIView alloc] initWithFrame:CGRectMake(12, 12, 6, 6)];
    self.liveStatusDot.backgroundColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.55 alpha:1.0];
    self.liveStatusDot.layer.cornerRadius = 3;
    self.liveStatusDot.userInteractionEnabled = NO;
    [self.dashboardTabBtn addSubview:self.liveStatusDot];
    
    self.consoleTabBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.consoleTabBtn.frame = CGRectMake(kTabWidth, 0, kTabWidth, kInnerHeight);
    [self.consoleTabBtn setTitle:@"Console" forState:UIControlStateNormal];
    [self.consoleTabBtn setTitleColor:[UIColor colorWithWhite:0.65 alpha:1.0] forState:UIControlStateNormal];
    self.consoleTabBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.consoleTabBtn addTarget:self action:@selector(selectConsole) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.consoleTabBtn];
    
    self.consoleUnreadBadge = [[UILabel alloc] initWithFrame:CGRectMake(87, 7, 18, 16)];
    self.consoleUnreadBadge.text = @"0";
    self.consoleUnreadBadge.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightBold];
    self.consoleUnreadBadge.textColor = [UIColor whiteColor];
    self.consoleUnreadBadge.textAlignment = NSTextAlignmentCenter;
    self.consoleUnreadBadge.backgroundColor = [UIColor colorWithRed:0.22 green:0.53 blue:0.95 alpha:0.90];
    self.consoleUnreadBadge.layer.cornerRadius = 8;
    self.consoleUnreadBadge.layer.masksToBounds = YES;
    self.consoleUnreadBadge.userInteractionEnabled = NO;
    [self.consoleTabBtn addSubview:self.consoleUnreadBadge];
    
    // The titleRootView must sit above contentView for touch routing
    [self.titleRootView addSubview:self.contentView];
    
    self.navigationItem.titleView = self.titleRootView;
}

#pragma mark - Telegram-iOS _UILiquidLensView Lift/Unlift

- (void)liftLensAnimated:(BOOL)animated {
    if (self.isLifted) return;
    self.isLifted = YES;
    
    if (!self.lensView) {
        // Fallback
        [UIView animateWithDuration:0.25 animations:^{
            self.restingBackgroundView.alpha = 0.0;
        }];
        return;
    }
    
    SEL sel = sel_registerName("setLifted:animated:alongsideAnimations:completion:");
    if ([self.lensView respondsToSelector:sel]) {
        void (^alongside)(void) = ^{
            CGFloat liftedInset = kLiftedInset;
            CGRect base = self.currentLensBaseFrame;
            self.lensView.bounds = CGRectMake(0, 0, base.size.width + liftedInset * 2, base.size.height + liftedInset * 2);
        };
        void (^completion)(void) = ^{};
        
        typedef void (*LiftMethod)(id, SEL, BOOL, BOOL, id, id);
        LiftMethod func = (LiftMethod)objc_msgSend;
        func(self.lensView, sel, YES, animated, [alongside copy], [completion copy]);
    }
    
    void (^fadeBlock)(void) = ^{ self.restingBackgroundView.alpha = 0.0; };
    if (animated) {
        [UIView animateWithDuration:0.25 animations:fadeBlock];
    } else {
        fadeBlock();
    }
}

- (void)unliftLensAnimated:(BOOL)animated {
    if (!self.isLifted) return;
    self.isLifted = NO;
    
    if (!self.lensView) {
        [UIView animateWithDuration:0.2 animations:^{
            self.restingBackgroundView.alpha = 1.0;
        }];
        return;
    }
    
    SEL sel = sel_registerName("setLifted:animated:alongsideAnimations:completion:");
    if ([self.lensView respondsToSelector:sel]) {
        void (^alongside)(void) = ^{
            CGRect base = self.currentLensBaseFrame;
            self.lensView.bounds = CGRectMake(0, 0, base.size.width, base.size.height);
        };
        void (^completion)(void) = ^{};
        
        typedef void (*LiftMethod)(id, SEL, BOOL, BOOL, id, id);
        LiftMethod func = (LiftMethod)objc_msgSend;
        func(self.lensView, sel, NO, animated, [alongside copy], [completion copy]);
    }
    
    void (^fadeBlock)(void) = ^{ self.restingBackgroundView.alpha = 1.0; };
    if (animated) {
        [UIView animateWithDuration:0.2 animations:fadeBlock];
    } else {
        fadeBlock();
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
    
    self.dashboardTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.dashboardTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.dashboardTableView.backgroundColor = [UIColor blackColor];
    self.dashboardTableView.dataSource = self;
    self.dashboardTableView.delegate = self;
    self.dashboardTableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    [self.pagingScrollView addSubview:self.dashboardTableView];
    
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

#pragma mark - Scroll Synchronization (Telegram: tabSwitchFraction interpolation)

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.pagingScrollView) return;
    CGFloat pageWidth = self.pagingScrollView.bounds.size.width;
    if (pageWidth <= 0) return;
    
    CGFloat progress = self.pagingScrollView.contentOffset.x / pageWidth;
    progress = fmax(0.0, fmin(1.0, progress));
    
    // Telegram: interpolate lens center between tab frames
    CGFloat lensX = progress * kTabWidth;
    self.currentLensBaseFrame = CGRectMake(lensX, 0, kTabWidth, kInnerHeight);
    
    if (self.lensView) {
        self.lensView.center = CGPointMake(lensX + kTabWidth * 0.5, kInnerHeight * 0.5);
    }
    
    // Update tab text styles
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

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.pagingScrollView) [self scheduleLiftEnd];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (scrollView == self.pagingScrollView) [self scheduleLiftEnd];
}

- (void)scheduleLiftEnd {
    [self.liftTimer invalidate];
    self.liftTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *t) {
        [self unliftLensAnimated:YES];
    }];
}

- (void)selectDashboard {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    [self liftLensAnimated:YES];
    [self.pagingScrollView setContentOffset:CGPointMake(0, 0) animated:YES];
}

- (void)selectConsole {
    UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    [self liftLensAnimated:YES];
    [self.pagingScrollView setContentOffset:CGPointMake(self.pagingScrollView.bounds.size.width, 0) animated:YES];
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
