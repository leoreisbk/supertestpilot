// Minimal XCTest stub for Kotlin/Native cinterop.
// Declares only the APIs used by TestPilot without importing UIKit,
// which is incompatible with Kotlin/Native's bundled LLVM on iOS 26+ SDKs.
// The actual implementation is linked from XCTest.framework at build time.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// XCUIElementType enum
// ---------------------------------------------------------------------------
typedef NS_ENUM(NSUInteger, XCUIElementType) {
    XCUIElementTypeAny                 = 0,
    XCUIElementTypeOther               = 1,
    XCUIElementTypeApplication         = 2,
    XCUIElementTypeGroup               = 3,
    XCUIElementTypeWindow              = 4,
    XCUIElementTypeSheet               = 5,
    XCUIElementTypeDrawer              = 6,
    XCUIElementTypeAlert               = 7,
    XCUIElementTypeDialog              = 8,
    XCUIElementTypeButton              = 9,
    XCUIElementTypeRadioButton         = 10,
    XCUIElementTypeRadioGroup          = 11,
    XCUIElementTypeCheckBox            = 12,
    XCUIElementTypeDisclosureTriangle  = 13,
    XCUIElementTypePopUpButton         = 14,
    XCUIElementTypeComboBox            = 15,
    XCUIElementTypeMenuButton          = 16,
    XCUIElementTypeToolbarButton       = 17,
    XCUIElementTypePopover             = 18,
    XCUIElementTypeKeyboard            = 19,
    XCUIElementTypeKey                 = 20,
    XCUIElementTypeNavigationBar       = 21,
    XCUIElementTypeTabBar              = 22,
    XCUIElementTypeTabGroup            = 23,
    XCUIElementTypeToolbar             = 24,
    XCUIElementTypeStatusBar           = 25,
    XCUIElementTypeTable               = 26,
    XCUIElementTypeTableRow            = 27,
    XCUIElementTypeTableColumn         = 28,
    XCUIElementTypeOutlineRow          = 29,
    XCUIElementTypeBrowser             = 30,
    XCUIElementTypeCollectionView      = 31,
    XCUIElementTypeSlider              = 32,
    XCUIElementTypePageIndicator       = 33,
    XCUIElementTypeProgressIndicator   = 34,
    XCUIElementTypeActivityIndicator   = 35,
    XCUIElementTypeSegmentedControl    = 36,
    XCUIElementTypePicker              = 37,
    XCUIElementTypePickerWheel         = 38,
    XCUIElementTypeSwitch              = 39,
    XCUIElementTypeToggle              = 40,
    XCUIElementTypeLink                = 41,
    XCUIElementTypeImage               = 42,
    XCUIElementTypeIcon                = 43,
    XCUIElementTypeSearchField         = 44,
    XCUIElementTypeScrollView          = 45,
    XCUIElementTypeScrollBar           = 46,
    XCUIElementTypeStaticText          = 47,
    XCUIElementTypeTextField           = 48,
    XCUIElementTypeSecureTextField     = 49,
    XCUIElementTypeDatePicker          = 50,
    XCUIElementTypeTextView            = 51,
    XCUIElementTypeMenu                = 52,
    XCUIElementTypeMenuItem            = 53,
    XCUIElementTypeMenuBar             = 54,
    XCUIElementTypeMenuBarItem         = 55,
    XCUIElementTypeMap                 = 56,
    XCUIElementTypeWebView             = 57,
    XCUIElementTypeIncrementArrow      = 58,
    XCUIElementTypeDecrementArrow      = 59,
    XCUIElementTypeTimeline            = 60,
    XCUIElementTypeRatingIndicator     = 61,
    XCUIElementTypeValueIndicator      = 62,
    XCUIElementTypeSplitGroup          = 63,
    XCUIElementTypeSplitter            = 64,
    XCUIElementTypeRelevanceIndicator  = 65,
    XCUIElementTypeColorWell           = 66,
    XCUIElementTypeHelpTag             = 67,
    XCUIElementTypeMatte               = 68,
    XCUIElementTypeDockItem            = 69,
    XCUIElementTypeRuler               = 70,
    XCUIElementTypeRulerMarker         = 71,
    XCUIElementTypeGrid                = 72,
    XCUIElementTypeLevelIndicator      = 73,
    XCUIElementTypeCell                = 74,
    XCUIElementTypeLayoutArea          = 75,
    XCUIElementTypeLayoutItem          = 76,
    XCUIElementTypeHandle              = 77,
    XCUIElementTypeStepper             = 78,
    XCUIElementTypeTab                 = 79,
    XCUIElementTypeTouchBar            = 81,
    XCUIElementTypeStatusItem          = 82,
};

// ---------------------------------------------------------------------------
// XCUIGestureVelocity
// ---------------------------------------------------------------------------
typedef double XCUIGestureVelocity;
#define XCUIGestureVelocitySlow    ((XCUIGestureVelocity)100.0)
#define XCUIGestureVelocityDefault ((XCUIGestureVelocity)250.0)
#define XCUIGestureVelocityFast    ((XCUIGestureVelocity)500.0)

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
@class XCUIElement;
@class XCUIElementQuery;
@class XCUICoordinate;

// ---------------------------------------------------------------------------
// XCUIElementSnapshot - read-only snapshot data for a UI element
// (Kotlin/Native appends "Protocol" to ObjC protocol names, so this ObjC
// protocol named "XCUIElementSnapshot" becomes "XCUIElementSnapshotProtocol"
// in Kotlin — matching the original Kotlin source code.)
// ---------------------------------------------------------------------------
@protocol XCUIElementSnapshot <NSObject>
@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly, nullable) id value;
@property (nonatomic, readonly) BOOL selected;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) XCUIElementType elementType;
@property (nonatomic, readonly, copy) NSArray *children;
@end

// ---------------------------------------------------------------------------
// XCUIElementSnapshotProviding - objects that can produce a snapshot
// (Kotlin/Native maps this as "XCUIElementSnapshotProvidingProtocol".)
// ---------------------------------------------------------------------------
@protocol XCUIElementSnapshotProviding <NSObject>
- (nullable id<XCUIElementSnapshot>)snapshotWithError:(NSError * _Nullable * _Nullable)error;
@end

// ---------------------------------------------------------------------------
// XCUIElementQuery
// ---------------------------------------------------------------------------
@interface XCUIElementQuery : NSObject
@property (nonatomic, readonly) XCUIElement *firstMatch;
@property (nonatomic, readonly) XCUIElementQuery *buttons;
@property (nonatomic, readonly) XCUIElementQuery *navigationBars;
- (XCUIElement *)elementBoundByIndex:(NSUInteger)index;
- (XCUIElementQuery *)matchingIdentifier:(NSString *)identifier;
@end

// ---------------------------------------------------------------------------
// XCUIElement
// ---------------------------------------------------------------------------
@interface XCUIElement : NSObject <XCUIElementSnapshotProviding>
@property (nonatomic, readonly, getter=exists) BOOL exists;
@property (nonatomic, readonly) XCUIElementQuery *navigationBars;
@property (nonatomic, readonly) XCUIElementQuery *buttons;
- (BOOL)waitForExistenceWithTimeout:(NSTimeInterval)timeout;
- (BOOL)isHittable;
- (void)tap;
- (void)typeText:(NSString *)text;
- (void)swipeUpWithVelocity:(XCUIGestureVelocity)velocity;
- (void)swipeDownWithVelocity:(XCUIGestureVelocity)velocity;
- (XCUIElementQuery *)descendantsMatchingType:(XCUIElementType)type;
- (XCUICoordinate *)coordinateWithNormalizedOffset:(CGVector)normalizedOffset;
@end

// ---------------------------------------------------------------------------
// XCUIApplication
// ---------------------------------------------------------------------------
@interface XCUIApplication : XCUIElement
- (instancetype)init;
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier;
- (void)launch;
@end

// ---------------------------------------------------------------------------
// XCTestCase
// ---------------------------------------------------------------------------
@interface XCTestCase : NSObject
@end

// ---------------------------------------------------------------------------
// CGVector (CoreGraphics struct — redeclare here since we don't import CG)
// ---------------------------------------------------------------------------
#ifndef CGVECTOR_DEFINED
typedef struct CGVector { CGFloat dx; CGFloat dy; } CGVector;
#define CGVECTOR_DEFINED 1
#endif

// ---------------------------------------------------------------------------
// XCUICoordinate — represents a coordinate on screen, supports gestures
// ---------------------------------------------------------------------------
@interface XCUICoordinate : NSObject
- (void)tap;
- (void)typeText:(NSString *)text;
@end

// ---------------------------------------------------------------------------
// XCUIScreenshot — screenshot data returned by XCUIScreen
// ---------------------------------------------------------------------------
@interface XCUIScreenshot : NSObject
@property (nonatomic, readonly) NSData *PNGRepresentation;
@end

// ---------------------------------------------------------------------------
// XCUIScreen — physical screen; main is the device's primary screen
// ---------------------------------------------------------------------------
@interface XCUIScreen : NSObject
@property (class, nonatomic, readonly) XCUIScreen *mainScreen;
- (XCUIScreenshot *)screenshot;
@end

NS_ASSUME_NONNULL_END
