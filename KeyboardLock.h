// Copyright (c) 2026 Dzzen.com. SPDX-License-Identifier: MIT
#import <Cocoa/Cocoa.h>

typedef CGEventRef (^TBKeyboardEventHandler)(CGEventType type, CGEventRef event);

// Тесты подставляют backend: реальное разрешение и event tap не вызываются.
@protocol TBKeyboardBackend <NSObject>
- (BOOL)requestAccessibility;
- (BOOL)startWithHandler:(TBKeyboardEventHandler)handler;
- (BOOL)isEnabled;
- (void)stop;
@end

@interface TBKeyboardLock : NSObject
@property (nonatomic, readonly, getter=isLocked) BOOL locked;
@property (nonatomic, readonly, copy) NSString *status;
@property (nonatomic, copy) void (^stateChanged)(void);
- (instancetype)initWithBackend:(id<TBKeyboardBackend>)backend;
- (BOOL)lock;
- (void)unlock;
- (void)unlockWithStatus:(NSString *)status;
- (CGEventRef)handleEvent:(CGEventRef)event type:(CGEventType)type;
@end

@interface TBSystemKeyboardBackend : NSObject <TBKeyboardBackend>
@end
