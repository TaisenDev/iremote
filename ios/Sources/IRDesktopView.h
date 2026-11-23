#import <UIKit/UIKit.h>
#import "IRSession.h"

@interface IRDesktopView : UIView
@property (nonatomic) UIImage *frameImage;
@property (nonatomic) BOOL trackpad;
@property (nonatomic, copy) void (^command)(IRCommand type, NSData *data);
@end
