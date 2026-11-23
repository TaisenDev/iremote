#import "IRScanner.h"
#import <AVFoundation/AVFoundation.h>

@interface IRScanner () <AVCaptureMetadataOutputObjectsDelegate>
@end
@implementation IRScanner {
    AVCaptureSession *_capture;
    AVCaptureVideoPreviewLayer *_preview;
    dispatch_queue_t _camera;
    UILabel *_instruction;
    UIButton *_cancel;
    BOOL _finished;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    _camera = dispatch_queue_create("iremote.camera", DISPATCH_QUEUE_SERIAL);
    _capture = [[AVCaptureSession alloc] init];
    _capture.sessionPreset = AVCaptureSessionPresetMedium;
    _preview = [AVCaptureVideoPreviewLayer layerWithSession:_capture];
    _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer addSublayer:_preview];
    _instruction = [[UILabel alloc] init];
    _instruction.numberOfLines = 0;
    _instruction.textAlignment = NSTextAlignmentCenter;
    _instruction.textColor = [UIColor whiteColor];
    _instruction.backgroundColor = [UIColor colorWithWhite:0.03 alpha:0.9];
    _instruction.text = @"Encuadra el QR que muestra iremote en tu PC.";
    [self.view addSubview:_instruction];
    _cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancel setTitle:@"Cancelar" forState:UIControlStateNormal];
    [_cancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _cancel.backgroundColor = [UIColor colorWithWhite:0.03 alpha:0.85];
    [_cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancel];

    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_finished) return;
            if (granted) [self startCamera];
            else self->_instruction.text = @"Permite el acceso a Cámara en Ajustes o usa Conexión manual.";
        });
    }];
}
- (void)startCamera {
    dispatch_async(_camera, ^{
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:NULL] : nil;
        AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
        if (!input || ![_capture canAddInput:input] || ![_capture canAddOutput:output]) {
            dispatch_async(dispatch_get_main_queue(), ^{ _instruction.text = @"La cámara no está disponible."; });
            return;
        }
        [_capture beginConfiguration];
        [_capture addInput:input];
        [_capture addOutput:output];
        if ([output.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]) {
            [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
            output.metadataObjectTypes = @[AVMetadataObjectTypeQRCode];
        }
        [_capture commitConfiguration];
        [_capture startRunning];
        dispatch_async(dispatch_get_main_queue(), ^{ [self.view setNeedsLayout]; });
    });
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    _preview.frame = bounds;
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if (_preview.connection.isVideoOrientationSupported && orientation >= UIInterfaceOrientationPortrait &&
        orientation <= UIInterfaceOrientationLandscapeRight)
        _preview.connection.videoOrientation = (AVCaptureVideoOrientation)orientation;
    _instruction.frame = CGRectMake(0, bounds.size.height - 90, bounds.size.width, 90);
    _cancel.frame = CGRectMake(12, self.topLayoutGuide.length + 12, 100, 48);
}
- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray *)objects
       fromConnection:(AVCaptureConnection *)connection {
    if (_finished) return;
    for (AVMetadataMachineReadableCodeObject *code in objects) {
        if (![code.type isEqualToString:AVMetadataObjectTypeQRCode] || ![code.stringValue hasPrefix:@"iremote-pair:1|"])
            continue;
        _finished = YES;
        [self stopCamera];
        NSString *value = code.stringValue;
        [self dismissViewControllerAnimated:YES completion:^{ if (self.onCode) self.onCode(value); }];
        break;
    }
}
- (void)stopCamera { dispatch_async(_camera, ^{ [_capture stopRunning]; }); }
- (void)cancel {
    _finished = YES;
    [self stopCamera];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    _finished = YES;
    [self stopCamera];
}
@end
