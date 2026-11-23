#import <UIKit/UIKit.h>
@interface IRScanner : UIViewController
@property (nonatomic, copy) void (^onCode)(NSString *value);
@end
