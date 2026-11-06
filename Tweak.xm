#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

/* 3.15.5
 * Inject a staff pawn UIImageView next to the current user's username label.
 * Works even if no flair is selected.
 */

static BOOL gReady;
static NSUInteger gTries;
static const void *kInjectedKey = &kInjectedKey;

static NSString * const kStaffCode = @"Flair/pawn_traditional";

static id ChessSafe(id o, NSString *k) { if (!o || !k.length) return nil; @try { return [o valueForKey:k]; } @catch (__unused NSException *e) { return nil; } }
static id ChessUser(void) { Class c = NSClassFromString(@"CHCurrentUser"); if (!c) return nil; return ChessSafe(c, @"currentUser") ?: ChessSafe(c, @"sharedUser") ?: ChessSafe(c, @"sharedInstance"); }
static NSString *ChessMe(void) { id u = ChessUser(); for (NSString *k in @[ @"userName", @"username", @"user_name" ]) { id v = ChessSafe(u, k); if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return [(NSString *)v copy]; } return nil; }

static BOOL ChessNameIsMe(NSString *n) {
    NSString *me = ChessMe();
    if (!me.length || !n.length) return NO;
    if ([me caseInsensitiveCompare:n] == NSOrderedSame) return YES;
    NSString *t = [n stringByReplacingOccurrencesOfString:@"…" withString:@""];
    t = [t stringByReplacingOccurrencesOfString:@"..." withString:@""];
    t = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length < 4) return NO;
    return [me.lowercaseString hasPrefix:t.lowercaseString];
}

static UIImage *ChessStaffImage(void) {
    UIImage *img = [UIImage imageNamed:kStaffCode];
    if (!img) img = [UIImage imageNamed:@"pawn_traditional"];
    if (!img) img = [UIImage imageNamed:@"Flair/pawn_blue"];
    return img;
}

static void ChessInjectNextToLabel(UILabel *lab) {
    if (!lab || !ChessNameIsMe(lab.text)) return;
    if (objc_getAssociatedObject(lab, kInjectedKey)) return;
    UIImage *img = ChessStaffImage();
    if (!img) return;

    UIView *parent = lab.superview;
    if (!parent) return;

    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.tag = 0xF1A1;
    [parent addSubview:iv];

    [NSLayoutConstraint activateConstraints:@[
        [iv.widthAnchor constraintEqualToConstant:16],
        [iv.heightAnchor constraintEqualToConstant:16],
        [iv.centerYAnchor constraintEqualToAnchor:lab.centerYAnchor],
        [iv.leadingAnchor constraintEqualToAnchor:lab.trailingAnchor constant:4]
    ]];

    objc_setAssociatedObject(lab, kInjectedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ChessWalkAndInject(UIView *root) {
    if (!root || !ChessMe().length) return;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSInteger n = 0;
    while (q.count && n < 500) {
        UIView *v = q.firstObject; [q removeObjectAtIndex:0]; n++;
        if ([v isKindOfClass:UILabel.class]) {
            UILabel *lab = (UILabel *)v;
            if (ChessNameIsMe(lab.text) && lab.font.pointSize >= 10 && lab.font.pointSize <= 20)
                ChessInjectNextToLabel(lab);
        }
        for (UIView *s in v.subviews) [q addObject:s];
    }
}

static void ChessForceOnAllWindows(void) {
    @try {
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
                if (![sc isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *w in ((UIWindowScene *)sc).windows) if (!w.hidden) ChessWalkAndInject(w);
            }
        }
        for (UIWindow *w in UIApplication.sharedApplication.windows) if (!w.hidden) ChessWalkAndInject(w);
    } @catch (__unused NSException *e) {}
}

static void Try(void);
static void Retry(void) { if (gTries++ >= 60) return; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ Try(); }); }
static void Try(void) {
    if (gReady) return;
    if (!ChessMe().length) { Retry(); return; }
    gReady = YES;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (uint64_t)(0.5 * NSEC_PER_SEC)), (uint64_t)(1.5 * NSEC_PER_SEC), (uint64_t)(0.2 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{ ChessForceOnAllWindows(); });
    dispatch_resume(timer);
}
__attribute__((constructor)) static void ctor(void) { dispatch_async(dispatch_get_main_queue(), ^{ Try(); }); }
