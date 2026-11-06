#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

/* 3.15.4
 * Walk views and set flairImageView image to Flair/pawn_traditional.
 * Also force flair code/URL as before.
 */

static IMP gSetFlairURL, gSetFlairCode, gSetFlairForPlayer, gSetupFlairWith;
static BOOL gReady;
static NSUInteger gTries;

static NSString * const kStaffCode = @"Flair/pawn_traditional";
static NSString * const kStaffFlair = @"https://images.chesscomfiles.com/chess-flair/staff_mod_account/pawn_traditional.svg";

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
static NSString *ChessPlayerName(id p) { if (!p) return nil; for (NSString *k in @[ @"username", @"userName", @"user_name", @"name", @"authorName", @"senderName" ]) { id v = ChessSafe(p, k); if ([v isKindOfClass:NSString.class] && [(NSString *)v length]) return v; } return nil; }
static BOOL ChessIsOwnPlayer(id player) { if (!player) return NO; for (NSString *k in @[ @"isCurrentUser", @"isCurrentUserPlayer", @"isSelf", @"isMe" ]) { id v = ChessSafe(player, k); if ([v respondsToSelector:@selector(boolValue)] && [v boolValue]) return YES; } return ChessNameIsMe(ChessPlayerName(player)); }

static UIImage *ChessStaffImage(void) {
    UIImage *img = [UIImage imageNamed:kStaffCode];
    if (!img) img = [UIImage imageNamed:@"pawn_traditional"];
    return img;
}

static void ChessForceImageOnView(UIView *v) {
    if (!v) return;
    UIImage *img = ChessStaffImage();
    if (!img) return;
    @try {
        id iv = ChessSafe(v, @"flairImageView");
        if ([iv isKindOfClass:UIImageView.class]) {
            ((UIImageView *)iv).image = img;
            ((UIImageView *)iv).hidden = NO;
            ((UIImageView *)iv).alpha = 1;
        }
        if ([v isKindOfClass:UIImageView.class]) {
            NSString *cn = NSStringFromClass(v.class);
            if ([cn containsString:@"Flair"] || [cn containsString:@"flair"]) {
                ((UIImageView *)v).image = img;
                ((UIImageView *)v).hidden = NO;
            }
        }
    } @catch (__unused NSException *e) {}
}

static void ChessForceFlairOn(id obj) {
    if (!obj) return;
    @try {
        if ([obj respondsToSelector:@selector(setFlairCode:)])
            ((void (*)(id, SEL, id))objc_msgSend)(obj, @selector(setFlairCode:), kStaffCode);
        if ([obj respondsToSelector:@selector(setFlairURL:)])
            ((void (*)(id, SEL, id))objc_msgSend)(obj, @selector(setFlairURL:), [NSURL URLWithString:kStaffFlair]);
        if ([obj isKindOfClass:UIView.class]) ChessForceImageOnView((UIView *)obj);
    } @catch (__unused NSException *e) {}
}

static void ChessWalkAndForce(UIView *root) {
    if (!root || !ChessMe().length) return;
    NSMutableArray *q = [NSMutableArray arrayWithObject:root];
    NSInteger n = 0;
    while (q.count && n < 400) {
        UIView *v = q.firstObject; [q removeObjectAtIndex:0]; n++;
        NSString *cn = NSStringFromClass(v.class);
        if ([cn containsString:@"Flair"] || [cn containsString:@"flair"] || [cn containsString:@"PlayerInfo"] || [cn containsString:@"UserRow"] || [cn containsString:@"Standing"]) {
            ChessForceImageOnView(v);
        }
        id iv = ChessSafe(v, @"flairImageView");
        if ([iv isKindOfClass:UIImageView.class]) ChessForceImageOnView(v);
        for (UIView *s in v.subviews) [q addObject:s];
    }
}

static void ChessForceOnAllWindows(void) {
    @try {
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
                if (![sc isKindOfClass:UIWindowScene.class]) continue;
                for (UIWindow *w in ((UIWindowScene *)sc).windows) if (!w.hidden) ChessWalkAndForce(w);
            }
        }
        for (UIWindow *w in UIApplication.sharedApplication.windows) if (!w.hidden) ChessWalkAndForce(w);
        ChessForceFlairOn(ChessUser());
    } @catch (__unused NSException *e) {}
}

static void HookSetFlairCode(id self, SEL _cmd, id code) {
    id use = (ChessIsOwnPlayer(self) || ChessNameIsMe(ChessPlayerName(self))) ? kStaffCode : code;
    if (gSetFlairCode) ((void (*)(id, SEL, id))gSetFlairCode)(self, _cmd, use);
    if ([self isKindOfClass:UIView.class]) ChessForceImageOnView((UIView *)self);
}
static void HookSetFlairURL(id self, SEL _cmd, id url) {
    id use = (ChessIsOwnPlayer(self) || ChessNameIsMe(ChessPlayerName(self))) ? [NSURL URLWithString:kStaffFlair] : url;
    if (gSetFlairURL) ((void (*)(id, SEL, id))gSetFlairURL)(self, _cmd, use);
    if ([self isKindOfClass:UIView.class]) ChessForceImageOnView((UIView *)self);
}
static void HookSetFlairForPlayer(id self, SEL _cmd, id player) {
    if (ChessIsOwnPlayer(player) || ChessNameIsMe(ChessPlayerName(player))) ChessForceFlairOn(player);
    if (gSetFlairForPlayer) ((void (*)(id, SEL, id))gSetFlairForPlayer)(self, _cmd, player);
    if ([self isKindOfClass:UIView.class]) ChessForceImageOnView((UIView *)self);
}
static void HookSetupFlairWith(id self, SEL _cmd, id arg) {
    if (gSetupFlairWith) ((void (*)(id, SEL, id))gSetupFlairWith)(self, _cmd, arg);
    if ([self isKindOfClass:UIView.class]) ChessForceImageOnView((UIView *)self);
}

static void Install(Class c, SEL s, IMP n, IMP *o) { if (!c || !s || !n || !o || *o) return; Method m = class_getInstanceMethod(c, s); if (!m) m = class_getClassMethod(c, s); if (!m) return; *o = method_getImplementation(m); method_setImplementation(m, n); }
static void InstallAnywhere(SEL sel, IMP n, IMP *o) {
    if (!sel || !n || !o || *o) return;
    int nclasses = objc_getClassList(NULL, 0); if (nclasses <= 0) return;
    Class *classes = (Class *)malloc((size_t)nclasses * sizeof(Class)); if (!classes) return;
    nclasses = objc_getClassList(classes, nclasses);
    for (int i = 0; i < nclasses && !*o; i++) { Class c = classes[i]; if (!c) continue; Method m = class_getInstanceMethod(c, sel); if (!m) continue; if (method_getImplementation(m) == n) continue; *o = method_getImplementation(m); method_setImplementation(m, n); }
    free(classes);
}

static void Try(void);
static void Retry(void) { if (gTries++ >= 80) return; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ Try(); }); }
static void Try(void) {
    if (gReady) return;
    @autoreleasepool {
        InstallAnywhere(@selector(setFlairCode:), (IMP)HookSetFlairCode, &gSetFlairCode);
        InstallAnywhere(@selector(setFlairURL:), (IMP)HookSetFlairURL, &gSetFlairURL);
        InstallAnywhere(@selector(setFlairForPlayer:), (IMP)HookSetFlairForPlayer, &gSetFlairForPlayer);
        InstallAnywhere(@selector(setupFlairWith:), (IMP)HookSetupFlairWith, &gSetupFlairWith);

        if (gSetFlairCode || gSetFlairURL || gSetupFlairWith) {
            gReady = YES;
            ChessForceFlairOn(ChessUser());
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 1ull * NSEC_PER_SEC), 2ull * NSEC_PER_SEC, (uint64_t)(0.3 * NSEC_PER_SEC));
            dispatch_source_set_event_handler(timer, ^{ ChessForceOnAllWindows(); });
            dispatch_resume(timer);
        } else Retry();
    }
}
__attribute__((constructor)) static void ctor(void) { dispatch_async(dispatch_get_main_queue(), ^{ Try(); }); }
