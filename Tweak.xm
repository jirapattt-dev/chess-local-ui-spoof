#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

/* 3.16.0
 * Display-only spoof: replace current user's username labels with CHESScom.
 * Server still sees the real account. No protobuf.
 */

static BOOL gReady;
static NSUInteger gTries;
static const void *kSpoofedKey = &kSpoofedKey;

static NSString * const kSpoofName = @"CHESScom";
static NSString * const kSpoofFull = @"Chess.com Team";
static NSString * const kAvatarURL = @"https://images.chesscomfiles.com/uploads/v1/user/33.862d5ff1.200x200o.0fc116e99993.png";

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

static void ChessSpoofLabel(UILabel *lab) {
    if (!lab || !ChessNameIsMe(lab.text)) return;
    if (objc_getAssociatedObject(lab, kSpoofedKey)) return;
    NSString *orig = lab.text;
    if (orig.length > 16 || [orig containsString:@"..."]) {
        lab.text = [kSpoofName stringByAppendingString:@"…"];
    } else {
        lab.text = kSpoofName;
    }
    objc_setAssociatedObject(lab, kSpoofedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ChessWalkAndSpoof(UIView *root) {
    if (!root || !ChessMe().length) return;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSInteger n = 0;
    while (q.count && n < 600) {
        UIView *v = q.firstObject; [q removeObjectAtIndex:0]; n++;
        if ([v isKindOfClass:UILabel.class]) {
            UILabel *lab = (UILabel *)v;
            if (ChessNameIsMe(lab.text) && lab.font.pointSize >= 10 && lab.font.pointSize <= 22)
                ChessSpoofLabel(lab);
        }
        for (UIView *s in v.subviews) [q addObject:s];
    }
}

static void ChessForceOnAllWindows(void) {
    @try {
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
                if (![sc isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *w in ((UIWindowScene *)sc).windows) if (!w.hidden) ChessWalkAndSpoof(w);
            }
        }
        for (UIWindow *w in UIApplication.sharedApplication.windows) if (!w.hidden) ChessWalkAndSpoof(w);
    } @catch (__unused NSException *e) {}
}

static void Try(void);
static void Retry(void) { if (gTries++ >= 60) return; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ Try(); }); }
static void Try(void) {
    if (gReady) return;
    if (!ChessMe().length) { Retry(); return; }
    gReady = YES;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (uint64_t)(0.5 * NSEC_PER_SEC)), (uint64_t)(1.0 * NSEC_PER_SEC), (uint64_t)(0.2 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{ ChessForceOnAllWindows(); });
    dispatch_resume(timer);
}
__attribute__((constructor)) static void ctor(void) { dispatch_async(dispatch_get_main_queue(), ^{ Try(); }); }
