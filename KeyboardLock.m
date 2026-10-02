// Copyright (c) 2026 Dzzen.com. SPDX-License-Identifier: MIT
#import "KeyboardLock.h"
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/hidsystem/ev_keymap.h>
#include <unistd.h>

// NX_SYSDEFINED / NX_SUBTYPE_AUX_CONTROL_BUTTONS из системного event API.
static const CGEventType TBSystemDefined = (CGEventType)14;
static const unsigned short TBPowerKeyCode = 0x7f;

static BOOL TBPointerEvent(CGEventType type) {
    switch (type) {
        case kCGEventLeftMouseDown: case kCGEventLeftMouseUp:
        case kCGEventRightMouseDown: case kCGEventRightMouseUp:
        case kCGEventOtherMouseDown: case kCGEventOtherMouseUp:
        case kCGEventMouseMoved: case kCGEventLeftMouseDragged:
        case kCGEventRightMouseDragged: case kCGEventOtherMouseDragged:
        case kCGEventScrollWheel: return YES;
        default: return NO;
    }
}

@interface TBKeyboardLock ()
@property (nonatomic) id<TBKeyboardBackend> backend;
@property (nonatomic, readwrite, copy) NSString *status;
@end

@implementation TBKeyboardLock {
    BOOL _locked;
}
- (instancetype)init {
    return [self initWithBackend:[TBSystemKeyboardBackend new]];
}
- (instancetype)initWithBackend:(id<TBKeyboardBackend>)backend {
    if ((self = [super init])) {
        _backend = backend;
        _status = @"Клавиатура доступна";
    }
    return self;
}
- (BOOL)isLocked {
    if (_locked && ![self.backend isEnabled]) {
        [self unlockWithStatus:@"Клавиатура доступна: перехват отключён macOS"];
    }
    return _locked;
}
- (void)changed {
    if (self.stateChanged) self.stateChanged();
}
- (BOOL)lock {
    if (self.isLocked) return YES;
    // Запрос вызывается исключительно из действия кнопки, а не при запуске.
    if (![self.backend requestAccessibility]) {
        [self unlockWithStatus:@"Клавиатура доступна: разрешите Универсальный доступ и нажмите снова"];
        return NO;
    }
    __weak TBKeyboardLock *weakSelf = self;
    BOOL started = [self.backend startWithHandler:^CGEventRef(CGEventType type, CGEventRef event) {
        TBKeyboardLock *owner = weakSelf;
        return owner ? [owner handleEvent:event type:type] : event;
    }];
    if (!started || ![self.backend isEnabled]) {
        [self unlockWithStatus:@"Клавиатура доступна: macOS не включила перехват"];
        return NO;
    }
    _locked = YES;
    self.status = @"Клавиатура заблокирована для чистки";
    [self changed];
    return YES;
}
- (void)unlock { [self unlockWithStatus:@"Клавиатура доступна"]; }
- (void)unlockWithStatus:(NSString *)status {
    _locked = NO;
    [self.backend stop];
    self.status = status;
    [self changed];
}
- (CGEventRef)handleEvent:(CGEventRef)event type:(CGEventType)type {
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        // Fail-open: никогда не включаем tap автоматически после сбоя.
        [self unlockWithStatus:@"Клавиатура доступна: перехват отключён macOS"];
        return event;
    }
    if (!self.isLocked || !event) return event;
    if (TBPointerEvent(type)) {
        // Ctrl-click и Shift-scroll не должны мешать разблокировке мышью.
        // Не изменяем кнопки, координаты, delta, momentum или тип события.
        CGEventFlags keyboardFlags = kCGEventFlagMaskAlphaShift | kCGEventFlagMaskShift |
            kCGEventFlagMaskControl | kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand |
            kCGEventFlagMaskSecondaryFn;
        CGEventSetFlags(event, CGEventGetFlags(event) & ~keyboardFlags);
        return event;
    }
    if (type == kCGEventKeyDown || type == kCGEventKeyUp || type == kCGEventFlagsChanged) {
        // Power не блокируется. Touch ID не является клавиатурным CGEvent.
        return CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) == TBPowerKeyCode ? event : NULL;
    }
    if (type == TBSystemDefined) {
        NSEvent *native = [NSEvent eventWithCGEvent:event];
        if (native.type == NSEventTypeSystemDefined && native.subtype == 8) {
            unsigned int key = ((unsigned int)native.data1 >> 16) & 0xffff;
            if (key != NX_POWER_KEY) return NULL;
        }
    }
    // Не читаем символы и не записываем ввод в лог или на диск.
    return event;
}
- (void)dealloc { [_backend stop]; }
@end

@interface TBSystemKeyboardBackend ()
@property (nonatomic, copy) TBKeyboardEventHandler handler;
@end

@implementation TBSystemKeyboardBackend {
    CFMachPortRef _tap;
    CFRunLoopSourceRef _source;
}
static CGEventRef TBKeyboardCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    (void)proxy;
    // Сильная локальная ссылка сохраняет backend при teardown внутри callback.
    __attribute__((objc_precise_lifetime)) TBSystemKeyboardBackend *backend = (__bridge TBSystemKeyboardBackend *)context;
    TBKeyboardEventHandler handler = backend.handler;
    return handler ? handler(type, event) : event;
}
- (BOOL)requestAccessibility {
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
}
- (BOOL)hasEventMask:(CGEventMask)mask {
    // CoreGraphics может убрать клавиатурные bits из маски при отказе доступа,
    // оставив активный mouse tap. Не выдаём такой результат за блокировку.
    uint32_t capacity = 0;
    if (CGGetEventTapList(0, NULL, &capacity) != kCGErrorSuccess || !capacity) return NO;
    CGEventTapInformation *list = calloc(capacity, sizeof(*list));
    if (!list) return NO;
    uint32_t count = 0;
    BOOL found = NO;
    if (CGGetEventTapList(capacity, list, &count) == kCGErrorSuccess) {
        for (uint32_t index = 0; index < MIN(count, capacity); index++) {
            CGEventTapInformation info = list[index];
            // В этом процессе есть только один наш HID tap.
            if (info.tappingProcess == getpid() && info.tapPoint == kCGHIDEventTap &&
                info.options == kCGEventTapOptionDefault && info.enabled &&
                (info.eventsOfInterest & mask) == mask) { found = YES; break; }
        }
    }
    free(list);
    return found;
}
- (BOOL)startWithHandler:(TBKeyboardEventHandler)handler {
    [self stop];
    self.handler = handler;
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) |
        CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(TBSystemDefined);
    for (CGEventType type = kCGEventLeftMouseDown; type <= kCGEventOtherMouseDragged; type++) {
        if (TBPointerEvent(type)) mask |= CGEventMaskBit(type);
    }
    // Один активный HID tap; fallback на более поздний session tap отсутствует.
    _tap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                           mask, TBKeyboardCallback, (__bridge void *)self);
    if (!_tap) { [self stop]; return NO; }
    _source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
    if (!_source) { [self stop]; return NO; }
    // Меню AppKit работает в tracking mode: фильтр остаётся активен внутри меню.
    CFRunLoopAddCommonMode(CFRunLoopGetMain(), (__bridge CFStringRef)NSEventTrackingRunLoopMode);
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
    CGEventTapEnable(_tap, true);
    if (![self isEnabled] || !AXIsProcessTrusted() || ![self hasEventMask:mask]) {
        [self stop];
        return NO;
    }
    return YES;
}
- (BOOL)isEnabled { return _tap && CFMachPortIsValid(_tap) && CGEventTapIsEnabled(_tap); }
- (void)stop {
    if (_tap) CGEventTapEnable(_tap, false);
    if (_source) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRunLoopSourceInvalidate(_source);
        CFRelease(_source);
        _source = NULL;
    }
    if (_tap) {
        CFMachPortInvalidate(_tap);
        CFRelease(_tap);
        _tap = NULL;
    }
    self.handler = nil;
}
- (void)dealloc { [self stop]; }
@end
