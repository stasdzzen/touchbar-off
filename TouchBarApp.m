// Copyright (c) 2026 Dzzen.com. SPDX-License-Identifier: MIT
#import <Cocoa/Cocoa.h>
#include <dlfcn.h>

// Сигнатуры сверены с Objective-C runtime на macOS 26.6.2.
@interface NSObject (DFRBrightnessAPI)
- (void)scheduleWithDispatchQueue:(dispatch_queue_t)queue;
- (void)unscheduleWithDispatchQueue:(dispatch_queue_t)queue;
- (int)getDFRDisplayID;
- (BOOL)turnOff;
- (BOOL)turnOn;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSMenu *menu;
@property NSButton *toggle;
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
    self.statusItem.menu = self.menu;

    // Обычное меню macOS; собственная только строка цветной кнопки.
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 218, 44)];
    self.toggle = [NSButton buttonWithTitle:@"" target:self action:@selector(togglePanel:)];
    self.toggle.frame = NSMakeRect(14, 7, 190, 30);
    self.toggle.bezelStyle = NSBezelStyleRounded;
    self.toggle.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.toggle.contentTintColor = NSColor.whiteColor;
    self.toggle.accessibilityLabel = @"Переключить Touch Bar";
    self.toggle.enabled = NO;
    [row addSubview:self.toggle];
    NSMenuItem *control = [NSMenuItem new];
    control.view = row;
    [self.menu addItem:control];

    NSMenuItem *website = [[NSMenuItem alloc] initWithTitle:@"Dzzen.com ↗" action:@selector(openWebsite:) keyEquivalent:@""];
    website.target = self;
    [self.menu addItem:website];
    [self.menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Закрыть приложение" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [self.menu addItem:quit];
    [self updateUI];

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
    self.toggle.bezelColor = self.enabled ? NSColor.systemGreenColor : NSColor.systemRedColor;
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
    [NSApp terminate:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
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
