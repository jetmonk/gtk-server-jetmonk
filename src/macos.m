/*
 * MacOSX specific functions for the GTK-server.
 *
 * Only compiled on MacOSX, for the GTK3 and GTK4 backends, which run on AppKit.
 * configure adds this file and the AppKit framework to the build.
 *
 * This file is part of the GTK-server and released under the GNU General Public
 * License, version 2 or (at your option) any later version.
 */

#import <AppKit/AppKit.h>

/* Set the icon in the Dock. A program which is not inside an application bundle
 * gets the generic executable icon. The file can be any image format NSImage
 * reads: PNG, JPEG, TIFF, ICNS, PDF and so on. Returns 1 if the icon was set,
 * 0 if the file could not be read. */
int gtk_server_macos_icon(const char *file)
{
    @autoreleasepool {
        NSImage *image;

        if (file == NULL) return 0;
        image = [[NSImage alloc] initWithContentsOfFile:[NSString stringWithUTF8String:file]];
        if (image == nil) return 0;
        /* The application keeps its own reference to the icon */
        [[NSApplication sharedApplication] setApplicationIconImage:image];
        [image release];
    }
    return 1;
}

/* Full screen. GTK4 on macOS cannot take a window out of full screen again: the title bar
 * with its buttons does not come back. Without full screen, the green button of a window
 * zooms it instead, which GTK handles. Windows are set when this is called, and new ones
 * as the application updates, since GTK creates them later. */

static BOOL allow_full_screen = YES;
static id full_screen_observer = nil;

static void Set_Full_Screen(NSWindow *window)
{
    NSWindowCollectionBehavior old = [window collectionBehavior];
    NSWindowCollectionBehavior new = old & ~(NSWindowCollectionBehaviorFullScreenPrimary
                                            | NSWindowCollectionBehaviorFullScreenAuxiliary
                                            | NSWindowCollectionBehaviorFullScreenNone);

    if (allow_full_screen) {
        /* Back to what GTK sets: full screen for windows with a title bar */
        if ([window styleMask] & NSWindowStyleMaskTitled) new |= NSWindowCollectionBehaviorFullScreenPrimary;
        else new = old & ~NSWindowCollectionBehaviorFullScreenNone;
    }
    else new |= NSWindowCollectionBehaviorFullScreenNone;
    if (new != old) [window setCollectionBehavior:new];
}

/* Allow full screen (1) or not (0). Returns 1. */
int gtk_server_macos_full_screen(int allow)
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];

        allow_full_screen = allow ? YES : NO;
        for (NSWindow *window in [app windows]) Set_Full_Screen(window);
        if (full_screen_observer == nil) {
            full_screen_observer = [[NSNotificationCenter defaultCenter]
                addObserverForName:NSApplicationDidUpdateNotification object:app queue:nil
                        usingBlock:^(NSNotification *note) {
                            (void)note;
                            if (!allow_full_screen)
                                for (NSWindow *window in [[NSApplication sharedApplication] windows]) Set_Full_Screen(window);
                        }];
            [full_screen_observer retain];
        }
    }
    return 1;
}

/* Light and dark appearance. GTK does not follow the system's appearance on macOS by
 * itself. gtk_server_macos_appearance gives a function, which is called with 1 for dark
 * and 0 for light at once and whenever the appearance changes; NULL stops that. */

static void (*appearance_changed)(int dark) = NULL;
static id appearance_observer = nil;

static int Is_Dark(void)
{
    NSAppearanceName name = [[[NSApplication sharedApplication] effectiveAppearance]
                                bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [name isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
}

@interface GtkServerAppearanceObserver : NSObject
@end

@implementation GtkServerAppearanceObserver
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    (void)path; (void)object; (void)change; (void)context;
    if (appearance_changed) appearance_changed(Is_Dark());
}
@end

/* Returns 1 if the appearance is dark now, otherwise 0. */
int gtk_server_macos_appearance(void (*changed)(int dark))
{
    @autoreleasepool {
        appearance_changed = changed;
        if (changed != NULL && appearance_observer == nil) {
            appearance_observer = [[GtkServerAppearanceObserver alloc] init];
            [[NSApplication sharedApplication] addObserver:appearance_observer forKeyPath:@"effectiveAppearance"
                                                   options:0 context:NULL];
        }
        if (changed != NULL) changed(Is_Dark());
        return Is_Dark();
    }
}
