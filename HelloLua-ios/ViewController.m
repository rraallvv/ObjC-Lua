//
//  ViewController.m
//  HelloLua-ios
//
//  Created by Rhody Lugo on 5/20/15.
//  Copyright (c) 2015 Sean Meiners. All rights reserved.
//

#import "ViewController.h"
#import "LuaContext.h"
#import "LuaExport.h"


@protocol UIAlertLuaExport <LuaExport>
+ (instancetype)alloc;
- (instancetype)initWithTitle:(NSString *)title
					  message:(NSString *)message
					 delegate:(id)delegate
			cancelButtonTitle:(NSString *)cancelButtonTitle
			otherButtonTitles:(NSString *)otherButtonTitles, ...;
- (void)show;
@end

@interface UIAlertView (LuaExport) <UIAlertLuaExport>
@end

@implementation UIAlertView (LuaExport)
@end


@interface ViewController ()

@property (weak, nonatomic) IBOutlet UITextView *editorView;
@property (weak, nonatomic) IBOutlet UILabel *resultLabel;
@property (strong) LuaContext *luaContext;
@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.luaContext = [LuaContext new];
	self.luaContext[@"UIAlertView"] = [UIAlertView class];
}

- (IBAction)runScript:(id)sender {
	NSError *error = nil;
	id result = [self.luaContext parse:self.editorView.text error:&error];

	if( error )
		[self.resultLabel setText:[[error userInfo] objectForKey:NSLocalizedDescriptionKey]];
	else if ( result )
		[self.resultLabel setText:[NSString stringWithFormat:@"Succeeded with return value: %@", result]];
	else
		[self.resultLabel setText:@"Succeeded with no return value."];
}

- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}

@end
