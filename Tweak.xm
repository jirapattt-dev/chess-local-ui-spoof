#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

/* 3.15.6
 * Draw a green pawn and replace the current flair image next to the username.
 * Does not depend on asset name.
 */

static BOOL gReady;
static NSUInteger gTries;
static const void *kReplacedKey = &kReplacedKey;

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

static UIImage *ChessGreenPawn(void) {
    static UIImage *img;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGSize sz = CGSizeMake(32, 32);
        UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        [[UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:1] setFill];
        // head
        CGContextFillEllipseInRect(ctx, CGRectMake(10, 4, 12, 12));
        // neck
        CGContextFillRect(ctx, CGRectMake(14, 14, 4, 4));
        // body
        CGContextFillEllipseInRect(ctx, CGRectMake(8, 16, 16, 10));
        // base
        CGContextFillRect(ctx, CGRectMake(6, 24, 20, 4));
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

static void ChessReplaceFlairNearLabel(UILabel *lab) {
    if (!lab || !ChessNameIsMe(lab.text)) return;
    UIView *parent = lab.superview;
    if (!parent) return;
    UIImage *pawn = ChessGreenPawn();
    if (!pawn) return;

    for (UIView *s in parent.subviews) {
        if (s == lab) continue;
        if (![s isKindOfClass:UIImageView.class]) continue;
        UIImageView *iv = (UIImageView *)s;
        CGFloat w = iv.bounds.size.width;
        CGFloat h = iv.bounds.size.height;
        if (w < 8 || w > 40 || h < 8 || h > 40) continue;
        // roughly to the right of the label
        if (iv.frame.origin.x < lab.frame.origin.x) continue;
        if (objc_getAssociatedObject(iv, kReplacedKey)) continue;
        iv.image = pawn;
        iv.hidden = NO;
        iv.alpha = 1;
        objc_setAssociatedObject(iv, kReplacedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void ChessWalkAndReplace(UIView *root) {
    if (!root || !ChessMe().length) return;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSInteger n = 0;
    while (q.count && n < 600) {
        UIView *v = q.firstObject; [q removeObjectAtIndex:0]; n++;
        if ([v isKindOfClass:UILabel.class]) {
            UILabel *lab = (UILabel *)v;
            if (ChessNameIsMe(lab.text) && lab.font.pointSize >= 10 && lab.font.pointSize <= 22)
                ChessReplaceFlairNearLabel(lab);
        }
        for (UIView *s in v.subviews) [q addObject:s];
    }
}

static void ChessForceOnAllWindows(void) {
    @try {
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
                if (![sc isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *w in ((UIWindowScene *)sc).windows) if (!w.hidden) ChessWalkAndReplace(w);
            }
        }
        for (UIWindow *w in UIApplication.sharedApplication.windows) if (!w.hidden) ChessWalkAndReplace(w);
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
