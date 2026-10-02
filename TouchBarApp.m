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

// Системное оформление NSButton может игнорировать bezelColor.
// Рисуем только кнопку сами, сохраняя обработку нажатий и доступность NSButton.
@interface TBStateButton : NSButton
@property (nonatomic) BOOL panelEnabled;
@end

@implementation TBStateButton
- (void)setPanelEnabled:(BOOL)value {
    _panelEnabled = value;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGFloat alpha = self.enabled ? 1.0 : 0.45;
    NSColor *background = self.panelEnabled
        ? [NSColor colorWithSRGBRed:0.10 green:0.49 blue:0.25 alpha:alpha]
        : [NSColor colorWithSRGBRed:0.78 green:0.16 blue:0.18 alpha:alpha];
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:7 yRadius:7];
    [background setFill];
    [shape fill];
    if (self.cell.isHighlighted) {
        [[NSColor colorWithWhite:0 alpha:0.16] setFill];
        [shape fill];
    }
    NSDictionary *attributes = @{
        NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1 alpha:alpha]
    };
    NSSize size = [self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint(round((NSWidth(self.bounds) - size.width) / 2), round((NSHeight(self.bounds) - size.height) / 2)) withAttributes:attributes];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property NSStatusItem *statusItem;
@property NSMenu *menu;
@property TBStateButton *toggle;
@property TBStateButton *keyboardToggle;
@property NSMenuItem *keyboardStatus;
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
    self.menu = [NSMenu new];
    self.menu.autoenablesItems = NO;
    self.menu.delegate = self;
    self.statusItem.menu = self.menu;

    // Обычное меню macOS; собственная только строка цветной кнопки.
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 258, 44)];
    self.toggle = [[TBStateButton alloc] initWithFrame:NSMakeRect(14, 7, 230, 30)];
    self.toggle.target = self;
    self.toggle.action = @selector(togglePanel:);
    self.toggle.bordered = NO;
    self.toggle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.toggle.accessibilityLabel = @"Переключить Touch Bar";
    self.toggle.enabled = NO;
    [row addSubview:self.toggle];
    NSMenuItem *control = [NSMenuItem new];
    control.view = row;
    [self.menu addItem:control];

    NSView *keyboardRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 258, 44)];
    self.keyboardToggle = [[TBStateButton alloc] initWithFrame:NSMakeRect(14, 7, 230, 30)];
    self.keyboardToggle.target = self;
    self.keyboardToggle.action = @selector(toggleKeyboard:);
    self.keyboardToggle.bordered = NO;
    self.keyboardToggle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.keyboardToggle.accessibilityLabel = @"Блокировка клавиатуры для чистки";
    [keyboardRow addSubview:self.keyboardToggle];
    NSMenuItem *keyboardControl = [NSMenuItem new];
    keyboardControl.view = keyboardRow;
    [self.menu addItem:keyboardControl];
    self.keyboardStatus = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    self.keyboardStatus.enabled = NO;
    [self.menu addItem:self.keyboardStatus];
    self.keyboardLock = [TBKeyboardLock new];
    __weak AppDelegate *weakSelf = self;
    self.keyboardLock.stateChanged = ^{ [weakSelf updateKeyboardUI]; };

    // Lifecycle клавиатуры независим от наличия клиента Touch Bar.
    NSNotificationCenter *workspaceCenter = [[NSWorkspace sharedWorkspace] notificationCenter];
    [workspaceCenter addObserver:self selector:@selector(unlockKeyboardForLifecycle:) name:NSWorkspaceWillSleepNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(unlockKeyboardForLifecycle:) name:NSWorkspaceSessionDidResignActiveNotification object:nil];

    NSMenuItem *website = [[NSMenuItem alloc] initWithTitle:@"Dzzen.com ↗" action:@selector(openWebsite:) keyEquivalent:@""];
    website.target = self;
    [self.menu addItem:website];
    [self.menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Закрыть приложение" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [self.menu addItem:quit];
    [self updateUI];
    [self updateKeyboardUI];

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
        self.toggle.enabled = YES;
        [self applyEnabled:self.enabled];
    });
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(woke:) name:NSWorkspaceDidWakeNotification object:nil];
}

- (void)updateUI {
    self.toggle.title = self.enabled ? @"Touch Bar включён" : @"Touch Bar выключен";
    self.toggle.panelEnabled = self.enabled;
    self.toggle.accessibilityValue = self.enabled ? @"Включён" : @"Выключен";
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
    [self applyEnabled:!self.enabled];
}

- (void)updateKeyboardUI {
    BOOL locked = self.keyboardLock.isLocked;
    self.keyboardToggle.title = locked ? @"Разблокировать клавиатуру" : @"Заблокировать клавиатуру";
    self.keyboardToggle.panelEnabled = !locked;
    self.keyboardToggle.accessibilityValue = locked ? @"Заблокирована" : @"Доступна";
    self.keyboardStatus.title = locked ? @"Клавиатура заблокирована для чистки" : @"Клавиатура доступна";
    self.keyboardStatus.toolTip = self.keyboardLock.status;
    self.keyboardToggle.toolTip = self.keyboardLock.status;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    (void)menu;
    // Перечитываем доступность реального tap перед показом меню.
    [self updateKeyboardUI];
}

- (void)toggleKeyboard:(id)sender {
    (void)sender;
    if (self.keyboardLock.isLocked) [self.keyboardLock unlock];
    else if (![self.keyboardLock lock]) {
        [self.menu cancelTracking];
        [NSApp activateIgnoringOtherApps:YES];
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Клавиатура не заблокирована";
        alert.informativeText = [self.keyboardLock.status stringByAppendingString:
            @". Проверьте разрешение в Системных настройках → Конфиденциальность и безопасность → Универсальный доступ. После выдачи разрешения нажмите кнопку снова; если macOS требует перезапуск, закройте и откройте приложение. Если разрешение уже есть, эта версия macOS могла отклонить HID event tap; клавиатура остаётся доступной."];
        [alert addButtonWithTitle:@"Понятно"];
        [alert runModal];
    }
    [self updateKeyboardUI];
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
