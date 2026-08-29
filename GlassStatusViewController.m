#import "GlassStatusViewController.h"
#import <sys/utsname.h>

@interface GlassStatusViewController ()

@property (nonatomic, strong) UIVisualEffectView *headerGlassCard;
@property (nonatomic, strong) UIVisualEffectView *consoleGlassCard;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusBadgeLabel;
@property (nonatomic, strong) UILabel *deviceMetaLabel;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIView *statusOrb;
@property (nonatomic, strong) NSMutableArray<NSString *> *logsArray;

@end

@implementation GlassStatusViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.logsArray = [NSMutableArray array];
    
    [self setupBackdrop];
    [self setupHeaderGlassCard];
    [self setupConsoleGlassCard];
    
    [MHAServer sharedServer].delegate = self;
    
    NSError *error = nil;
    if (![[MHAServer sharedServer] startOnPort:8080 error:&error]) {
        [self serverDidLogMessage:[NSString stringWithFormat:@"Failed to bind server: %@", error.localizedDescription] isError:YES];
    } else {
        [self serverDidLogMessage:@"MobileHouseArrest Liquid Glass Environment Initialized." isError:NO];
        [self serverDidLogMessage:@"Listening for USB bridge on localhost:8080." isError:NO];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - Liquid Glass Layout & Styling

- (void)setupBackdrop {
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.04 blue:0.06 alpha:1.0];
    
    // Ambient specular background glow
    CAGradientLayer *glow = [CAGradientLayer layer];
    glow.frame = [UIScreen mainScreen].bounds;
    glow.colors = @[
        (id)[UIColor colorWithRed:0.10 green:0.18 blue:0.28 alpha:0.5].CGColor,
        (id)[UIColor colorWithRed:0.04 green:0.04 blue:0.07 alpha:0.9].CGColor,
        (id)[UIColor colorWithRed:0.02 green:0.02 blue:0.03 alpha:1.0].CGColor
    ];
    glow.locations = @[@0.0, @0.45, @1.0];
    [self.view.layer insertSublayer:glow atIndex:0];
}

- (void)setupHeaderGlassCard {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.headerGlassCard = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.headerGlassCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.headerGlassCard.layer.cornerRadius = 24;
    self.headerGlassCard.layer.masksToBounds = YES;
    self.headerGlassCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.14].CGColor;
    self.headerGlassCard.layer.borderWidth = 1.0;
    [self.view addSubview:self.headerGlassCard];
    
    // Status orb (active glowing dot)
    self.statusOrb = [[UIView alloc] init];
    self.statusOrb.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusOrb.backgroundColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.55 alpha:1.0];
    self.statusOrb.layer.cornerRadius = 5;
    self.statusOrb.layer.shadowColor = [UIColor colorWithRed:0.25 green:0.90 blue:0.55 alpha:0.8].CGColor;
    self.statusOrb.layer.shadowRadius = 8;
    self.statusOrb.layer.shadowOpacity = 1.0;
    [self.headerGlassCard.contentView addSubview:self.statusOrb];
    
    // Title
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.text = @"MobileHouseArrest Bridge";
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightBold];
    [self.headerGlassCard.contentView addSubview:self.titleLabel];
    
    // Status Badge
    self.statusBadgeLabel = [[UILabel alloc] init];
    self.statusBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusBadgeLabel.text = @"Daemon Online  •  Port 8080";
    self.statusBadgeLabel.textColor = [UIColor colorWithRed:0.35 green:0.85 blue:0.55 alpha:1.0];
    self.statusBadgeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [self.headerGlassCard.contentView addSubview:self.statusBadgeLabel];
    
    // Device info
    struct utsname u;
    uname(&u);
    NSString *model = [NSString stringWithCString:u.machine encoding:NSUTF8StringEncoding];
    NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
    
    self.deviceMetaLabel = [[UILabel alloc] init];
    self.deviceMetaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.deviceMetaLabel.text = [NSString stringWithFormat:@"%@  •  iOS %ld.%ld.%ld  •  PID %d",
                                model, (long)os.majorVersion, (long)os.minorVersion, (long)os.patchVersion,
                                [[NSProcessInfo processInfo] processIdentifier]];
    self.deviceMetaLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
    self.deviceMetaLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [self.headerGlassCard.contentView addSubview:self.deviceMetaLabel];
    
    // AutoLayout
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.headerGlassCard.topAnchor constraintEqualToAnchor:guide.topAnchor constant:12],
        [self.headerGlassCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.headerGlassCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.headerGlassCard.heightAnchor constraintEqualToConstant:106],
        
        [self.statusOrb.leadingAnchor constraintEqualToAnchor:self.headerGlassCard.contentView.leadingAnchor constant:18],
        [self.statusOrb.topAnchor constraintEqualToAnchor:self.headerGlassCard.contentView.topAnchor constant:22],
        [self.statusOrb.widthAnchor constraintEqualToConstant:10],
        [self.statusOrb.heightAnchor constraintEqualToConstant:10],
        
        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.statusOrb.trailingAnchor constant:10],
        [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.statusOrb.centerYAnchor],
        [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.headerGlassCard.contentView.trailingAnchor constant:-16],
        
        [self.statusBadgeLabel.leadingAnchor constraintEqualToAnchor:self.statusOrb.leadingAnchor],
        [self.statusBadgeLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:8],
        
        [self.deviceMetaLabel.leadingAnchor constraintEqualToAnchor:self.statusOrb.leadingAnchor],
        [self.deviceMetaLabel.topAnchor constraintEqualToAnchor:self.statusBadgeLabel.bottomAnchor constant:6]
    ]];
    
    // Pulse animation on status orb
    CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
    pulse.duration = 1.2;
    pulse.fromValue = @1.0;
    pulse.toValue = @0.4;
    pulse.autoreverses = YES;
    pulse.repeatCount = HUGE_VALF;
    [self.statusOrb.layer addAnimation:pulse forKey:@"pulse"];
}

- (void)setupConsoleGlassCard {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.consoleGlassCard = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.consoleGlassCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.consoleGlassCard.layer.cornerRadius = 24;
    self.consoleGlassCard.layer.masksToBounds = YES;
    self.consoleGlassCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    self.consoleGlassCard.layer.borderWidth = 1.0;
    [self.view addSubview:self.consoleGlassCard];
    
    // Header Bar Inside Console
    UILabel *headerTitle = [[UILabel alloc] init];
    headerTitle.translatesAutoresizingMaskIntoConstraints = NO;
    headerTitle.text = @"CONSOLE ACTIVITY";
    headerTitle.textColor = [UIColor colorWithWhite:0.50 alpha:1.0];
    headerTitle.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [self.consoleGlassCard.contentView addSubview:headerTitle];
    
    // Clear Button (Glass Style)
    UIButton *clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    clearBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [clearBtn setTitle:@"Clear" forState:UIControlStateNormal];
    [clearBtn setTitleColor:[UIColor colorWithWhite:0.75 alpha:1.0] forState:UIControlStateNormal];
    clearBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [clearBtn addTarget:self action:@selector(clearLogs) forControlEvents:UIControlEventTouchUpInside];
    [self.consoleGlassCard.contentView addSubview:clearBtn];
    
    // Log TextView
    self.logTextView = [[UITextView alloc] init];
    self.logTextView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logTextView.backgroundColor = [UIColor clearColor];
    self.logTextView.textColor = [UIColor colorWithRed:0.35 green:0.88 blue:0.65 alpha:1.0];
    self.logTextView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logTextView.editable = NO;
    self.logTextView.showsVerticalScrollIndicator = YES;
    [self.consoleGlassCard.contentView addSubview:self.logTextView];
    
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.consoleGlassCard.topAnchor constraintEqualToAnchor:self.headerGlassCard.bottomAnchor constant:14],
        [self.consoleGlassCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.consoleGlassCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.consoleGlassCard.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-14],
        
        [headerTitle.leadingAnchor constraintEqualToAnchor:self.consoleGlassCard.contentView.leadingAnchor constant:18],
        [headerTitle.topAnchor constraintEqualToAnchor:self.consoleGlassCard.contentView.topAnchor constant:14],
        
        [clearBtn.trailingAnchor constraintEqualToAnchor:self.consoleGlassCard.contentView.trailingAnchor constant:-18],
        [clearBtn.centerYAnchor constraintEqualToAnchor:headerTitle.centerYAnchor],
        
        [self.logTextView.topAnchor constraintEqualToAnchor:headerTitle.bottomAnchor constant:10],
        [self.logTextView.leadingAnchor constraintEqualToAnchor:self.consoleGlassCard.contentView.leadingAnchor constant:12],
        [self.logTextView.trailingAnchor constraintEqualToAnchor:self.consoleGlassCard.contentView.trailingAnchor constant:-12],
        [self.logTextView.bottomAnchor constraintEqualToAnchor:self.consoleGlassCard.contentView.bottomAnchor constant:-12]
    ]];
}

#pragma mark - MHAServerDelegate

- (void)serverDidLogMessage:(NSString *)message isError:(BOOL)isError {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"HH:mm:ss"];
    NSString *ts = [df stringFromDate:[NSDate date]];
    
    NSString *prefix = isError ? @"[!]" : @"[+]";
    NSString *formatted = [NSString stringWithFormat:@"[%@] %@ %@", ts, prefix, message];
    
    [self.logsArray addObject:formatted];
    if (self.logsArray.count > 250) {
        [self.logsArray removeObjectAtIndex:0];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.logTextView.text = [self.logsArray componentsJoinedByString:@"\n"];
        if (self.logTextView.text.length > 0) {
            NSRange bottom = NSMakeRange(self.logTextView.text.length - 1, 1);
            [self.logTextView scrollRangeToVisible:bottom];
        }
    });
}

- (void)serverClientCountDidChange:(NSUInteger)count {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusBadgeLabel.text = [NSString stringWithFormat:@"Daemon Online  •  Clients: %lu", (unsigned long)count];
    });
}

- (void)clearLogs {
    [self.logsArray removeAllObjects];
    self.logTextView.text = @"";
}

@end
