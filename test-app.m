// Проверка обработки команд без управления настоящей панелью.
#define main app_entry_for_test
#import "TouchBarApp.m"
#undef main
#include <assert.h>

@interface FakePanel : NSObject
@property BOOL accept;
@property int displayID;
@property int onCalls;
@property int offCalls;
@end
@implementation FakePanel
- (int)getDFRDisplayID { return self.displayID; }
- (BOOL)turnOn { self.onCalls++; return self.accept; }
- (BOOL)turnOff { self.offCalls++; return self.accept; }
@end

@interface TestDelegate : AppDelegate
@property int errors;
@end
@implementation TestDelegate
- (void)showError:(NSString *)message { (void)message; self.errors++; }
@end

int main(void) { @autoreleasepool {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id previous = [defaults objectForKey:@"TouchBarEnabled"];
    TestDelegate *app = [TestDelegate new];
    FakePanel *panel = [FakePanel new];
    panel.displayID = 3;
    panel.accept = YES;
    app.brightnessClient = panel;
    app.ready = YES;
    assert([app applyEnabled:NO]);
    assert(!app.enabled && panel.offCalls == 1 && panel.onCalls == 0);
    assert([app applyEnabled:YES]);
    assert(app.enabled && panel.onCalls == 1 && [defaults boolForKey:@"TouchBarEnabled"]);
    panel.accept = NO;
    assert(![app applyEnabled:NO]);
    assert(app.enabled && app.errors == 1 && [defaults boolForKey:@"TouchBarEnabled"]);
    panel.displayID = 0;
    int calls = panel.offCalls;
    assert(![app applyEnabled:NO]);
    assert(panel.offCalls == calls && app.enabled && app.errors == 2);
    panel.displayID = 3;
    app.ready = NO;
    assert(![app applyEnabled:NO]);
    assert(panel.offCalls == calls && app.errors == 3);
    if (previous) [defaults setObject:previous forKey:@"TouchBarEnabled"];
    else [defaults removeObjectForKey:@"TouchBarEnabled"];
    puts("OK: on/off, отказ API сохраняет выбор, отсутствие панели и неготовность не вызывают команды.");
} return 0; }
