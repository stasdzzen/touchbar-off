// Только synthetic events и fake backend: не запрашивает права и не создаёт tap.
#define main app_entry_for_keyboard_test
#import "../TouchBarApp.m"
#undef main
#import <IOKit/hidsystem/ev_keymap.h>
#include <assert.h>

@interface FakeKeyboardBackend : NSObject <TBKeyboardBackend>
@property BOOL permission;
@property BOOL create;
@property BOOL active;
@property BOOL enableOnStart;
@property int permissionCalls;
@property int startCalls;
@property int stopCalls;
@property (copy) TBKeyboardEventHandler handler;
@end
@implementation FakeKeyboardBackend
- (BOOL)requestAccessibility { self.permissionCalls++; return self.permission; }
- (BOOL)startWithHandler:(TBKeyboardEventHandler)handler {
    self.startCalls++;
    self.handler = handler;
    self.active = self.create && self.enableOnStart;
    return self.create;
}
- (BOOL)isEnabled { return self.active; }
- (void)stop { self.stopCalls++; self.active = NO; self.handler = nil; }
@end

static CGEventRef MediaEvent(unsigned int key) {
    NSEvent *event = [NSEvent otherEventWithType:NSEventTypeSystemDefined location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:8
        data1:(NSInteger)((key << 16) | 0x0a00) data2:0];
    CGEventRef cg = event.CGEvent;
    assert(cg);
    return CGEventCreateCopy(cg);
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    FakeKeyboardBackend *backend = [FakeKeyboardBackend new];
    TBKeyboardLock *lock = [[TBKeyboardLock alloc] initWithBackend:backend];
    __block int changes = 0;
    lock.stateChanged = ^{ changes++; };
    assert(!lock.isLocked && backend.permissionCalls == 0 && backend.startCalls == 0);
    assert(![lock lock]);
    assert(!lock.isLocked && backend.permissionCalls == 1 && backend.startCalls == 0);
    assert([lock.status containsString:@"Универсальный доступ"]);
    backend.permission = YES;
    assert(![lock lock]);
    assert(!lock.isLocked && backend.startCalls == 1 && !backend.handler);
    backend.create = YES;
    assert(![lock lock]); // Создан, но не включён.
    assert(!lock.isLocked && !backend.handler);
    backend.enableOnStart = YES;
    assert([lock lock]);
    assert(lock.isLocked && changes == 4);
    int starts = backend.startCalls;
    assert([lock lock] && backend.startCalls == starts);

    CGEventRef key = CGEventCreateKeyboardEvent(NULL, 0, true);
    assert(key);
    for (NSNumber *type in @[@(kCGEventKeyDown), @(kCGEventKeyUp), @(kCGEventFlagsChanged)]) {
        assert(backend.handler(type.unsignedIntValue, key) == NULL);
    }
    CGEventSetIntegerValueField(key, kCGKeyboardEventKeycode, 0x7f);
    assert(backend.handler(kCGEventKeyDown, key) == key);
    assert(backend.handler(kCGEventKeyUp, key) == key);
    assert(backend.handler(kCGEventFlagsChanged, key) == key);
    CGEventSetIntegerValueField(key, kCGKeyboardEventKeycode, 0);

    // Мышь, трекпад и scroll сохраняют события; keyboard modifiers сняты.
    CGEventFlags modifiers = kCGEventFlagMaskAlphaShift | kCGEventFlagMaskShift |
        kCGEventFlagMaskControl | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand |
        kCGEventFlagMaskSecondaryFn;
    for (NSNumber *type in @[@(kCGEventLeftMouseDown), @(kCGEventLeftMouseUp),
        @(kCGEventRightMouseDown), @(kCGEventRightMouseUp), @(kCGEventOtherMouseDown),
        @(kCGEventOtherMouseUp), @(kCGEventMouseMoved), @(kCGEventLeftMouseDragged),
        @(kCGEventRightMouseDragged), @(kCGEventOtherMouseDragged), @(kCGEventScrollWheel)]) {
        BOOL scroll = type.unsignedIntValue == kCGEventScrollWheel;
        CGEventRef pointer = scroll
            ? CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, 7)
            : CGEventCreateMouseEvent(NULL, type.unsignedIntValue, CGPointMake(45, 92), kCGMouseButtonLeft);
        assert(pointer);
        CGEventSetLocation(pointer, CGPointMake(45, 92));
        int64_t button = CGEventGetIntegerValueField(pointer, kCGMouseEventButtonNumber);
        CGEventSetFlags(pointer, modifiers | kCGEventFlagMaskNonCoalesced);
        assert(backend.handler(type.unsignedIntValue, pointer) == pointer);
        assert(CGEventGetFlags(pointer) == kCGEventFlagMaskNonCoalesced);
        assert(CGPointEqualToPoint(CGEventGetLocation(pointer), CGPointMake(45, 92)));
        assert(CGEventGetType(pointer) == type.unsignedIntValue);
        if (scroll) assert(CGEventGetIntegerValueField(pointer, kCGScrollWheelEventDeltaAxis1) == 7);
        else assert(CGEventGetIntegerValueField(pointer, kCGMouseEventButtonNumber) == button);
        CFRelease(pointer);
    }
    CGEventRef media = MediaEvent(NX_KEYTYPE_SOUND_UP);
    assert(backend.handler((CGEventType)14, media) == NULL);
    CFRelease(media);
    media = MediaEvent(NX_KEYTYPE_PLAY);
    assert(backend.handler((CGEventType)14, media) == NULL);
    CFRelease(media);
    media = MediaEvent(NX_POWER_KEY);
    assert(backend.handler((CGEventType)14, media) == media);
    CFRelease(media);
    assert(backend.handler((CGEventType)29, key) == key); // Неизвестный жест не фильтруется.

    for (NSNumber *type in @[@(kCGEventTapDisabledByTimeout), @(kCGEventTapDisabledByUserInput)]) {
        assert([lock lock]);
        TBKeyboardEventHandler callback = backend.handler;
        assert(callback(type.unsignedIntValue, key) == key);
        assert(!lock.isLocked && !backend.active && !backend.handler);
        assert([lock.status containsString:@"отключён macOS"]);
        assert(callback(kCGEventKeyDown, key) == key); // Сохранённый callback тоже fail-open.
    }
    assert([lock lock]);
    backend.active = NO; // Пропущенное уведомление disabled: проверка реального состояния.
    assert(!lock.isLocked && !backend.handler);
    assert([lock lock]);
    [lock unlock];
    assert(!lock.isLocked && [lock handleEvent:key type:kCGEventKeyDown] == key);
    CGEventSetFlags(key, modifiers);
    assert([lock handleEvent:key type:kCGEventScrollWheel] == key);
    assert(CGEventGetFlags(key) == modifiers); // После unlock flags больше не меняются.

    AppDelegate *app = [AppDelegate new];
    app.keyboardLock = lock;
    app.keyboardToggle = [[TBStateButton alloc] initWithFrame:NSMakeRect(0, 0, 230, 30)];
    app.keyboardStatus = [NSMenuItem new];
    assert([lock lock]);
    [app updateKeyboardUI];
    assert([app.keyboardToggle.title isEqualToString:@"Разблокировать клавиатуру"]);
    [app toggleKeyboard:nil];
    assert(!lock.isLocked && [app.keyboardToggle.title isEqualToString:@"Заблокировать клавиатуру"]);
    assert(!app.ready && !app.brightnessClient); // Клавиатура работает независимо от DFR.
    for (NSString *name in @[NSWorkspaceWillSleepNotification, NSWorkspaceSessionDidResignActiveNotification]) {
        assert([lock lock]);
        [app unlockKeyboardForLifecycle:[NSNotification notificationWithName:name object:nil]];
        assert(!lock.isLocked && !backend.active);
    }
    assert([lock lock]);
    [app applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:nil]];
    assert(!lock.isLocked && !backend.active);
    app.keyboardLock = nil;
    lock.stateChanged = nil;
    __weak TBKeyboardLock *weakLock = lock;
    assert([lock lock]);
    lock = nil;
    assert(!weakLock && !backend.active && !backend.handler); // Нет retain cycle.
    CFRelease(key);
    puts("OK: permissions/create/enable errors, keyboard/media/power callback, pointer pass-through, fail-open, UI, lifecycle, teardown без реального tap.");
} return 0; }
