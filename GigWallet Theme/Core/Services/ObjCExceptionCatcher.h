#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Utility to catch Objective-C exceptions from Swift code.
/// Swift's do/catch cannot intercept NSExceptions (thrown by some SDKs like Google Sign-In),
/// which causes SIGABRT crashes. This bridge lets us catch them safely.
@interface ObjCExceptionCatcher : NSObject

/// Executes the given block and returns nil on success.
/// If an NSException is thrown, returns the exception's reason string.
+ (nullable NSString *)catchException:(void (NS_NOESCAPE ^)(void))block NS_SWIFT_NAME(catchException(_:));

@end

NS_ASSUME_NONNULL_END
