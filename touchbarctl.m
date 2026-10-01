#import <Foundation/Foundation.h>
#include <dlfcn.h>
@interface NSObject (TouchBarPrivate)
- (void)scheduleWithDispatchQueue:(dispatch_queue_t)queue;
- (void)unscheduleWithDispatchQueue:(dispatch_queue_t)queue;
- (long long)displayState;
- (long long)getDimmingStep;
- (int)getDFRDisplayID;
- (BOOL)turnOff;
- (BOOL)turnOn;
@end
int main(int argc, const char *argv[]) { @autoreleasepool {
 if(argc!=2 || (strcmp(argv[1],"status") && strcmp(argv[1],"off") && strcmp(argv[1],"on"))) { fprintf(stderr,"Использование: touchbarctl status|off|on\n"); return 2; }
 void *handle=dlopen("/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness",RTLD_NOW|RTLD_LOCAL);
 if(!handle) { fprintf(stderr,"DFRBrightness недоступен\n"); return 1; }
 Class cls=NSClassFromString(@"DFRBrightnessClient");
 if(!cls) { fprintf(stderr,"DFRBrightnessClient недоступен\n"); return 1; }
 id client=[[cls alloc] init];
 for(NSString *name in @[@"scheduleWithDispatchQueue:",@"displayState",@"getDimmingStep",@"getDFRDisplayID",@"turnOff",@"turnOn",@"unscheduleWithDispatchQueue:"]) {
  if(![client respondsToSelector:NSSelectorFromString(name)]) { fprintf(stderr,"Несовместимый API\n"); return 1; }
 }
 [client scheduleWithDispatchQueue:dispatch_get_main_queue()];
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
 int displayID=[client getDFRDisplayID];
 if(displayID<=0) { fprintf(stderr,"Дисплей Touch Bar не найден\n"); [client unscheduleWithDispatchQueue:dispatch_get_main_queue()]; return 1; }
 printf("До: displayID=%d state=%lld dimmingStep=%lld\n",displayID,[client displayState],[client getDimmingStep]);
 BOOL ok=YES;
 if(!strcmp(argv[1],"off")) ok=[client turnOff];
 if(!strcmp(argv[1],"on")) ok=[client turnOn];
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
 printf("Команда API=%s; после: state=%lld dimmingStep=%lld\n",ok?"принята":"отклонена",[client displayState],[client getDimmingStep]);
 [client unscheduleWithDispatchQueue:dispatch_get_main_queue()];
 return ok?0:1;
} }
