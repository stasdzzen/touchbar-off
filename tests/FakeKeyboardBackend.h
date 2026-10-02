// Подставной backend для тестов: никаких разрешений и системного event tap.
#import "../KeyboardLock.h"

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

