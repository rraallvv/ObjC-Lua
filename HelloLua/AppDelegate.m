//
//  AppDelegate.m
//  HelloLua
//
//  Created by Rhody Lugo on 5/19/15.
//  Copyright (c) 2015 Sean Meiners. All rights reserved.
//

#import "AppDelegate.h"
#import "LuaContext.h"
#import "LuaExport.h"


@protocol NSAlertLuaExport <LuaExport>
@property (copy) NSString *messageText;
@property (copy) NSString *informativeText;
+ (instancetype)alloc;
- (instancetype)init;
- (NSModalResponse)runModal;
@end

@interface NSAlert (LuaExport) <NSAlertLuaExport>
@end

@implementation NSAlert (LuaExport)
@end


@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (unsafe_unretained) IBOutlet NSTextView *editorView;
@property (weak) IBOutlet NSTextField *resultLabel;
@property (strong) LuaContext *luaContext;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[self.editorView setAutomaticDashSubstitutionEnabled:NO];
	self.luaContext = [LuaContext new];
	self.luaContext[@"NSAlert"] = [NSAlert class];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {

}

- (IBAction)runScript:(id)sender {
	NSError *error = nil;
	id result = [self.luaContext parse:self.editorView.string error:&error];

	if( error )
		[self.resultLabel setStringValue:[[error userInfo] objectForKey:NSLocalizedDescriptionKey]];
	else if ( result )
		[self.resultLabel setStringValue:[NSString stringWithFormat:@"Succeeded with return value: %@", result]];
	else
		[self.resultLabel setStringValue:@"Succeeded with no return value."];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	return YES;
}

@end
