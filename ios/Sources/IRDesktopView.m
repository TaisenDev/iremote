#import "IRDesktopView.h"
#import <AVFoundation/AVUtilities.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

@implementation IRDesktopView {
    UIImageView *_screen;
    CGRect _picture;
    CGPoint _cursor;
    CGPoint _dragLocation;
    CGFloat _wheelX;
    CGFloat _wheelY;
    CFTimeInterval _lastMove;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.045 alpha:1];
        _screen = [[UIImageView alloc] init];
        _screen.contentMode = UIViewContentModeScaleAspectFit;
        _screen.accessibilityLabel = @"Pantalla de la PC";
        [self addSubview:_screen];
        _cursor = CGPointMake(0.5, 0.5);
        for (NSUInteger count = 1; count <= 3; count++) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
            tap.numberOfTouchesRequired = count;
            [self addGestureRecognizer:tap];
        }
        UIPanGestureRecognizer *pointer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
        pointer.maximumNumberOfTouches = 1;
        [self addGestureRecognizer:pointer];
        UIPanGestureRecognizer *wheel = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(wheel:)];
        wheel.minimumNumberOfTouches = 2;
        wheel.maximumNumberOfTouches = 2;
        [self addGestureRecognizer:wheel];
        UILongPressGestureRecognizer *drag = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
        drag.minimumPressDuration = 0.38;
        [self addGestureRecognizer:drag];
    }
    return self;
}
- (void)setFrameImage:(UIImage *)frameImage {
    _frameImage = frameImage;
    _screen.image = frameImage;
    _picture = frameImage ? AVMakeRectWithAspectRatioInsideRect(frameImage.size, self.bounds) : CGRectZero;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _screen.frame = self.bounds;
    _picture = _frameImage ? AVMakeRectWithAspectRatioInsideRect(_frameImage.size, self.bounds) : CGRectZero;
}
- (CGPoint)normalized:(CGPoint)point {
    return CGPointMake(MIN(1, MAX(0, (point.x - _picture.origin.x) / _picture.size.width)),
                       MIN(1, MAX(0, (point.y - _picture.origin.y) / _picture.size.height)));
}
- (void)advance:(CGPoint)delta {
    _cursor.x = MIN(1, MAX(0, _cursor.x + delta.x * 1.35 / _picture.size.width));
    _cursor.y = MIN(1, MAX(0, _cursor.y + delta.y * 1.35 / _picture.size.height));
}
- (void)pointer:(uint8_t)action {
    if (!self.command) return;
    uint16_t x = (uint16_t)lround(_cursor.x * 65535.0);
    uint16_t y = (uint16_t)lround(_cursor.y * 65535.0);
    uint8_t packet[] = {x >> 8, x & 255, y >> 8, y & 255, action};
    self.command(IRPointer, [NSData dataWithBytes:packet length:sizeof(packet)]);
}
- (BOOL)moveDue {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastMove < 1.0 / 30.0) return NO;
    _lastMove = now;
    return YES;
}
- (void)tapped:(UITapGestureRecognizer *)gesture {
    if (!_frameImage) return;
    CGPoint point = [gesture locationInView:self];
    if (!self.trackpad) {
        if (!CGRectContainsPoint(_picture, point)) return;
        _cursor = [self normalized:point];
    }
    NSUInteger count = gesture.numberOfTouchesRequired;
    [self pointer:count == 2 ? 3 : 1];
    [self pointer:count == 2 ? 4 : 2];
    if (count == 3) { [self pointer:1]; [self pointer:2]; }
}
- (void)panned:(UIPanGestureRecognizer *)gesture {
    if (!_frameImage || (gesture.state != UIGestureRecognizerStateEnded && ![self moveDue])) return;
    if (self.trackpad) {
        [self advance:[gesture translationInView:self]];
        [gesture setTranslation:CGPointZero inView:self];
    } else {
        _cursor = [self normalized:[gesture locationInView:self]];
    }
    [self pointer:0];
}
- (void)dragged:(UILongPressGestureRecognizer *)gesture {
    if (!_frameImage) return;
    if (!self.trackpad) _cursor = [self normalized:[gesture locationInView:self]];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _dragLocation = [gesture locationInView:self];
        [self pointer:1];
    }
    else if (gesture.state == UIGestureRecognizerStateChanged && [self moveDue]) {
        if (self.trackpad) {
            CGPoint current = [gesture locationInView:self];
            [self advance:CGPointMake(current.x - _dragLocation.x, current.y - _dragLocation.y)];
            _dragLocation = current;
        }
        [self pointer:0];
    } else if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled)
        [self pointer:2];
}
- (void)wheel:(UIPanGestureRecognizer *)gesture {
    if (!_frameImage || !self.command) return;
    if (gesture.state == UIGestureRecognizerStateBegan) _wheelX = _wheelY = 0;
    CGPoint delta = [gesture translationInView:self];
    [gesture setTranslation:CGPointZero inView:self];
    _wheelX += delta.x * 7;
    _wheelY -= delta.y * 7;
    if (fabs(_wheelX) < 25 && fabs(_wheelY) < 25) return;
    uint16_t horizontal = (uint16_t)(int16_t)MAX(-1200, MIN(1200, _wheelX));
    uint16_t vertical = (uint16_t)(int16_t)MAX(-1200, MIN(1200, _wheelY));
    uint8_t packet[] = {vertical >> 8, vertical & 255, horizontal >> 8, horizontal & 255};
    self.command(IRScroll, [NSData dataWithBytes:packet length:sizeof(packet)]);
    _wheelX = _wheelY = 0;
}
@end
