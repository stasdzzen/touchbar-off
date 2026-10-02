// Реальные AppKit views, fake backend: геометрия меню и состояния без ввода.
#define main app_entry_for_menu_test
#import "../TouchBarApp.m"
#undef main
#import "FakeKeyboardBackend.h"
#include <assert.h>

@interface MenuPanel : NSObject
@property BOOL accept;
@property int displayID;
@end
@implementation MenuPanel
- (int)getDFRDisplayID { return self.displayID; }
- (BOOL)turnOn { return self.accept; }
- (BOOL)turnOff { return self.accept; }
@end

@interface MenuDelegate : AppDelegate
@property int panelErrors;
@property int keyboardErrors;
@end
@implementation MenuDelegate
- (void)showError:(NSString *)message { (void)message; self.panelErrors++; }
- (void)showKeyboardError:(NSString *)message { (void)message; self.keyboardErrors++; }
@end

static NSArray<NSValue *> *Frames(AppDelegate *app) {
    NSMutableArray<NSValue *> *frames = [NSMutableArray new];
    for (TBToggleRow *row in @[app.panelRow, app.keyboardRow]) {
        [row layoutSubtreeIfNeeded];
        for (NSView *view in @[row, row.control, row.label, row.detail]) {
            [frames addObject:[NSValue valueWithRect:view.frame]];
        }
    }
    return frames;
}

static void StableGeometry(AppDelegate *app, NSSize size, NSArray<NSValue *> *frames) {
    [app.menu update];
    assert(NSEqualSizes(app.menu.size, size));
    assert([Frames(app) isEqualToArray:frames]);
    assert([app.panelRow.label.stringValue isEqualToString:@"Touch Bar"]);
    assert([app.keyboardRow.label.stringValue isEqualToString:@"Чистка клавиатуры"]);
    // Все menu item titles постоянны; меняются только поля фиксированного размера.
    for (NSMenuItem *item in app.menu.itemArray) {
        if (item.view) assert(item.title.length == 0);
    }
    for (TBToggleRow *row in @[app.panelRow, app.keyboardRow]) {
        NSSize text = [row.detail.stringValue sizeWithAttributes:@{NSFontAttributeName: row.detail.font}];
        assert(text.width <= NSWidth(row.detail.bounds) - 4);
    }
}

// Фон для offscreen артефакта. Содержимое — те же AppKit rows, что в NSMenu.
@interface MenuPreview : NSView
@end
@implementation MenuPreview
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(dirtyRect);
}
@end

static void Render(NSString *appearanceName, NSString *suffix, BOOL enabled, BOOL locked) {
    FakeKeyboardBackend *backend = [FakeKeyboardBackend new];
    backend.permission = backend.create = backend.enableOnStart = YES;
    MenuDelegate *app = [MenuDelegate new];
    app.keyboardLock = [[TBKeyboardLock alloc] initWithBackend:backend];
    app.ready = YES;
    app.enabled = enabled;
    [app createMenu];
    if (locked) assert([app.keyboardLock lock]);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 320, 128)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    MenuPreview *preview = [[MenuPreview alloc] initWithFrame:NSMakeRect(0, 0, 320, 128)];
    window.contentView = preview;
    window.appearance = [NSAppearance appearanceNamed:appearanceName];
    // NSMenu задаёт frame своих views при смене window. Сначала отсоединяем.
    for (NSMenuItem *item in app.menu.itemArray) if (item.view) item.view = nil;
    [preview addSubview:app.panelRow];
    [preview addSubview:app.keyboardRow];
    app.panelRow.frame = NSMakeRect(0, 64, 320, 64);
    app.keyboardRow.frame = NSMakeRect(0, 0, 320, 64);
    [window.appearance performAsCurrentDrawingAppearance:^{
        [preview layoutSubtreeIfNeeded];
        NSBitmapImageRep *bitmap = [preview bitmapImageRepForCachingDisplayInRect:preview.bounds];
        assert(bitmap);
        [preview cacheDisplayInRect:preview.bounds toBitmapImageRep:bitmap];
        assert(NSEqualRects(app.panelRow.frame, NSMakeRect(0, 64, 320, 64)));
        assert(NSEqualRects(app.keyboardRow.frame, NSMakeRect(0, 0, 320, 64)));
        NSString *file = [NSString stringWithFormat:@"build/tests/menu-%@-%@.png", suffix, locked ? @"on" : @"off"];
        assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:file atomically:YES]);
    }];
    [app.keyboardLock unlock];
    [window close];
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id previous = [defaults objectForKey:@"TouchBarEnabled"];
    FakeKeyboardBackend *backend = [FakeKeyboardBackend new];
    backend.permission = backend.create = backend.enableOnStart = YES;
    MenuDelegate *app = [MenuDelegate new];
    app.keyboardLock = [[TBKeyboardLock alloc] initWithBackend:backend];
    MenuPanel *panel = [MenuPanel new];
    panel.accept = YES;
    panel.displayID = 3;
    app.brightnessClient = panel;
    [app createMenu];
    assert(backend.permissionCalls == 0 && backend.startCalls == 0);
    [app.menu update];
    NSSize size = app.menu.size;
    NSArray<NSValue *> *frames = Frames(app);
    assert(!app.toggle.enabled && !app.keyboardLock.isLocked);
    StableGeometry(app, size, frames);
    app.ready = YES;
    for (int panelState = 0; panelState < 2; panelState++) {
        for (int keyboardState = 0; keyboardState < 2; keyboardState++) {
            app.toggle.state = panelState ? NSControlStateValueOn : NSControlStateValueOff;
            [app togglePanel:app.toggle];
            app.keyboardToggle.state = keyboardState ? NSControlStateValueOn : NSControlStateValueOff;
            [app toggleKeyboard:app.keyboardToggle];
            assert(app.enabled == (BOOL)panelState && app.keyboardLock.isLocked == (BOOL)keyboardState);
            assert(app.toggle.state == (panelState ? NSControlStateValueOn : NSControlStateValueOff));
            assert(app.keyboardToggle.state == (keyboardState ? NSControlStateValueOn : NSControlStateValueOff));
            StableGeometry(app, size, frames);
        }
    }
    // AppKit уже переместил thumb: отказ возвращает фактическое состояние.
    panel.accept = NO;
    app.toggle.state = NSControlStateValueOff;
    [app togglePanel:app.toggle];
    assert(app.panelErrors == 1 && app.enabled && app.toggle.state == NSControlStateValueOn);
    StableGeometry(app, size, frames);
    panel.displayID = 0;
    app.toggle.state = NSControlStateValueOff;
    [app togglePanel:app.toggle];
    assert(app.panelErrors == 2 && app.toggle.state == NSControlStateValueOn);
    app.ready = NO;
    [app updateUI];
    assert(!app.toggle.enabled);
    StableGeometry(app, size, frames);

    [app.keyboardLock unlock];
    for (int failure = 0; failure < 3; failure++) {
        backend.permission = failure != 0;
        backend.create = failure != 1;
        backend.enableOnStart = failure != 2;
        app.keyboardToggle.state = NSControlStateValueOn;
        [app toggleKeyboard:app.keyboardToggle];
        assert(!app.keyboardLock.isLocked && app.keyboardToggle.state == NSControlStateValueOff);
        StableGeometry(app, size, frames);
    }
    assert(app.keyboardErrors == 3);
    backend.permission = backend.create = backend.enableOnStart = YES;
    app.keyboardToggle.state = NSControlStateValueOn;
    [app toggleKeyboard:app.keyboardToggle];
    backend.active = NO;
    [app menuNeedsUpdate:app.menu];
    assert(app.keyboardToggle.state == NSControlStateValueOff);
    StableGeometry(app, size, frames);
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        NSString *suffix = [appearance isEqualToString:NSAppearanceNameAqua] ? @"light" : @"dark";
        Render(appearance, suffix, NO, NO);
        Render(appearance, suffix, YES, YES);
    }
    if (previous) [defaults setObject:previous forKey:@"TouchBarEnabled"];
    else [defaults removeObjectForKey:@"TouchBarEnabled"];
    puts("OK: NSSwitch states/errors, постоянные NSMenu size и frames во всех состояниях; AppKit PNG light/dark без DFR/event tap.");
} return 0; }
