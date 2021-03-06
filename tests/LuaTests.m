#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <XCTest/XCTest.h>
#import <JavaScriptCore/JavaScriptCore.h>

#import "LuaContext.h"
#import "LuaExport.h"

#if TARGET_OS_IPHONE

@interface NSValue (CGAddons)

+ (NSValue *)valueWithPoint:(CGPoint)point;
- (CGPoint)pointValue;

+ (NSValue *)valueWithSize:(CGSize)size;
- (CGSize)sizeValue;

+ (NSValue *)valueWithRect:(CGRect)rect;
- (CGRect)rectValue;

@end

@implementation NSValue (CGAddons)

+ (NSValue *)valueWithPoint:(CGPoint)point {
	return [NSValue valueWithBytes:&point objCType:@encode(CGPoint)];
}

- (CGPoint)pointValue {
	if( strcmp(@encode(CGPoint), self.objCType) )
		return CGPointZero;
	CGPoint point;
	[self getValue:&point];
	return point;
}

+ (NSValue *)valueWithSize:(CGSize)size {
	return [NSValue valueWithBytes:&size objCType:@encode(CGSize)];
}

- (CGSize)sizeValue {
	if( strcmp(@encode(CGSize), self.objCType) )
		return CGSizeZero;
	CGSize size;
	[self getValue:&size];
	return size;
}

+ (NSValue *)valueWithRect:(CGRect)rect {
	return [NSValue valueWithBytes:&rect objCType:@encode(CGRect)];
}

- (CGRect)rectValue {
	if( strcmp(@encode(CGRect), self.objCType) )
		return CGRectZero;
	CGRect rect;
	[self getValue:&rect];
	return rect;
}

@end

#endif

static inline BOOL compareFloatsEpsilon(float a, float b) {
	return fabs(a - b) < __FLT_EPSILON__;
}

@interface ExportObject : NSObject

@property (nonatomic, strong) NSString *privateString;
@property (nonatomic, strong) NSString *publicString;

@property (nonatomic, assign) CGFloat floatProperty;

@property (nonatomic, assign) BOOL silence;

- (NSString*)privateMethod;
- (NSString*)publicMethod;

- (void)voidTakesString:(NSString*)str andNumber:(NSNumber*)num;
- (CGRect)rectTakesArray:(NSArray*)arr andRect:(CGRect)rect;
- (CGFloat)floatTakesNothing;
- (CGAffineTransform)transformTakesTransform:(CGAffineTransform)transform andFloat:(CGFloat)fl;
- (NSArray*)transformTakesArray:(NSArray*)transform andFloat:(CGFloat)fl;

- (CATransform3D)passThroughMatrix:(CATransform3D)matrix;

- (NSString *)runBlock:(NSString *(^)(NSString *))block;

@end

@interface InheritedExportObject : ExportObject


@property (nonatomic, strong) NSString *privateString2;
@property (nonatomic, strong) NSString *publicString2;

- (NSString*)privateMethod2;
- (NSString*)publicMethod2;

@end

@interface InheritedPrivateObject : InheritedExportObject


@property (nonatomic, strong) NSString *privateString3;

- (NSString*)privateMethod3;

@end

static inline NSString *StringFromCGRect(const CGRect rect) {
	return [NSString stringWithFormat:@"{ { %f x %f }, { %f x %f } }",
			rect.origin.x, rect.origin.y, rect.size.width, rect.size.height ];
}

static inline NSString *StringFromCGAffineTransform(const CGAffineTransform xform) {
	return [NSString stringWithFormat:@"{ { %f, %f }, { %f, %f }, { %f, %f } }",
			xform.a, xform.b, xform.c, xform.d, xform.tx, xform.ty];
}

static inline NSString *StringFromCATransform3D(const CATransform3D xform) {
	return [NSString stringWithFormat:@"{ { %f, %f, %f, %f }, { %f, %f, %f, %f }, { %f, %f, %f, %f }, { %f, %f, %f, %f } }",
			xform.m11, xform.m12, xform.m13, xform.m14,
			xform.m21, xform.m22, xform.m23, xform.m24,
			xform.m31, xform.m32, xform.m33, xform.m34,
			xform.m41, xform.m42, xform.m43, xform.m44 ];
}

@implementation ExportObject

- (id)init {
	if( (self = [super init]) ) {
		_privateString = @"privateStr";
		_publicString = @"publicStr";
	}
	return self;
}

- (NSString*)privateMethod {
	if( ! _silence )
		NSLog(@"private method called");
	return @"private method";
}

- (NSString*)publicMethod {
	if( ! _silence )
		NSLog(@"public method called");
	return @"public method";
}

- (void)voidTakesString:(NSString*)str andNumber:(NSNumber*)num {
	NSLog(@"%@ got: '%@' '%@'", NSStringFromSelector(_cmd), [str description], [num description]);
}

- (CGRect)rectTakesArray:(NSArray*)arr andRect:(CGRect)rect {
	NSLog(@"%@ got: '%@' '%@'", NSStringFromSelector(_cmd), [arr description], StringFromCGRect(rect));
	if( [arr count] == 4 )
		return CGRectMake([arr[0] floatValue], [arr[1] floatValue], [arr[2] floatValue], [arr[3] floatValue]);
	return rect;
}

- (CGFloat)floatTakesNothing {
	NSLog(@"%@ got: _", NSStringFromSelector(_cmd));
	return M_2_PI;
}

- (CGAffineTransform)transformTakesTransform:(CGAffineTransform)transform andFloat:(CGFloat)fl {
	NSLog(@"%@ got: '%@' '%f'", NSStringFromSelector(_cmd), StringFromCGAffineTransform(transform), fl);
	return CGAffineTransformRotate(transform, fl);
}

static inline CGAffineTransform CGAffineTransformFromArray(NSArray *transform) {
	if( [transform count] == 6 ) {
		CGAffineTransform xform = {
			[transform[0] floatValue], [transform[1] floatValue],
			[transform[2] floatValue], [transform[3] floatValue],
			[transform[4] floatValue], [transform[5] floatValue] };
		return xform;
	}
	return CGAffineTransformIdentity;
}

static inline CATransform3D CATransform3DFromArray(NSArray *transform) {
	if( [transform count] == 16 ) {
		CATransform3D xform = {
			[transform[0] floatValue], [transform[1] floatValue], [transform[2] floatValue], [transform[3] floatValue],
			[transform[4] floatValue], [transform[5] floatValue], [transform[6] floatValue], [transform[7] floatValue],
			[transform[8] floatValue], [transform[9] floatValue], [transform[10] floatValue], [transform[11] floatValue],
			[transform[12] floatValue], [transform[13] floatValue], [transform[14] floatValue], [transform[15] floatValue] };
		return xform;
	}
	return CATransform3DIdentity;
}

static inline NSArray* arrayFromCGAffineTransform(const CGAffineTransform xform) {
	return @[ @(xform.a), @(xform.b), @(xform.c), @(xform.d), @(xform.tx), @(xform.ty) ];
}

- (NSArray*)transformTakesArray:(NSArray*)transform andFloat:(CGFloat)fl {
	NSLog(@"%@ got: '%@' '%f'", NSStringFromSelector(_cmd), transform, fl);
	CGAffineTransform xform = CGAffineTransformFromArray(transform);
	xform = CGAffineTransformRotate(xform, fl);
	return arrayFromCGAffineTransform(xform);
}

- (CATransform3D)passThroughMatrix:(CATransform3D)matrix {
	NSLog(@"%@ got: '%@'", NSStringFromSelector(_cmd), StringFromCATransform3D(matrix));
	return matrix;
}

- (NSString *)runBlock:(NSString *(^)(NSString *))block {
    return block(self.privateString);
}

- (void)dealloc {
    //NSLog(@"dealloc");
}

@end

@implementation InheritedExportObject

- (id)init {
	if( (self = [super init]) ) {
		_privateString2 = @"privateStr2";
		_publicString2 = @"publicStr2";
	}
	return self;
}

- (NSString*)privateMethod2 {
	if( ! self.silence )
		NSLog(@"private method 2 called");
	return @"private method 2";
}

- (NSString*)publicMethod2 {
	if( ! self.silence )
		NSLog(@"public method 2 called");
	return @"public method 2";
}

@end

@implementation InheritedPrivateObject

- (id)init {
	if( (self = [super init]) ) {
		_privateString3 = @"privateStr3";
	}
	return self;
}

- (NSString*)privateMethod3 {
	if( ! self.silence )
		NSLog(@"private method 3 called");
	return @"private method 3";
}

@end

@protocol ExportObjectExports <LuaExport>

@property (nonatomic, strong) NSString *publicString;

@property (nonatomic, assign) CGFloat floatProperty;

+ (instancetype)alloc;
- (id)init;

- (NSString*)publicMethod;

- (void)voidTakesString:(NSString*)str andNumber:(NSNumber*)num;
- (CGRect)rectTakesArray:(NSArray*)arr andRect:(CGRect)rect;
- (CGFloat)floatTakesNothing;
- (CGAffineTransform)transformTakesTransform:(CGAffineTransform)transform andFloat:(CGFloat)fl;
- (NSArray*)transformTakesArray:(NSArray*)transform andFloat:(CGFloat)fl;

- (CATransform3D)passThroughMatrix:(CATransform3D)matrix;

- (NSString *)runBlock:(NSString *(^)(NSString *))block;

@end

@interface ExportObject (Exports) <ExportObjectExports>
@end
@implementation ExportObject (Exports)
@end

@protocol InheritedExportObjectExports <LuaExport>

@property (nonatomic, strong) NSString *publicString2;

- (NSString*)publicMethod2;

@end

@interface InheritedExportObject (Exports) <InheritedExportObjectExports>
@end
@implementation InheritedExportObject (Exports)
@end

@interface LuaTests : XCTestCase
@end

@implementation LuaTests

- (void)testSandbox {
	LuaContext *ctx1 = [LuaContext new];

	NSError *error = nil;

	id result;

	ExportObject *obj = [ExportObject new];

	ctx1[@"exObject"] = obj;
	result = [ctx1 parse:@"return exObject" error:&error];
	NSLog(@"export object to context #1 result: %@ error: %@", result, error);
	XCTAssert( ! error, @"failed to load script: %@", error);
	XCTAssert( [result isEqual:obj], @"result is wrong");

	LuaContext *ctx2 = [[LuaContext alloc] initWithVirtualMachine:ctx1.virtualMachine];

	result = [ctx2 parse:@"return exObject" error:&error];
	NSLog(@"retrieve object from context #2 result: %@ error: %@", result, error);
	XCTAssert( ! error, @"failed to load script: %@", error);
	XCTAssert( result == nil, @"result is wrong");

	ctx2[@"exObject"] = ctx1[@"exObject"];
	result = [ctx2 parse:@"return exObject" error:&error];
	NSLog(@"copy object from context #1 to context #2 result: %@ error: %@", result, error);
	XCTAssert( ! error, @"failed to load script: %@", error);
	XCTAssert( [result isEqual:obj], @"result is wrong");

	[ctx2 parse:@"exObject = nil" error:&error];
	result = ctx2[@"exObject"];
	NSLog(@"nil object in context #2 result: %@ error: %@", result, error);
	XCTAssert( ! error, @"failed to load script: %@", error);
	XCTAssert( result == nil, @"result is wrong");

	result = ctx1[@"exObject"];
	NSLog(@"retrieve object from context #1 result: %@ error: %@", result, error);
	XCTAssert( ! error, @"failed to load script: %@", error);
	XCTAssert( [result isEqual:obj], @"result is wrong");
}

- (void)testValue {
    LuaContext *ctx = [LuaContext new];

	NSError *error = nil;

    NSString *script = @"function say (n) print(n) return x end";
    [ctx parse:script error:&error];
    XCTAssert( ! error, @"failed to load script: %@", error);

	id result;

    ctx[@"x"] = @5;
    XCTAssert( [ctx[@"x"] intValue] == 5, @"x != 5");
    result = [ctx call:@"say" with:@[ @"test int" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result intValue] == 5, @"result != 5");

    ctx[@"x"] = @YES;
    XCTAssert( [ctx[@"x"] boolValue] == YES, @"x != YES");
    result = [ctx call:@"say" with:@[ @"test bool" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result boolValue] == YES, @"result != YES");

    ctx[@"x"] = @NO;
    XCTAssert( [ctx[@"x"] boolValue] == NO, @"x != NO");
    result = [ctx call:@"say" with:@[ @"test bool" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result boolValue] == NO, @"result != NO");

    ctx[@"x"] = @M_PI;
    XCTAssert( [ctx[@"x"] doubleValue] == M_PI, @"x != Pi");
    result = [ctx call:@"say" with:@[ @"test float" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result doubleValue] == M_PI, @"result != Pi");

    ctx[@"x"] = @"string";
    XCTAssert( [ctx[@"x"] isEqualToString:@"string"], @"x != 'string'");
    result = [ctx call:@"say" with:@[ @"test string" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result isEqualToString:@"string"], @"result != 'string'");

    ctx[@"x"] = @[ @3, @2, @1 ];
    XCTAssert( [ctx[@"x"][0] intValue] == 3 && [ctx[@"x"][1] intValue] == 2 && [ctx[@"x"][2] intValue] == 1, @"x != [3, 2, 1]");
    result = [ctx call:@"say" with:@[ @"test array" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result[0] intValue] == 3 && [result[1] intValue] == 2 && [result[2] intValue] == 1, @"result != [3, 2, 1]");

    ctx[@"x"] = @{ @"a": @3, @"b": @2, @"c": @1 };
    XCTAssert( [ctx[@"x"][@"a"] intValue] == 3 && [ctx[@"x"][@"b"] intValue] == 2 && [ctx[@"x"][@"c"] intValue] == 1, @"x != {a=3, b=2, c=1}");
    result = [ctx call:@"say" with:@[ @"test dictionary" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result[@"a"] intValue] == 3 && [result[@"b"] intValue] == 2 && [result[@"c"] intValue] == 1, @"result != {a=3, b=2, c=1}");

    ctx[@"x"] = [NSValue valueWithPoint:CGPointMake(12, 34)];
    XCTAssert( [ctx[@"x"][@"x"] doubleValue] == 12 &&  [ctx[@"x"][@"y"] doubleValue] == 34, @"x != {12, 34}");
    result = [ctx call:@"say" with:@[ @"test point" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result[@"x"] doubleValue] == 12 &&  [result[@"y"] doubleValue] == 34, @"result != {12, 34}");

    ctx[@"x"] = [NSValue valueWithSize:CGSizeMake(12, 34)];
    XCTAssert( [ctx[@"x"][@"width"] doubleValue] == 12 &&  [ctx[@"x"][@"height"] doubleValue] == 34, @"x != {12, 34}");
    result = [ctx call:@"say" with:@[ @"test size" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result[@"width"] doubleValue] == 12 &&  [result[@"height"] doubleValue] == 34, @"result != {12, 34}");

    ctx[@"x"] = [NSValue valueWithRect:CGRectMake(12, 34, 56, 78)];
    XCTAssert( [ctx[@"x"][@"x"] doubleValue] == 12 && [ctx[@"x"][@"y"] doubleValue] == 34
              && [ctx[@"x"][@"width"] doubleValue] == 56 && [ctx[@"x"][@"height"] doubleValue] == 78,  @"x != {{12, 34}, {56, 78}}");
    result = [ctx call:@"say" with:@[ @"test rect" ] error:&error];
    XCTAssert( ! error, @"failed to run say: %@", error);
    NSLog(@"say returned: %@", result);
    XCTAssert( [result[@"x"] doubleValue] == 12 && [result[@"y"] doubleValue] == 34
              && [result[@"width"] doubleValue] == 56 && [result[@"height"] doubleValue] == 78,  @"result != {{12, 34}, {56, 78}}");
}

static inline BOOL CGAffineTransformEqualToTransformEpsilon(CGAffineTransform t1, CGAffineTransform t2) {
	return ( compareFloatsEpsilon(t1.a, t2.a)
			&& compareFloatsEpsilon(t1.b, t2.b)
			&& compareFloatsEpsilon(t1.c, t2.c)
			&& compareFloatsEpsilon(t1.d, t2.d)
			&& compareFloatsEpsilon(t1.tx, t2.tx)
			&& compareFloatsEpsilon(t1.ty, t2.ty)
			);
}

static inline BOOL CATransform3DEqualToTransformEpsilon(CATransform3D t1, CATransform3D t2) {
    return ( compareFloatsEpsilon(t1.m11, t2.m11)
            && compareFloatsEpsilon(t1.m12, t2.m12)
            && compareFloatsEpsilon(t1.m13, t2.m13)
            && compareFloatsEpsilon(t1.m14, t2.m14)
            && compareFloatsEpsilon(t1.m21, t2.m21)
            && compareFloatsEpsilon(t1.m22, t2.m22)
            && compareFloatsEpsilon(t1.m23, t2.m23)
            && compareFloatsEpsilon(t1.m24, t2.m24)
            && compareFloatsEpsilon(t1.m31, t2.m31)
            && compareFloatsEpsilon(t1.m32, t2.m32)
            && compareFloatsEpsilon(t1.m33, t2.m33)
            && compareFloatsEpsilon(t1.m34, t2.m34)
            && compareFloatsEpsilon(t1.m41, t2.m41)
            && compareFloatsEpsilon(t1.m42, t2.m42)
            && compareFloatsEpsilon(t1.m43, t2.m43)
            && compareFloatsEpsilon(t1.m44, t2.m44)
            );
}

- (void)testExport {
    LuaContext *ctx = [LuaContext new];

    NSError *error = nil;

    NSString *script =
@"function publicFn () local v = ex.publicMethod() print(v) return v end"
" function publicPr () local v = ex.publicString print(v) return v end"
" function privateFn () local v = ex.privateMethod() print(v) return v end"
" function privatePr () local v = ex.privateString print(v) return v end"
" function floatProp (v) ex.floatProperty = v return v end"
" function setPublicPr (v) ex.publicString = v print(v) return v end";
    [ctx parse:script error:&error];
    XCTAssert( ! error, @"failed to load script: %@", error);

    id result;
    ExportObject *ex = [ExportObject new];
    ctx[@"ex"] = ex;

    result = [ctx call:@"publicFn" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    ex.silence = YES;
    XCTAssert( [result isEqualToString:[ex publicMethod]], @"result is wrong");
    ex.silence = NO;

    result = [ctx call:@"publicPr" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");

    result = [ctx call:@"floatProp" with:@[ @M_PI ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( compareFloatsEpsilon([result floatValue], ex.floatProperty), @"result is wrong");

    result = [ctx call:@"privateFn" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"private access succeeded");
    ex.silence = YES;
    XCTAssert( ! [result isEqualToString:[ex privateMethod]], @"result is wrong");
    ex.silence = NO;
    error = nil;

    result = [ctx call:@"privatePr" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"private access succeeded");
    XCTAssert( ! [result isEqualToString:ex.privateString], @"result is wrong");
    error = nil;

    result = [ctx call:@"setPublicPr" with:@[ @"new value" ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");

    result = [ctx call:@"setPublicPr" with:@[ @"another value" ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");

    result = [ctx call:@"publicPr" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");

    result = [ctx call:@"setPublicPr" with:@[ @5 ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"setting string to number succeeded");
    XCTAssert( ! [result isEqualToString:ex.publicString], @"result is wrong");
    error = nil;

    result = [ctx call:@"setPublicPr" with:@[ [NSMutableString stringWithString:@"mutable test"] ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");

    ctx[@"ex"] = [ExportObject class];
    result = [ctx parse:@"return ex.alloc().init()" error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isKindOfClass:[ExportObject class]], @"result is wrong");
}

- (void)testComplexType {
    LuaContext *ctx = [LuaContext new];

    NSError *error = nil;

    NSString *script =
@"function testVoid () ex.voidTakesStringAndNumber(\"string\", 6) end"
" function testRect1 () return ex.rectTakesArrayAndRect({1, 2, 3, 4}, { x = 4, y = 3, width = 2, height = 1 }) end"
" function testRect2 () return ex.rectTakesArrayAndRect(nil, { x = 5, y = 6, width = 7, height = 8 }) end"
" function testFloat () return ex.floatTakesNothing() end"
" function testXForm1 () return ex.transformTakesTransformAndFloat(CGAffineTransformIdentity, 1.5) end"
" function testXForm2 () return ex.transformTakesArrayAndFloat({1, 0, 0, 1, 0, 0}, 1.5) end"
" function test3DXFormPass (v) return ex.passThroughMatrix(v) end"
"";
    [ctx parse:script error:&error];
    XCTAssert( ! error, @"failed to load script: %@", error);

    id result;
    ExportObject *ex = [ExportObject new];
    ctx[@"ex"] = ex;
    ctx[@"CGAffineTransformIdentity"] = @[ @1.0, @0.0, @0.0, @1.0, @0.0, @0.0 ];

    result = [ctx call:@"testVoid" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && ! error, @"failed with: %@", error);

    result = [ctx call:@"testRect1" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( [result[@"x"] floatValue] == 1 && [result[@"y"] floatValue] == 2
              && [result[@"width"] floatValue] == 3 && [result[@"height"] floatValue] == 4 , @"wrong result");

    result = [ctx call:@"testRect2" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( [result[@"x"] floatValue] == 5 && [result[@"y"] floatValue] == 6
              && [result[@"width"] floatValue] == 7 && [result[@"height"] floatValue] == 8 , @"wrong result");

    result = [ctx call:@"testFloat" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( compareFloatsEpsilon([result floatValue], M_2_PI) && ! error, @"failed with: %@", error);

    result = [ctx call:@"testXForm1" with:nil error:&error];
    CGAffineTransform expected = CGAffineTransformMakeRotation(1.5);
    NSLog(@"%d result: %@ expected: %@ error: %@", __LINE__, result, StringFromCGAffineTransform(expected), error);
    CGAffineTransform xform = CGAffineTransformFromArray(result);
    XCTAssert( CGAffineTransformEqualToTransformEpsilon(expected, xform) && ! error, @"failed with: %@", error);

    result = [ctx call:@"testXForm2" with:nil error:&error];
    expected = CGAffineTransformMakeRotation(1.5);
    NSLog(@"%d result: %@ expected: %@ error: %@", __LINE__, result, StringFromCGAffineTransform(expected), error);
    xform = CGAffineTransformFromArray(result);
    XCTAssert( CGAffineTransformEqualToTransformEpsilon(expected, xform) && ! error, @"failed with: %@", error);

    result = [ctx call:@"test3DXFormPass" with:@[ [NSValue valueWithBytes:&CATransform3DIdentity objCType:@encode(CATransform3D)] ] error:&error];
    NSLog(@"%d result: %@ expected: %@ error: %@", __LINE__, result, StringFromCATransform3D(CATransform3DIdentity), error);
    CATransform3D xform3d = CATransform3DFromArray(result);
    XCTAssert( CATransform3DEqualToTransformEpsilon(CATransform3DIdentity, xform3d) && ! error, @"failed with: %@", error);
}

- (void)testInheritance {
    LuaContext *ctx = [LuaContext new];

    NSError *error = nil;

    NSString *script =
@"function publicFn () local v = ex.publicMethod() print(v) return v end"
" function publicFn2 () local v = ex.publicMethod2() print(v) return v end"
" function publicPr () local v = ex.publicString print(v) return v end"
" function publicPr2 () local v = ex.publicString2 print(v) return v end"
" function privateFn () local v = ex.privateMethod() print(v) return v end"
" function privateFn2 () local v = ex.privateMethod2() print(v) return v end"
" function privateFn3 () local v = ex.privateMethod3() print(v) return v end"
" function privatePr () local v = ex.privateString print(v) return v end"
" function privatePr2 () local v = ex.privateString2 print(v) return v end"
" function privatePr3 () local v = ex.privateString3 print(v) return v end"
" function setPublicPr (v) ex.publicString = v print(v) return v end"
" function setPublicPr2 (v) ex.publicString2 = v print(v) return v end";
    [ctx parse:script error:&error];
    XCTAssert( ! error, @"failed to load script: %@", error);

    id result;
    InheritedPrivateObject *ex = [InheritedPrivateObject new];
    ctx[@"ex"] = ex;

    result = [ctx call:@"publicFn" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    ex.silence = YES;
    XCTAssert( [result isEqualToString:[ex publicMethod]], @"result is wrong");
    ex.silence = NO;

    result = [ctx call:@"publicFn2" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    ex.silence = YES;
    XCTAssert( [result isEqualToString:[ex publicMethod2]], @"result is wrong");
    ex.silence = NO;

    result = [ctx call:@"publicPr" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");

    result = [ctx call:@"publicPr2" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString2], @"result is wrong");


    result = [ctx call:@"privateFn" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"private access succeeded");
    ex.silence = YES;
    XCTAssert( ! [result isEqualToString:[ex privateMethod]], @"result is wrong");
    ex.silence = NO;
    error = nil;

    result = [ctx call:@"privateFn2" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"private access succeeded");
    ex.silence = YES;
    XCTAssert( ! [result isEqualToString:[ex privateMethod2]], @"result is wrong");
    ex.silence = NO;
    error = nil;

    result = [ctx call:@"privateFn3" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"private access succeeded");
    ex.silence = YES;
    XCTAssert( ! [result isEqualToString:[ex privateMethod3]], @"result is wrong");
    ex.silence = NO;
    error = nil;

    result = [ctx call:@"privatePr" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"private access succeeded");
    XCTAssert( ! [result isEqualToString:ex.privateString], @"result is wrong");
    error = nil;

    result = [ctx call:@"privatePr2" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"private access succeeded");
    XCTAssert( ! [result isEqualToString:ex.privateString2], @"result is wrong");
    error = nil;

    result = [ctx call:@"privatePr3" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"private access succeeded");
    XCTAssert( ! [result isEqualToString:ex.privateString3], @"result is wrong");
    error = nil;

    result = [ctx call:@"setPublicPr" with:@[ @"new value" ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");

    result = [ctx call:@"setPublicPr" with:@[ @"another value" ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");

    result = [ctx call:@"publicPr" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");

    result = [ctx call:@"setPublicPr" with:@[ @5 ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"setting string to number succeeded");
    XCTAssert( ! [result isEqualToString:ex.publicString], @"result is wrong");
    error = nil;

    result = [ctx call:@"setPublicPr" with:@[ [NSMutableString stringWithString:@"mutable test"] ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString], @"result is wrong");


    result = [ctx call:@"setPublicPr2" with:@[ @"new value 2" ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString2], @"result is wrong");

    result = [ctx call:@"setPublicPr2" with:@[ @"another value 2" ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString2], @"result is wrong");

    result = [ctx call:@"publicPr2" with:nil error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString2], @"result is wrong");

    result = [ctx call:@"setPublicPr2" with:@[ @6 ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! result && error, @"setting string to number succeeded");
    XCTAssert( ! [result isEqualToString:ex.publicString2], @"result is wrong");
    error = nil;

    result = [ctx call:@"setPublicPr2" with:@[ [NSMutableString stringWithString:@"mutable test 2"] ] error:&error];
    NSLog(@"%d result: %@ error: %@", __LINE__, result, error);
    XCTAssert( ! error, @"failed with: %@", error);
    XCTAssert( [result isEqualToString:ex.publicString2], @"result is wrong");
}

- (void)testPrint {
    LuaContext *ctx = [LuaContext new];

    NSError *error = nil;

    NSString *script =
@"function testPrint (v) s = dumpVar(v) print(s) return s end"
"";
    [ctx parse:script error:&error];
    XCTAssert( ! error, @"failed to load script: %@", error);

    id result;

    result = [ctx call:@"testPrint" with:@[ @"foo" ] error:&error];
    NSLog(@"result: %@ error: %@", result, error);
    XCTAssert( ! error, @"unexpected error: %@", error);
    XCTAssert( [result isEqualToString:@"foo"], @"result is wrong");

    result = [ctx call:@"testPrint" with:@[ @1 ] error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"unexpected error: %@", error);
    XCTAssert( [result isEqualToString:@"1"], @"result is wrong");

    result = [ctx call:@"testPrint" with:@[ @[ @1, @2, @3 ] ] error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"unexpected error: %@", error);
    // yes, this is dependent on how [NSArray description] behaves, but it's "good enough"
    XCTAssert( [result isEqualToString:@"(\n    1,\n    2,\n    3\n)"], @"result is wrong");

    result = [ctx call:@"testPrint" with:@[ @{ @"a": @1, @"b": @2, @"c": @3 } ] error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"unexpected error: %@", error);
    // yes, this is dependent on how [NSDictionary description] behaves, but it's "good enough"
    XCTAssert( [result isEqualToString:@"{\n    a = 1;\n    b = 2;\n    c = 3;\n}"], @"result is wrong");
}

- (void)testBlocks {
    LuaContext *ctx = [LuaContext new];

    NSError *error = nil;

    ExportObject *obj = [ExportObject new];
    obj.privateString = @"private string";

    ctx[@"exObject"] = obj;

    id result;

    ctx[@"exBlock"] = ^(NSString *arg) {
        return [NSString stringWithFormat:@"block result: %@", arg];
    };
    result = [ctx parse:@"return exObject.runBlock(exBlock)" error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"failed to load script: %@", error);
    XCTAssert( [result isEqual:@"block result: private string"], @"result is wrong");

    result = [ctx parse:@"return exBlock('string')" error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"failed to load script: %@", error);
    XCTAssert( [result isEqual:@"block result: string"], @"result is wrong");

    result = [ctx parse:@"return exObject()" error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! result && error, @"object called: %@", error);
}

- (void)testMultipleReturnValues {
    LuaContext *ctx = [LuaContext new];

    NSError *error = nil;

    [ctx parse:@"function passThrough (...) return ... end" error:&error];
    XCTAssert( ! error, @"failed to load script: %@", error);

    id result;

    result = [ctx call:@"passThrough" with:nil error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"failed to load script: %@", error);
    XCTAssert( ! result, @"result is wrong");

    result = [ctx call:@"passThrough" with:@[@1] error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"failed to load script: %@", error);
    XCTAssert( [result isEqual:@1], @"result is wrong");

    result = [ctx call:@"passThrough" with:@[@1, @2.3, @"string", @YES, @NO] error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"failed to load script: %@", error);
    XCTAssert( [result[0] isEqual:@1]
              && [result[1] isEqual:@2.3]
              && [result[2] isEqualToString:@"string"]
              && [result[3] isEqual:@YES]
              && [result[4] isEqual:@NO], @"result is wrong");

    result = [ctx parse:@"return none" error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"failed to load script: %@", error);
    XCTAssert( ! result, @"result is wrong");

    result = [ctx parse:@"return 1" error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"failed to load script: %@", error);
    XCTAssert( [result isEqual:@1], @"result is wrong");

    result = [ctx parse:@"return 1, 2.3, 'string', true, false" error:&error];
    NSLog(@"error: %@", error);
    XCTAssert( ! error, @"failed to load script: %@", error);
    XCTAssert( [result[0] isEqual:@1]
              && [result[1] isEqual:@2.3]
              && [result[2] isEqualToString:@"string"]
              && [result[3] isEqual:@YES]
              && [result[4] isEqual:@NO], @"result is wrong");
}

static inline int triangularNumber(int number) {
	return number*(number+1)/2;
}

static void measureBlock(id self, void(^block)(), int passCount, NSTimeInterval *time, NSTimeInterval *stdev) {
    NSMutableArray *passTimes = [NSMutableArray arrayWithCapacity:passCount];

    clock_t startTime, finishTime;

    double passTime;

    for( int i=0; i<passCount; ++i ) {
        startTime = clock();
        block();
        finishTime = clock();
        passTime = (double)(finishTime - startTime) / CLOCKS_PER_SEC;
        [passTimes addObject:@(passTime)];
    }

    NSExpression *expression;

    expression = [NSExpression expressionForFunction:@"average:" arguments:@[[NSExpression expressionForConstantValue:passTimes]]];
    *time = [[expression expressionValueWithObject:nil context:nil] doubleValue];

    expression = [NSExpression expressionForFunction:@"stddev:" arguments:@[[NSExpression expressionForConstantValue:passTimes]]];
    *stdev = [[expression expressionValueWithObject:nil context:nil] doubleValue] / *time * 100;
}

static BOOL compareObjects(id lobj, id robj) {
    if( [lobj isKindOfClass:[NSDictionary class]] ) {
        for( id key in lobj ) {
            if( !compareObjects(lobj[key], robj[key]) ) {
                return NO;
            }
        }
        return YES;
    }
    else if( [lobj isKindOfClass:[NSArray class]] ) {
        for( int i = 0; i < [lobj count]; ++i ) {
            if( !compareObjects(lobj[i], robj[i]) ) {
                return NO;
            }
        }
        return YES;
    }
    else {
        return [lobj isEqual:robj];
    }
}

static NSString *const luaTriangularNumber = LUA_STRING
(
 function triangularNumber(n)
     local x = 0
     for i = 0,n do
         x = x + i
     end
     return x
 end
 );

static NSString *const luaDictionaryAccess = LUA_STRING
(
 local result = {}
 for k, v in pairs(dictionary) do
     result[k] = v
 end
 return result;
 );

static NSString *const luaArrayAccess = LUA_STRING
(
 local result = {}
 for i = 1, #array do
     result[i] = array[i]
 end
 return result;
 );

static NSString *const luaDeepCopy = LUA_STRING
(
 local function deepCopy(original)
     local copy = {}
     for k, v in pairs(original) do
         if type(v) == 'table' then
             v = deepCopy(v)
         end
         copy[k] = v
     end
     return setmetatable(copy, getmetatable(original));
 end
 return deepCopy(object)
 );

static NSString *const jsTriangularNumber = LUA_STRING
(
 function triangularNumber(n) {
     var i, x = 0;
     for (i = 0; i <= n; ++i) {
         x = x + i;
     }
     return x;
 }
 );

static NSString *const jsDictionaryAccess = LUA_STRING
(
 var key, result = {};
 for (key in dictionary) {
     result[key] = dictionary[key];
 }
 result;
 );

static NSString *const jsArrayAccess = LUA_STRING
(
 var i, result = [];
 for (i = 0; i < array.length; i++) {
     result[i] = array[i];
 }
 result;
 );

static NSString *const jsDeepCopy = LUA_STRING
(
 function deepCopy(original) {
     var copy = original.constructor();
     for(var key in original) {
         var value = original[key];
         if(typeof(original[key])=='object' && original[key] != null) {
             value = deepCopy(value);
         }
         copy[key] = value;
     }
     return copy;
 }
 deepCopy(object)
 );

- (void)testPerformance {
    const int passCount = 100;

    NSDictionary *dictionary = @{@"Key1":@1, @"Key2": @2.3, @"Key3": @"four", @"Key4": @YES};
    NSArray *array = @[@1, @2.3, @"four", @YES];
    id obj1 = @{@"Key1": dictionary, @"Key2": array};
    id obj2 = @[dictionary, array];
    id obj3 = @{@"Key1": array, @"Key2": dictionary};
    id obj4 = @[array, dictionary];
    id object = @{@"Key1": obj1, @"Key2": obj2, @"Key3": obj3, @"Key4": obj4};

    NSTimeInterval luaTime, luaStdev, jsTime, jsStdev;

    BOOL result;

    LuaContext *ctx = [LuaContext new];

    [self measureBlock:^{
        [ctx parse:luaTriangularNumber error:nil];
        XCTAssert([[ctx call:@"triangularNumber" with:@[@(passCount)] error:nil] intValue] == triangularNumber(passCount), @"result is wrong");
    }];

    LuaContext *luaCtx = [LuaContext new];

    measureBlock(self,
                 ^{
                     [luaCtx parse:luaTriangularNumber error:nil];
                     XCTAssert([[luaCtx call:@"triangularNumber" with:@[@(passCount)] error:nil] intValue] == triangularNumber(passCount), @"result is wrong");
                 },
                 passCount,
                 &luaTime, &luaStdev
                 );
    NSLog(@"Lua execution time %f with relative standard deviation %.3f%%", luaTime, luaStdev);

    JSContext *jsCtx = [JSContext new];

    measureBlock(self,
                 ^{
                     [jsCtx evaluateScript:jsTriangularNumber];
                     XCTAssert([[jsCtx[@"triangularNumber"] callWithArguments:@[@(passCount)]] toInt32] == triangularNumber(passCount), @"result is wrong");
                 },
                 passCount,
                 &jsTime, &jsStdev
                 );
    NSLog(@"JavaScript execution time %f with relative standard deviation %.3f%%", jsTime, jsStdev);

    result = luaTime < jsTime;
    NSLog(@"Triangular Number: Lua execution time is %s than JavaScript's", result ? "less" : "greater or equal");
    XCTAssert(result, @"Triangular Number: Lua execution time is %s than JavaScript's", result ? "less" : "greater or equal");

    measureBlock(self,
                 ^{
                     luaCtx[@"dictionary"] = dictionary;
                     NSDictionary *result = [luaCtx parse:luaDictionaryAccess error:nil];
                     XCTAssert(compareObjects(dictionary, result), @"objects are different");
                 },
                 passCount,
                 &luaTime, &luaStdev
                 );
    NSLog(@"Lua execution time %f with relative standard deviation %.3f%%", luaTime, luaStdev);

    measureBlock(self,
                 ^{
                     jsCtx[@"dictionary"] = dictionary;
                     NSDictionary *result = [[jsCtx evaluateScript:jsDictionaryAccess] toDictionary];
                     XCTAssert(compareObjects(dictionary, result), @"objects are different");
                 },
                 passCount,
                 &jsTime, &jsStdev
                 );
    NSLog(@"JavaScript execution time %f with relative standard deviation %.3f%%", jsTime, jsStdev);

    result = luaTime < jsTime;
    NSLog(@"Dictionary access: Lua execution time is %s than JavaScript's", result ? "less" : "greater or equal");
    XCTAssert(result, @"Dictionary access: Lua execution time is %s than JavaScript's", result ? "less" : "greater or equal");

    measureBlock(self,
                 ^{
                     luaCtx[@"array"] = array;
                     NSArray *result = [luaCtx parse:luaArrayAccess error:nil];
                     XCTAssert(compareObjects(array, result), @"objects are different");
                 },
                 passCount,
                 &luaTime, &luaStdev
                 );
    NSLog(@"Lua execution time %f with relative standard deviation %.3f%%", luaTime, luaStdev);

    measureBlock(self,
                 ^{
                     jsCtx[@"array"] = array;
                     NSArray *result = [[jsCtx evaluateScript:jsArrayAccess] toArray];
                     XCTAssert(compareObjects(array, result), @"objects are different");
                 },
                 passCount,
                 &jsTime, &jsStdev
                 );
    NSLog(@"JavaScript execution time %f with relative standard deviation %.3f%%", jsTime, jsStdev);

    result = luaTime < jsTime;
    NSLog(@"Array access: Lua execution time is %s than JavaScript's", result ? "less" : "greater or equal");
    XCTAssert(result, @"Array access: Lua execution time is %s than JavaScript's", result ? "less" : "greater or equal");

    measureBlock(self,
                 ^{
                     luaCtx[@"object"] = object;
                     id result = [luaCtx parse:luaDeepCopy error:nil];
                     XCTAssert(compareObjects(object, result), @"objects are different");
                 },
                 passCount,
                 &luaTime, &luaStdev
                 );
    NSLog(@"Lua execution time %f with relative standard deviation %.3f%%", luaTime, luaStdev);

    measureBlock(self,
                 ^{
                     jsCtx[@"object"] = object;
                     id result = [[jsCtx evaluateScript:jsDeepCopy] toObject];
                     XCTAssert(compareObjects(object, result), @"objects are different");
                 },
                 passCount,
                 &jsTime, &jsStdev
                 );
    NSLog(@"JavaScript execution time %f with relative standard deviation %.3f%%", jsTime, jsStdev);

    result = luaTime < jsTime;
    NSLog(@"Deep copy: Lua execution time is %s than JavaScript's", result ? "less" : "greater or equal");
    XCTAssert(result, @"Deep copy: Lua execution time is %s than JavaScript's", result ? "less" : "greater or equal");
}

@end
