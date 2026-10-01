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
@property NSPopover *popover;
@property NSSwitch *toggle;
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
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(showPopover:);

    NSViewController *controller = [NSViewController new];
    controller.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 230, 100)];
    NSTextField *label = [NSTextField labelWithString:@"Touch Bar"];
    label.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    label.frame = NSMakeRect(18, 61, 140, 22);
    [controller.view addSubview:label];
    self.toggle = [[NSSwitch alloc] initWithFrame:NSMakeRect(172, 59, 40, 25)];
    self.toggle.accessibilityLabel = @"Touch Bar";
    self.toggle.toolTip = @"Включить или погасить панель";
    self.toggle.target = self;
    self.toggle.action = @selector(togglePanel:);
    self.toggle.enabled = NO;
    [controller.view addSubview:self.toggle];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(14, 46, 202, 1)];
    separator.boxType = NSBoxSeparator;
    [controller.view addSubview:separator];
    NSButton *quit = [NSButton buttonWithTitle:@"Закрыть приложение" target:self action:@selector(quit:)];
    quit.bordered = NO;
    quit.alignment = NSTextAlignmentLeft;
    quit.frame = NSMakeRect(18, 12, 194, 25);
    [controller.view addSubview:quit];
    self.popover = [NSPopover new];
    self.popover.contentViewController = controller;
    self.popover.contentSize = NSMakeSize(230, 100);
    self.popover.behavior = NSPopoverBehaviorTransient;
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
    self.toggle.state = self.enabled ? NSControlStateValueOn : NSControlStateValueOff;
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

- (void)woke:(NSNotification *)notification {
    (void)notification;
    // Повторяем последний выбор после пробуждения, без постоянного опроса.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self.ready) [self applyEnabled:self.enabled];
    });
}

- (void)showPopover:(id)sender {
    (void)sender;
    if (self.popover.shown) { [self.popover close]; return; }
    [NSApp activateIgnoringOtherApps:YES];
    [self.popover showRelativeToRect:self.statusItem.button.bounds ofView:self.statusItem.button preferredEdge:NSRectEdgeMinY];
}

- (void)showError:(NSString *)message {
    [self.popover close];
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
