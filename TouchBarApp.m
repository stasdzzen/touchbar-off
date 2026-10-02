// Copyright (c) 2026 Dzzen.com. SPDX-License-Identifier: MIT
#import <Cocoa/Cocoa.h>
#import "KeyboardLock.h"
#include <dlfcn.h>

// Сигнатуры сверены с Objective-C runtime на macOS 26.6.2.
@interface NSObject (DFRBrightnessAPI)
- (void)scheduleWithDispatchQueue:(dispatch_queue_t)queue;
- (void)unscheduleWithDispatchQueue:(dispatch_queue_t)queue;
- (int)getDFRDisplayID;
- (BOOL)turnOff;
- (BOOL)turnOn;
@end

// Постоянная геометрия: изменение состояния меняет текст, но не размер меню.
@interface TBToggleRow : NSView
@property NSSwitch *control;
@property NSTextField *label;
@property NSTextField *detail;
- (instancetype)initWithTitle:(NSString *)title target:(id)target action:(SEL)action;
@end

@implementation TBToggleRow
- (instancetype)initWithTitle:(NSString *)title target:(id)target action:(SEL)action {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 320, 64)])) {
        _control = [[NSSwitch alloc] initWithFrame:NSMakeRect(16, 30, 38, 24)];
        _control.target = target;
        _control.action = action;
        _control.accessibilityLabel = title;
        [self addSubview:_control];
        _label = [NSTextField labelWithString:title];
        _label.frame = NSMakeRect(68, 35, 236, 19);
        _label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        _label.textColor = NSColor.labelColor;
        _label.lineBreakMode = NSLineBreakByClipping;
        [self addSubview:_label];
        _detail = [NSTextField labelWithString:@""];
        _detail.frame = NSMakeRect(68, 15, 236, 16);
        _detail.font = [NSFont systemFontOfSize:11];
        _detail.textColor = NSColor.secondaryLabelColor;
        _detail.lineBreakMode = NSLineBreakByClipping;
        [self addSubview:_detail];
    }
    return self;
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property NSStatusItem *statusItem;
@property NSMenu *menu;
@property NSSwitch *toggle;
@property NSSwitch *keyboardToggle;
@property TBToggleRow *panelRow;
@property TBToggleRow *keyboardRow;
@property TBKeyboardLock *keyboardLock;
@property id brightnessClient;
@property BOOL enabled;
@property BOOL ready;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    // По умолчанию сохраняем выбранное владельцем гашение панели.
    self.enabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"TouchBarEnabled"];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSImage *icon = [[NSBundle mainBundle] imageForResource:@"MenuIcon"];
    icon.size = NSMakeSize(20, 18);
    icon.template = YES;
    self.statusItem.button.image = icon;
    if (!icon) self.statusItem.button.title = @"TB";
    self.statusItem.button.accessibilityLabel = @"Touch Bar";
    [self createMenu];
    self.statusItem.menu = self.menu;

    // Lifecycle клавиатуры независим от наличия клиента Touch Bar.
    NSNotificationCenter *workspaceCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [workspaceCenter addObserver:self selector:@selector(unlockKeyboardForLifecycle:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(unlockKeyboardForLifecycle:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];

    void *framework = dlopen("/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness", RTLD_NOW | RTLD_LOCAL);
    Class clientClass = framework ? NSClassFromString(@"DFRBrightnessClient") : Nil;
    self.brightnessClient = clientClass ? [[clientClass alloc] init] : nil;
    for (NSString *name in @[@"scheduleWithDispatchQueue:", @"unscheduleWithDispatchQueue:", @"getDFRDisplayID", @"turnOff", @"turnOn"]) {
        if (![self.brightnessClient respondsToSelector:NSSelectorFromString(name)]) {
            self.brightnessClient = nil;
            [self showError:@"Эта версия macOS не поддерживает используемый способ управления Touch Bar."];
            return;
        }
    }
    [self.brightnessClient scheduleWithDispatchQueue:dispatch_get_main_queue()];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.ready = YES;
        [self applyEnabled:self.enabled];
    });
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(woke:) name:NSWorkspaceDidWakeNotification object:nil];
}

// Можно создать настоящее меню в тесте с fake backend, без DFR и event tap.
- (void)createMenu {
    self.menu = [NSMenu new];
    self.menu.autoenablesItems = NO;
    self.menu.delegate = self;
    self.menu.minimumWidth = 320;

    self.panelRow = [[TBToggleRow alloc] initWithTitle:@"Touch Bar" target:self action:@selector(togglePanel:)];
    self.toggle = self.panelRow.control;
    NSMenuItem *control = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    control.view = self.panelRow;
    [self.menu addItem:control];

    self.keyboardRow = [[TBToggleRow alloc] initWithTitle:@"Чистка клавиатуры" target:self action:@selector(toggleKeyboard:)];
    self.keyboardToggle = self.keyboardRow.control;
    NSMenuItem *keyboardControl = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    keyboardControl.view = self.keyboardRow;
    [self.menu addItem:keyboardControl];
    if (!self.keyboardLock) self.keyboardLock = [TBKeyboardLock new];
    __weak AppDelegate *weakSelf = self;
    self.keyboardLock.stateChanged = ^{ [weakSelf updateKeyboardUI]; };

    NSMenuItem *website = [[NSMenuItem alloc] initWithTitle:@"Dzzen.com ↗" action:@selector(openWebsite:) keyEquivalent:@""];
    website.target = self;
    [self.menu addItem:website];
    [self.menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Закрыть приложение" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [self.menu addItem:quit];
    [self updateUI];
    [self updateKeyboardUI];
}

- (void)updateUI {
    self.toggle.state = self.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.toggle.enabled = self.ready;
    self.panelRow.detail.stringValue = self.ready ? (self.enabled ? @"Включён" : @"Выключен") : @"Панель недоступна";
    self.toggle.accessibilityHelp = @"Включённый тумблер включает Touch Bar. Выключенный гасит панель.";
    self.statusItem.button.toolTip = self.enabled ? @"Touch Bar: включение выбрано" : @"Touch Bar: гашение выбрано";
}

- (BOOL)applyEnabled:(BOOL)enabled {
    if (!self.ready || [self.brightnessClient getDFRDisplayID] <= 0) {
        [self updateUI];
        [self showError:@"Дисплей Touch Bar пока недоступен. Попробуйте ещё раз."];
        return NO;
    }
    BOOL accepted = enabled ? [self.brightnessClient turnOn] : [self.brightnessClient turnOff];
    if (!accepted) {
        [self updateUI];
        [self showError:@"macOS отклонила команду. Предыдущее положение переключателя сохранено."];
        return NO;
    }
    self.enabled = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"TouchBarEnabled"];
    [self updateUI];
    return YES;
}

- (void)togglePanel:(id)sender {
    (void)sender;
    [self applyEnabled:self.toggle.state == NSControlStateValueOn];
}

- (void)updateKeyboardUI {
    BOOL locked = self.keyboardLock.isLocked;
    self.keyboardToggle.state = locked ? NSControlStateValueOn : NSControlStateValueOff;
    self.keyboardRow.detail.stringValue = locked ? @"Заблокирована · трекпад работает" : @"Доступна · трекпад работает";
    self.keyboardToggle.accessibilityHelp = @"Включите для чистки клавиатуры. Выключите трекпадом или мышью, чтобы снова печатать.";
    self.keyboardRow.detail.toolTip = self.keyboardLock.status;
    self.keyboardToggle.toolTip = self.keyboardLock.status;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    (void)menu;
    // Перечитываем доступность реального tap перед показом меню.
    [self updateKeyboardUI];
}

- (void)toggleKeyboard:(id)sender {
    (void)sender;
    if (self.keyboardToggle.state == NSControlStateValueOff) [self.keyboardLock unlock];
    else if (![self.keyboardLock lock]) [self showKeyboardError:self.keyboardLock.status];
    [self updateKeyboardUI];
}

- (void)showKeyboardError:(NSString *)message {
    [self.menu cancelTracking];
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Клавиатура не заблокирована";
    alert.informativeText = [message stringByAppendingString:
        @". Разрешите Touch Bar в Системных настройках → Конфиденциальность и безопасность → Универсальный доступ, затем включите тумблер снова. Если macOS требует перезапуск, закройте и откройте приложение. Если разрешение уже есть, macOS могла отклонить блокировку; клавиатура остаётся доступной."];
    [alert addButtonWithTitle:@"Понятно"];
    [alert runModal];
}

- (void)unlockKeyboardForLifecycle:(NSNotification *)notification {
    (void)notification;
    [self.keyboardLock unlockWithStatus:@"Клавиатура доступна: блокировка снята при сне или смене сессии"];
}

- (void)woke:(NSNotification *)notification {
    (void)notification;
    // Повторяем последний выбор после пробуждения, без постоянного опроса.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.ready) [self applyEnabled:self.enabled];
    });
}

- (void)openWebsite:(id)sender {
    (void)sender;
    NSURL *url = [NSURL URLWithString:@"https://dzzen.com/?utm_source=touchbar-off&utm_medium=app&utm_campaign=menu"];
    [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)showError:(NSString *)message {
    [self.menu cancelTracking];
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Не удалось переключить Touch Bar";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"Понятно"];
    [alert runModal];
}

- (void)quit:(id)sender {
    (void)sender;
    [self.keyboardLock unlock];
    [NSApp terminate:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.keyboardLock unlock];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    // Не включаем мерцающую панель при закрытии приложения.
    [self.brightnessClient unscheduleWithDispatchQueue:dispatch_get_main_queue()];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        __attribute__((objc_precise_lifetime)) AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
