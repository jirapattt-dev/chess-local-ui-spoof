#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

/* 3.16.1
 * FM title only. No flair, no moderator.
 * Forces chessTitle / setPlayerTitle: / updateTitleViewWithTitle: for current user.
 */

static IMP gSetPlayerTitle, gUpdateTitleView, gHidePlayerTitle;
static IMP gPlayerInfoFactory, gLiveUserInit;
static BOOL gReady;
static NSUInteger gTries;

static NSString * const kTitle = @"FM";

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

static void ChessForceTitleOn(id obj) {
    if (!obj) return;
    @try {
        if ([obj respondsToSelector:@selector(setChessTitle:)])
            ((void (*)(id, SEL, id))objc_msgSend)(obj, @selector(setChessTitle:), kTitle);
        if ([obj respondsToSelector:@selector(setPlayerTitle:)])
            ((void (*)(id, SEL, id))objc_msgSend)(obj, @selector(setPlayerTitle:), kTitle);
    } @catch (__unused NSException *e) {}
}

static void HookSetPlayerTitle(id self, SEL _cmd, id title) {
    id use = (ChessIsOwnPlayer(self) || ChessNameIsMe(ChessPlayerName(self))) ? kTitle : title;
    if (gSetPlayerTitle) ((void (*)(id, SEL, id))gSetPlayerTitle)(self, _cmd, use);
}
static void HookUpdateTitleView(id self, SEL _cmd, id title) {
    id use = (ChessIsOwnPlayer(self) || ChessNameIsMe(ChessPlayerName(self))) ? kTitle : title;
    if (gUpdateTitleView) ((void (*)(id, SEL, id))gUpdateTitleView)(self, _cmd, use);
}
static void HookHidePlayerTitle(id self, SEL _cmd) {
    if (ChessIsOwnPlayer(self) || ChessNameIsMe(ChessPlayerName(self))) return;
    if (gHidePlayerTitle) ((void (*)(id, SEL))gHidePlayerTitle)(self, _cmd);
}

static id HookPlayerInfoFactory(id self, SEL _cmd, id username, id chessTitle, id avatarURL, id flairURL, id premiumStatus, id countryId, id color) {
    id title = chessTitle;
    if ([username isKindOfClass:NSString.class] && ChessNameIsMe((NSString *)username))
        title = kTitle;
    if (gPlayerInfoFactory)
        return ((id (*)(id, SEL, id, id, id, id, id, id, id))gPlayerInfoFactory)(self, _cmd, username, title, avatarURL, flairURL, premiumStatus, countryId, color);
    return nil;
}
static id HookLiveUserInit(id self, SEL _cmd, id username, id title, id flairURL, id premiumStatus, id friends) {
    id t = title;
    if ([username isKindOfClass:NSString.class] && ChessNameIsMe((NSString *)username))
        t = kTitle;
    if (gLiveUserInit)
        return ((id (*)(id, SEL, id, id, id, id, id))gLiveUserInit)(self, _cmd, username, t, flairURL, premiumStatus, friends);
    return nil;
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
        InstallAnywhere(@selector(setPlayerTitle:), (IMP)HookSetPlayerTitle, &gSetPlayerTitle);
        InstallAnywhere(@selector(updateTitleViewWithTitle:), (IMP)HookUpdateTitleView, &gUpdateTitleView);
        InstallAnywhere(@selector(hidePlayerTitle), (IMP)HookHidePlayerTitle, &gHidePlayerTitle);

        SEL piSel = @selector(playerInfoWithUsername:chessTitle:avatarURL:flairURL:premiumStatus:countryId:color:);
        for (NSString *name in @[ @"CHPlayerInfo", @"CHGame", @"CHCurrentUser", @"CHLiveUser" ]) {
            Class c = NSClassFromString(name); if (!c) continue;
            if (class_getInstanceMethod(c, piSel) || class_getClassMethod(c, piSel)) {
                Install(c, piSel, (IMP)HookPlayerInfoFactory, &gPlayerInfoFactory);
                if (!gPlayerInfoFactory) { Method m = class_getClassMethod(c, piSel); if (m) { gPlayerInfoFactory = method_getImplementation(m); method_setImplementation(m, (IMP)HookPlayerInfoFactory); } }
                if (gPlayerInfoFactory) break;
            }
        }
        SEL liveInit = @selector(initLiveUserWithUsername:title:flairURL:premiumStatus:friends:);
        for (NSString *name in @[ @"CHLiveUser", @"CHCurrentUser", @"CHPlayerInfo" ]) { Class c = NSClassFromString(name); if (c && class_getInstanceMethod(c, liveInit)) { Install(c, liveInit, (IMP)HookLiveUserInit, &gLiveUserInit); if (gLiveUserInit) break; } }

        if (gSetPlayerTitle || gPlayerInfoFactory) {
            gReady = YES;
            ChessForceTitleOn(ChessUser());
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2ull * NSEC_PER_SEC), 5ull * NSEC_PER_SEC, (uint64_t)(0.5 * NSEC_PER_SEC));
            dispatch_source_set_event_handler(timer, ^{ ChessForceTitleOn(ChessUser()); });
            dispatch_resume(timer);
        } else Retry();
    }
}
__attribute__((constructor)) static void ctor(void) { dispatch_async(dispatch_get_main_queue(), ^{ Try(); }); }
