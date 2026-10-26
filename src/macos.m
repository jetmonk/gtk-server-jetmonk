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
