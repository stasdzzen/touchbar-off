#import <Cocoa/Cocoa.h>

static void render(NSString *path, int pixels, BOOL menu) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixels pixelsHigh:menu ? pixels * 18 / 20 : pixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
    NSAffineTransform *scale = [NSAffineTransform transform];
    [scale scaleBy:pixels / (menu ? 20.0 : 1024.0)];
    [scale concat];
    if (menu) {
        [[NSColor blackColor] setStroke];
        NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1,4,18,10) xRadius:3 yRadius:3];
        frame.lineWidth = 1.4; [frame stroke];
        NSBezierPath *power = [NSBezierPath bezierPath];
        [power appendBezierPathWithArcWithCenter:NSMakePoint(10,8.4) radius:3 startAngle:120 endAngle:420 clockwise:NO];
        [power moveToPoint:NSMakePoint(10,12.2)]; [power lineToPoint:NSMakePoint(10,9.3)];
        power.lineWidth = 1.3; power.lineCapStyle = NSLineCapStyleRound; [power stroke];
    } else {
        NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(64,64,896,896) xRadius:208 yRadius:208];
        NSColor *light = [NSColor colorWithSRGBRed:128/255.0 green:102/255.0 blue:244/255.0 alpha:1];
        NSColor *dark = [NSColor colorWithSRGBRed:67/255.0 green:50/255.0 blue:163/255.0 alpha:1];
        [[[NSGradient alloc] initWithStartingColor:light endingColor:dark] drawInBezierPath:tile angle:-45];
        NSBezierPath *frame = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(176,368,672,288) xRadius:104 yRadius:104];
        [[NSColor colorWithSRGBRed:33/255.0 green:23/255.0 blue:77/255.0 alpha:.42] setFill]; [frame fill];
        [[NSColor colorWithWhite:1 alpha:.9] setStroke]; frame.lineWidth=24; [frame stroke];
        [[NSColor whiteColor] setStroke];
        NSBezierPath *power = [NSBezierPath bezierPath];
        [power appendBezierPathWithArcWithCenter:NSMakePoint(512,497.7) radius:88 startAngle:118.5 endAngle:421.5 clockwise:NO];
        [power moveToPoint:NSMakePoint(512,613)]; [power lineToPoint:NSMakePoint(512,525)];
        power.lineWidth=28; power.lineCapStyle=NSLineCapStyleRound; [power stroke];
        [[NSColor colorWithWhite:1 alpha:.6] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(278,496,32,32)] fill];
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(714,496,32,32)] fill];
    }
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![png writeToFile:path atomically:YES]) { fprintf(stderr,"Не удалось записать PNG\n"); exit(1); }
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc != 2) return 2;
    NSString *output = [NSString stringWithUTF8String:argv[1]];
    NSString *set = [output stringByAppendingPathComponent:@"AppIcon.iconset"];
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:set withIntermediateDirectories:YES attributes:nil error:&error]) { NSLog(@"%@",error); return 1; }
    for (NSNumber *value in @[@16,@32,@128,@256,@512]) {
        int n = value.intValue;
        render([set stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%dx%d.png",n,n]],n,NO);
        render([set stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%dx%d@2x.png",n,n]],n*2,NO);
    }
    render([output stringByAppendingPathComponent:@"MenuIcon.png"],20,YES);
    render([output stringByAppendingPathComponent:@"MenuIcon@2x.png"],40,YES);
    render([output stringByAppendingPathComponent:@"AppIcon.png"],1024,NO);
} return 0; }
