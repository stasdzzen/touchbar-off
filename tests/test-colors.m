// Проверка реально отрисованных пикселей без управления Touch Bar.
#define main app_entry_for_color_test
#import "../TouchBarApp.m"
#undef main
#include <assert.h>

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    TBStateButton *button = [[TBStateButton alloc] initWithFrame:NSMakeRect(0,0,190,30)];
    button.enabled = YES;
    for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
        [[NSAppearance appearanceNamed:appearance] performAsCurrentDrawingAppearance:^{
            for (int state = 0; state < 2; state++) {
                button.panelEnabled = state;
                button.title = state ? @"Touch Bar включён" : @"Touch Bar выключен";
                NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:380 pixelsHigh:60 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
                [NSGraphicsContext saveGraphicsState];
                [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
                NSAffineTransform *scale = [NSAffineTransform transform];
                [scale scaleBy:2]; [scale concat];
                [button drawRect:button.bounds];
                [NSGraphicsContext restoreGraphicsState];
                NSColor *pixel = [[bitmap colorAtX:20 y:30] colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                assert(pixel.alphaComponent > .99);
                if (state) assert(pixel.greenComponent > pixel.redComponent * 2);
                else assert(pixel.redComponent > pixel.greenComponent * 2);
                NSString *file = [NSString stringWithFormat:@"build/tests/button-%@-%@.png",appearance,state ? @"on" : @"off"];
                assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:file atomically:YES]);
            }
        }];
    }
    puts("OK: красные/зелёные пиксели фона в светлом и тёмном оформлении.");
} return 0; }
