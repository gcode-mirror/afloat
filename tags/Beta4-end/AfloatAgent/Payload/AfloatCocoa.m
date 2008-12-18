/*

Copyright © 2006, Emanuele Vulcano.

This file is part of Afloat.

    Afloat is free software; you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the Free Software Foundation; either version 2.1 of the License, or (at your option) any later version.

    Afloat is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License along with Afloat; if not, write to the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301  USA

*/

#import "AfloatAgentCommunication.h"
#import "AfloatLogging.h"
#import "AfloatCocoa.h"

#import <objc/objc-class.h>
#import "AfloatHub.h"
#import "AfloatCocoaWindowTracking.h"
#import "AfloatPreferences.h"

#define kAfloatCocoaUserAlphaValue @"AfloatCocoaUserAlphaValue"

#import <stdlib.h>

@implementation AfloatCocoa

static NSMutableSet* swizzledMethods = nil;

// From SIMBL's creator, ...
- (BOOL) renameSelector:(SEL) select ofClass:(Class) cls toNewSelector:(SEL) newSel {
	if (!swizzledMethods)
		swizzledMethods = [NSMutableSet new];
	NSString* methodName = [NSString stringWithFormat:@"-[%@ %@]", NSStringFromClass(cls), NSStringFromSelector(select)];
	
	if ([swizzledMethods containsObject:methodName]) {
		[self tellUserAndCrashWithReason:
			NSLocalizedString(@"Afloat tried to modify the same piece of the target application twice.", @"Afloat swizzled the same method twice.")
			];
	}
	
    Method method = nil;
	
    method = class_getInstanceMethod(cls, select);
    if (method == nil)
        return NO;
	
    method->method_name = newSel;
	[swizzledMethods addObject:methodName];
	
    return YES;
}

- (BOOL) bypassSelector:(SEL) original ofClass:(Class) cls throughNewSelector:(SEL) newSel keepOriginalAs:(SEL) kept {
	BOOL res = [self renameSelector:original ofClass:cls toNewSelector:kept];
	if (res)
		res = [self renameSelector:newSel ofClass:cls toNewSelector:original];
	
	return res;
}

- (void) performInstallOnMainThread {
	if (NSClassFromString(@"ASKWindow")) {
		// we're in an AppleScript Studio app
		AfloatLog(@"This is an AppleScript Studio application; Afloat won't load in it.");
		return;
	}
	
	[self performSelectorOnMainThread:@selector(prepareInstall) withObject:nil waitUntilDone:NO];
}

- (void) tellUserAndCrashWithReason:(NSString*) reason {
	NSLog(@"Afloat encountered a bug and will stop the current application: %@");
	NSAlert* alert = [NSAlert new];
	
	[alert setMessageText:
		NSLocalizedString(@"Afloat has encountered an internal problem. The application it was being executed in will now quit unexpectedly. Please report this to afloat@infinite-labs.net rather than the application's developer.", @"Afloat is going to crash.")
		];
	
	[alert setInformativeText:reason];
	
	[alert runModal];
	[alert release];
	(*((char*)NULL)) = '0'; // ensures we crash.	
	abort();
}

- (void) prepareInstall {
	AfloatLog(@"Preparing to install Afloat...");
	[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(delayedInstall:) userInfo:nil repeats:NO];
}

- (void) delayedInstall:(NSTimer*) t {
	[self install];
}

- (void) install {
	static BOOL wasInstalled = NO;
	if (wasInstalled) {
		[self tellUserAndCrashWithReason:
			NSLocalizedString(@"Afloat tried to install itself twice in the target application.", @"Afloat got -install twice.")
			];
	}
	
    // sink with "-"
	[self bypassSelector:@selector(miniaturize:) ofClass:[NSWindow class] throughNewSelector:@selector(afloatMiniaturize:) keepOriginalAs:@selector(afloatMiniaturizeOriginal:)];

    // install Drag Anywhere
    
    [self bypassSelector:@selector(sendEvent:) ofClass:[NSApplication class] throughNewSelector:@selector(afloatSendEvent:) keepOriginalAs:@selector(afloatSendEventOriginal:)];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeFocusedWindow:) name:NSWindowDidBecomeMainNotification object:nil];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(willCloseWindow:) name:NSWindowWillCloseNotification object:nil];
    	
	// install menu items
	
	NSMenu* mainMenu = [NSApp mainMenu], * items = [[AfloatHub sharedHub] afloatMenu];
	@try {
		[self searchAndInstallMenuItems:items inAppropriateMenuIn:mainMenu];
	} @catch (NSException* ex) {
		AfloatLog(@"An exception was raised while installing Afloat's menu items: %@", ex);
		return;
	}
	
	[[AfloatHub sharedHub] setFocusedWindow:[self focusedWindow]];
	AfloatLog(@"Afloat installed.");
}

- (BOOL) searchAndInstallMenuItems:(NSMenu*) items inAppropriateMenuIn:(NSMenu*) menu {
	NSEnumerator* enu = [[menu itemArray] objectEnumerator];
	int i = -1;
	NSMenuItem* item;
	
	while (item = [enu nextObject]) {
		i++;
		if ([item action] == @selector(performMiniaturize:)) {
			[self installMenuItems:items inMenu:menu index:i];
			return YES;
		}
		
		if ([item hasSubmenu]) {
			if ([self searchAndInstallMenuItems:items inAppropriateMenuIn:[item submenu]])
				return YES;
		}
	}
	
	return NO;
}

- (void) installMenuItems:(NSMenu*) items inMenu:(NSMenu*) menu index:(int) i {
	NSMenuItem* newItem = [[NSMenuItem alloc] initWithTitle:@"Afloat" action:nil keyEquivalent:@""];
	
	[menu insertItem:newItem atIndex:i];
	[menu setSubmenu:items forItem:newItem];
	
	[newItem release];
}

- (void) didChangeFocusedWindow:(NSNotification*) notif {
	[[AfloatHub sharedHub] setFocusedWindow:[notif object]];
}

- (void) willCloseWindow:(NSNotification*) notif {
	[[AfloatHub sharedHub] willRemoveWindow:[notif object]];
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (NSArray*) windows {
	NSEnumerator* enu = [[NSApp windows] objectEnumerator];
	NSWindow* wnd;
	NSMutableSet* topWindows = [NSMutableSet set];
	
	while (wnd = [enu nextObject]) {
		if ([wnd isKindOfClass:[NSPanel class]] || [wnd styleMask] & NSBorderlessWindowMask)
			continue;
		
		id atp = [wnd afloatTopWindow];
		if (atp) [topWindows addObject:[wnd afloatTopWindow]];
	}
	
	return [topWindows allObjects];
}

- (id) focusedWindow {
	return [[self windows] objectAtIndex:0];
}

- (void) deactivateApplication {
//	[[NSApplication sharedApplication] hide:self];
}

@end

@implementation NSWindow (AfloatCocoaAdditions)

- (void) afloatMiniaturize:(id) sender {
    if ([[AfloatPreferences sharedInstance] shouldUseSinkRatherThanMinimize])
        [[AfloatHub sharedHub] sinkWindow:self];
    else
        [self afloatMiniaturizeOriginal:sender];
}

- (float) userAlphaValue {
    NSNumber* n = [[[AfloatHub sharedHub] infoForWindow:self] objectForKey:kAfloatCocoaUserAlphaValue];
    if (n) return [n floatValue];
    
    return [self alphaValue];
}

- (void) setUserAlphaValue:(float) uav {
    [[[AfloatHub sharedHub] infoForWindow:self] setObject:[NSNumber numberWithFloat:uav] forKey:kAfloatCocoaUserAlphaValue];
    [self setAlphaValue:uav];
    [[AfloatHub sharedHub] changedUserAlpha:uav forWindow:self];
}

- (BOOL) overlayWindow {
	return [self ignoresMouseEvents];
}

- (void) setOverlayWindow:(BOOL) overlay {
	if (overlay) {
		[self setIgnoresMouseEvents:YES];
		if ([self userAlphaValue] == 1.0) [self setUserAlphaValue:[[AfloatHub sharedHub] adequateOverlayAlphaValue]];
		[self setAlwaysOnTop:YES];
	} else {
		[self setIgnoresMouseEvents:NO];
		if ([self userAlphaValue] == [[AfloatHub sharedHub] adequateOverlayAlphaValue]) [self setUserAlphaValue:1.0];
		[self setAlwaysOnTop:NO];
	}
}

- (id) afloatTopWindow {
	NSWindow* me = self;
	while ([me parentWindow])
		me = [me parentWindow];
		
	return me;
}

- (BOOL) alwaysOnTop {
	return [self level] == NSFloatingWindowLevel;
}

- (void) setAlwaysOnTop:(BOOL) onTop {
	[self setLevel:(onTop? NSFloatingWindowLevel : NSNormalWindowLevel)];
}


- (id) beginMouseTrackingWithOwner:(id) owner {
	return [[[AfloatCocoaWindowTracking alloc] initForWindow:self owner:owner] autorelease];
}

@end

// Drag Anywhere and Scroll to Set Transparency code

@implementation NSApplication (AfloatCocoaAdditions)

- (void) afloatSendEvent:(NSEvent*) evt {
    // bad hack: since we're going to support 10.3.9, and
    // we cannot do so while still using NSDeviceIndependentModifierFlagsMask,
    // we copy its value here. Since it's an enum, it's not terribly
    // important. Still.
    // This should do nothing to pre-10.4 events.
    
    unsigned int mods = [evt modifierFlags] & /* NSDeviceIndependentModifierFlagsMask */ 0xffff0000U;
    NSPoint ori;
    AfloatHub* hub = [AfloatHub sharedHub]; id wnd; float oldAlpha;
	
    if (mods == (NSCommandKeyMask | NSControlKeyMask)) {
        
        switch ([evt type]) {
            case NSLeftMouseDown:
                return; // filter it
                
            case NSLeftMouseDragged:
                if (!(wnd = [hub focusedWindow])) return;
                    
                ori = [[hub focusedWindow] frame].origin;
                ori.x += [evt deltaX];
                ori.y -= [evt deltaY];
                [[hub focusedWindow] setFrameOrigin:ori];
                return; // filter it once done
                
            case NSLeftMouseUp:
                return; // filter it
                
            case NSScrollWheel:
                oldAlpha = [[hub focusedWindow] alphaValue];
                [[hub focusedWindow] setAlphaValue:
                    [hub normalizedAlphaValueForValue:oldAlpha + [evt deltaY] * 0.10]];
                //NSRunAlertPanel(@"Opacita'",[NSString stringWithFormat:@"%f", [evt deltaY]],nil,nil,nil);
                return; // filter it
				
			// command-click to allow overlay window manipulation.
			case NSFlagsChanged:
				[hub beginTemporaryTrackingOfOverlays];
				break; // we don't filter this event, merely add to it.
        }
        
    } else if ([hub isTemporarilyTrackingOverlays] && [evt type] == NSFlagsChanged) {
		[hub endTemporaryTrackingOfOverlays];
		// we don't filter this event, merely add to it.
	}
    
    // If we didn't return above, we return the event to its
    // regular code path.
    [self afloatSendEventOriginal:evt];
	
	// "de-sinking"
	if ([evt type] == NSLeftMouseDown) {
		[[AfloatHub sharedHub] setFocusedWindow:
			[[AfloatCocoa sharedInstance] focusedWindow]];
	}
}

@end