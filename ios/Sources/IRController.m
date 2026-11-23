#import "IRController.h"
#import "IRDesktopView.h"
#import "IRPhoneStore.h"
#import "IRDiscovery.h"
#import "IRScanner.h"

@interface IRKeyboard : UIView <UIKeyInput>
@property (nonatomic, copy) void (^typed)(NSString *text);
@property (nonatomic, copy) dispatch_block_t erased;
@end
@implementation IRKeyboard
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)hasText { return YES; }
- (void)insertText:(NSString *)text { if (self.typed) self.typed(text); }
- (void)deleteBackward { if (self.erased) self.erased(); }
- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UITextAutocapitalizationType)autocapitalizationType { return UITextAutocapitalizationTypeNone; }
@end

@implementation IRController {
    UIScrollView *_setup;
    UILabel *_titleLabel;
    UILabel *_descriptionLabel;
    UILabel *_setupStatus;
    UITextField *_address;
    UITextField *_port;
    UITextField *_fingerprint;
    UITextField *_code;
    UIButton *_connect;
    UIButton *_scan;
    UIButton *_advanced;
    UIButton *_forget;
    UIView *_active;
    UIView *_bar;
    UILabel *_sessionStatus;
    UIButton *_disconnect;
    UIButton *_keyboardButton;
    UIButton *_specialButton;
    UIButton *_helpButton;
    UISegmentedControl *_mode;
    IRDesktopView *_desktop;
    UIScrollView *_keystrip;
    IRKeyboard *_keyboard;
    NSArray *_modifierButtons;
    NSDictionary *_saved;
    NSDictionary *_target;
    NSData *_pairCode;
    IRSession *_session;
    NSUInteger _retries;
    NSUInteger _generation;
    CGFloat _keyboardTop;
    uint8_t _modifiers;
    BOOL _keysVisible;
    BOOL _manual;
}
static UIColor *IRAccent(void) { return [UIColor colorWithRed:0.26 green:0.24 blue:0.70 alpha:1]; }

- (UILabel *)label:(NSString *)text style:(NSString *)style parent:(UIView *)parent {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:style];
    label.numberOfLines = 0;
    [parent addSubview:label];
    return label;
}
- (UIButton *)button:(NSString *)title action:(SEL)action parent:(UIView *)parent {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [parent addSubview:button];
    return button;
}
- (UITextField *)field:(NSString *)title parent:(UIView *)parent {
    UITextField *field = [[UITextField alloc] init];
    field.borderStyle = UITextBorderStyleRoundedRect;
    field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    field.accessibilityLabel = title;
    field.placeholder = title;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [parent addSubview:field];
    return field;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.view.tintColor = IRAccent();
    _setup = [[UIScrollView alloc] init];
    _setup.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:_setup];
    _titleLabel = [self label:@"Conectar con tu PC" style:UIFontTextStyleHeadline parent:_setup];
    _titleLabel.font = [_titleLabel.font fontWithSize:_titleLabel.font.pointSize + 11];
    _descriptionLabel = [self label:@"Abre iremote en Windows y escanea el QR para vincular el iPad."
                               style:UIFontTextStyleBody parent:_setup];
    _address = [self field:@"Dirección IPv4 de la PC" parent:_setup];
    _address.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    _port = [self field:@"Puerto" parent:_setup];
    _port.keyboardType = UIKeyboardTypeNumberPad;
    _fingerprint = [self field:@"Huella del receptor" parent:_setup];
    _code = [self field:@"Código de emparejamiento" parent:_setup];
    _code.keyboardType = UIKeyboardTypeNumberPad;
    _code.secureTextEntry = YES;
    _connect = [self button:@"Conectar" action:@selector(connect) parent:_setup];
    _connect.backgroundColor = IRAccent();
    [_connect setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_connect setTitleColor:[UIColor colorWithWhite:0.78 alpha:1] forState:UIControlStateDisabled];
    _connect.layer.cornerRadius = 8;
    _scan = [self button:@"Escanear QR" action:@selector(scan) parent:_setup];
    _scan.backgroundColor = IRAccent();
    [_scan setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _scan.layer.cornerRadius = 8;
    _advanced = [self button:@"Conexión manual" action:@selector(toggleManual) parent:_setup];
    _forget = [self button:@"Olvidar esta PC" action:@selector(forget) parent:_setup];
    _setupStatus = [self label:nil style:UIFontTextStyleFootnote parent:_setup];
    _setupStatus.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;

    _active = [[UIView alloc] init];
    _active.backgroundColor = [UIColor colorWithWhite:0.045 alpha:1];
    _active.hidden = YES;
    [self.view addSubview:_active];
    _bar = [[UIView alloc] init];
    _bar.backgroundColor = [UIColor colorWithWhite:0.97 alpha:1];
    [_active addSubview:_bar];
    _sessionStatus = [self label:nil style:UIFontTextStyleFootnote parent:_bar];
    _disconnect = [self button:@"Salir" action:@selector(disconnect) parent:_bar];
    _keyboardButton = [self button:@"Teclado" action:@selector(toggleKeyboard) parent:_bar];
    _specialButton = [self button:@"Teclas" action:@selector(toggleKeys) parent:_bar];
    _helpButton = [self button:@"Gestos" action:@selector(help) parent:_bar];
    _mode = [[UISegmentedControl alloc] initWithItems:@[@"Táctil", @"Trackpad"]];
    _mode.selectedSegmentIndex = [[NSUserDefaults standardUserDefaults] boolForKey:@"trackpad"] ? 1 : 0;
    [_mode addTarget:self action:@selector(changeMode) forControlEvents:UIControlEventValueChanged];
    [_bar addSubview:_mode];
    _desktop = [[IRDesktopView alloc] init];
    [_active addSubview:_desktop];
    _desktop.trackpad = _mode.selectedSegmentIndex == 1;
    _keyboard = [[IRKeyboard alloc] init];
    [_active addSubview:_keyboard];
    _keystrip = [[UIScrollView alloc] init];
    _keystrip.backgroundColor = _bar.backgroundColor;
    [_active addSubview:_keystrip];
    [self buildKeys];

    __weak typeof(self) owner = self;
    _desktop.command = ^(IRCommand type, NSData *data) { [owner send:type data:data]; };
    _keyboard.typed = ^(NSString *text) { [owner typed:text]; };
    _keyboard.erased = ^{ [owner key:8]; };
    _saved = IRSavedDevice();
    [self showSetup];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(disconnect) name:UIApplicationWillResignActiveNotification object:nil];
    [center addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)showSetup {
    _address.text = _saved[@"address"];
    _port.text = _saved[@"port"] ?: @"47921";
    _code.text = nil;
    _setup.hidden = NO;
    _active.hidden = YES;
    _connect.enabled = YES;
    [self updateSetup];
}
- (void)updateSetup {
    _descriptionLabel.text = _saved ? @"El iPad buscará tu PC en la red local." :
        @"Abre iremote en Windows y escanea el QR para vincular el iPad.";
    _address.hidden = _port.hidden = !_manual;
    _code.hidden = _fingerprint.hidden = !_manual || _saved != nil;
    _connect.hidden = !_manual && !_saved;
    _scan.hidden = _manual || _saved != nil;
    _forget.hidden = _saved == nil;
    [_advanced setTitle:_manual ? @"Volver al acceso rápido" : @"Conexión manual" forState:UIControlStateNormal];
    [self.view setNeedsLayout];
}
- (void)toggleManual {
    if (!_connect.enabled) return;
    _manual = !_manual;
    [self updateSetup];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat top = self.topLayoutGuide.length;
    CGFloat bottom = _keyboardTop > 0 ? MIN(_keyboardTop, CGRectGetHeight(bounds)) : CGRectGetHeight(bounds);
    if (bottom < top) bottom = top;
    _setup.frame = CGRectMake(0, top, bounds.size.width, bottom - top);
    CGFloat width = MIN(490, bounds.size.width - 48);
    CGFloat x = (bounds.size.width - width) / 2;
    CGFloat y = 34;
    for (UIView *element in @[_titleLabel, _descriptionLabel, _address, _port,
                              _fingerprint, _code, _connect, _scan, _setupStatus, _advanced, _forget]) {
        if (element.hidden) continue;
        CGFloat height = [element isKindOfClass:[UILabel class]]
            ? MAX(22, ceil([element sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height)) : 48;
        element.frame = CGRectMake(x, y, width, height);
        y += height + 12;
    }
    _setup.contentSize = CGSizeMake(bounds.size.width, y + 24);
    _active.frame = CGRectMake(0, top, bounds.size.width, bottom - top);
    _bar.frame = CGRectMake(0, 0, bounds.size.width, 56);
    _disconnect.frame = CGRectMake(12, 6, 52, 44);
    _mode.frame = CGRectMake(76, 6, 168, 44);
    _keyboardButton.frame = CGRectMake(bounds.size.width - 224, 6, 74, 44);
    _specialButton.frame = CGRectMake(bounds.size.width - 142, 6, 62, 44);
    _helpButton.frame = CGRectMake(bounds.size.width - 74, 6, 62, 44);
    _sessionStatus.frame = CGRectMake(260, 0, MAX(0, bounds.size.width - 490), 56);
    CGFloat keyHeight = _keysVisible ? 48 : 0;
    CGFloat desktopHeight = MAX(0, bottom - top - 56 - keyHeight);
    _desktop.frame = CGRectMake(0, 56, bounds.size.width, desktopHeight);
    _keystrip.frame = CGRectMake(0, 56 + desktopHeight, bounds.size.width, keyHeight);
    _keystrip.hidden = !_keysVisible;
}
- (void)keyboardChanged:(NSNotification *)note {
    CGRect rect = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    _keyboardTop = CGRectGetMinY([self.view convertRect:rect fromView:nil]);
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}
- (void)forget {
    if (!_connect.enabled) return;
    if (!IRForgetDevice()) { _setupStatus.text = @"No se pudo borrar el vínculo del llavero."; return; }
    _saved = nil;
    _manual = NO;
    _setupStatus.text = @"Abre Mostrar QR en el receptor para volver a vincular.";
    [self showSetup];
}
- (void)scan {
    if (self.presentedViewController || !_connect.enabled) return;
    IRScanner *scanner = [[IRScanner alloc] init];
    __weak typeof(self) owner = self;
    scanner.onCode = ^(NSString *value) { [owner acceptCode:value]; };
    [self presentViewController:scanner animated:YES completion:nil];
}
- (void)acceptCode:(NSString *)value {
    NSArray *parts = [value componentsSeparatedByString:@"|"];
    if (parts.count != 5 || ![parts[0] isEqualToString:@"iremote-pair:1"]) return;
    [self connectAddress:parts[1] port:parts[2] pin:IRFingerprint(parts[3]) code:parts[4] discover:YES];
}
- (void)connect {
    NSString *address = _manual ? [_address.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : _saved[@"address"];
    NSString *port = _manual ? (_port.text ?: @"") : _saved[@"port"];
    NSData *pin = _saved[@"fingerprint"] ?: IRFingerprint(_fingerprint.text ?: @"");
    [self connectAddress:address port:port pin:pin code:_saved ? nil : _code.text discover:!_manual];
}
- (void)connectAddress:(NSString *)address port:(NSString *)port pin:(NSData *)pin
                  code:(NSString *)code discover:(BOOL)discover {
    NSCharacterSet *nonDigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    if (!IRIsPrivateIPv4(address) || [port rangeOfCharacterFromSet:nonDigits].location != NSNotFound ||
        port.integerValue < 1024 || port.integerValue > 65535) {
        _setupStatus.text = @"Revisa la dirección local y el puerto que muestra la PC.";
        [self.view setNeedsLayout]; return;
    }
    if (pin.length != 12 || (!_saved && (code.length != 10 ||
        [code rangeOfCharacterFromSet:nonDigits].location != NSNotFound))) {
        _setupStatus.text = discover ? @"El QR es inválido. Genera otro en la PC." :
            @"Introduce la huella y el código de 10 dígitos que muestra la PC.";
        [self.view setNeedsLayout]; return;
    }
    _target = @{@"address": address, @"port": port, @"fingerprint": pin};
    _pairCode = code.length ? [code dataUsingEncoding:NSASCIIStringEncoding] : nil;
    _code.text = nil;
    [self.view endEditing:YES];
    _connect.enabled = NO;
    _retries = 0;
    if (discover) [self locateAndConnect]; else [self attempt];
}
- (void)locateAndConnect {
    NSUInteger current = ++_generation;
    _setupStatus.text = @"Buscando la PC en tu red…";
    [self.view setNeedsLayout];
    IRFindHost(_target[@"fingerprint"], _target[@"address"], ^(NSString *address) {
        if (_generation != current || !_target) return;
        if (address) {
            NSMutableDictionary *updated = [_target mutableCopy];
            updated[@"address"] = address;
            updated[@"port"] = @"47921";
            _target = updated;
        }
        [self attempt];
    });
}
- (void)attempt {
    [_session stop];
    _session = [[IRSession alloc] init];
    NSUInteger current = ++_generation;
    _setupStatus.text = _retries ? @"Recuperando la conexión…" : @"Conectando con la PC…";
    _sessionStatus.text = _setupStatus.text;
    [self.view setNeedsLayout];
    __weak typeof(self) owner = self;
    _session.onReady = ^(NSData *token) { [owner accepted:token generation:current]; };
    _session.onFrame = ^(UIImage *frame) { [owner frame:frame generation:current]; };
    _session.onFailure = ^(NSString *reason, BOOL retryable) { [owner failed:reason retryable:retryable generation:current]; };
    [_session startAt:_target[@"address"] port:(uint16_t)[_target[@"port"] intValue]
         fingerprint:_target[@"fingerprint"] credential:_pairCode ?: _saved[@"token"] pairing:_pairCode != nil];
}
- (void)accepted:(NSData *)token generation:(NSUInteger)current {
    if (_generation != current) return;
    NSMutableDictionary *updated = [_target mutableCopy];
    updated[@"token"] = token.length ? token : _saved[@"token"];
    if (!IRSaveDevice(updated)) {
        [self failed:@"No se pudo guardar la credencial en el llavero." retryable:NO generation:current]; return;
    }
    _saved = updated;
    _pairCode = nil;
    _setup.hidden = YES;
    _active.hidden = NO;
    _sessionStatus.text = @"Conectado · TLS 1.2";
    [self.view setNeedsLayout];
}
- (void)frame:(UIImage *)frame generation:(NSUInteger)current {
    if (_generation != current) return;
    _desktop.frameImage = frame;
    _retries = 0;
}
- (void)failed:(NSString *)reason retryable:(BOOL)retryable generation:(NSUInteger)current {
    if (_generation != current) return;
    if (retryable && _saved && _retries < 3) {
        _sessionStatus.text = @"Reconectando…";
        _setupStatus.text = _sessionStatus.text;
        _retries++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, _retries * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (_generation == current) {
                if (_manual) [self attempt]; else [self locateAndConnect];
            }
        });
        return;
    }
    [self disconnect];
    _setupStatus.text = reason;
    [self.view setNeedsLayout];
}
- (void)disconnect {
    if (!_session && !_target) return;
    _generation++;
    [_session stop];
    _session = nil;
    _target = nil;
    _pairCode = nil;
    _desktop.frameImage = nil;
    _modifiers = 0;
    [self updateModifiers];
    [_keyboard resignFirstResponder];
    _setupStatus.text = nil;
    [self showSetup];
}
- (void)send:(IRCommand)type data:(NSData *)data { [_session send:type data:data]; }
- (void)changeMode {
    _desktop.trackpad = _mode.selectedSegmentIndex == 1;
    [[NSUserDefaults standardUserDefaults] setBool:_desktop.trackpad forKey:@"trackpad"];
}
- (void)toggleKeyboard {
    if (_keyboard.isFirstResponder) [_keyboard resignFirstResponder];
    else [_keyboard becomeFirstResponder];
}
- (void)toggleKeys {
    _keysVisible = !_keysVisible;
    [self.view setNeedsLayout];
}
- (void)help {
    NSString *message = @"Un dedo toca o mueve el puntero. Dos dedos hacen clic derecho al tocar y desplazan al deslizar. Tres dedos hacen doble clic. Mantén un dedo apoyado y muévelo para arrastrar. Usa Teclas para funciones, flechas y atajos.";
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Gestos" message:message preferredStyle:UIAlertControllerStyleAlert];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cerrar" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)buildKeys {
    NSArray *names = @[@"Ctrl", @"Alt", @"Shift", @"Win", @"Esc", @"Tab", @"Intro", @"Retroceso", @"Espacio",
                       @"Insert", @"Supr", @"Inicio", @"Fin", @"Re Pág", @"Av Pág", @"Izq.", @"Arriba", @"Der.", @"Abajo",
                       @"Impr.", @"Pausa", @"Bloq. Mayús", @"Bloq. Num", @"Bloq. Despl.",
                       @"F1", @"F2", @"F3", @"F4", @"F5", @"F6", @"F7", @"F8", @"F9", @"F10", @"F11", @"F12"];
    uint8_t values[] = {1,2,4,8, 27,9,13,8,32,45,46,36,35,33,34,37,38,39,40,44,19,20,144,145,
                        112,113,114,115,116,117,118,119,120,121,122,123};
    NSMutableArray *modifiers = [NSMutableArray array];
    CGFloat x = 8;
    for (NSUInteger i = 0; i < names.count; i++) {
        UIButton *button = [self button:names[i] action:i < 4 ? @selector(modifier:) : @selector(special:) parent:_keystrip];
        button.tag = values[i];
        CGFloat width = MAX(48, [button sizeThatFits:CGSizeZero].width + 18);
        button.frame = CGRectMake(x, 2, width, 44);
        x += width;
        if (i < 4) [modifiers addObject:button];
    }
    _modifierButtons = modifiers;
    _keystrip.contentSize = CGSizeMake(x + 8, 48);
}
- (void)updateModifiers {
    for (UIButton *button in _modifierButtons) {
        BOOL held = (_modifiers & button.tag) != 0;
        button.backgroundColor = held ? IRAccent() : [UIColor clearColor];
        [button setTitleColor:held ? [UIColor whiteColor] : IRAccent() forState:UIControlStateNormal];
        button.accessibilityTraits = UIAccessibilityTraitButton | (held ? UIAccessibilityTraitSelected : 0);
    }
}
- (void)modifier:(UIButton *)button {
    _modifiers ^= button.tag;
    [self updateModifiers];
}
- (void)special:(UIButton *)button { [self key:(uint8_t)button.tag]; }
- (void)key:(uint8_t)value {
    uint8_t bytes[] = {value, _modifiers};
    [self send:IRKey data:[NSData dataWithBytes:bytes length:sizeof(bytes)]];
    _modifiers = 0;
    [self updateModifiers];
}
- (void)typed:(NSString *)text {
    if (_modifiers && text.length == 1) {
        unichar value = [[text uppercaseString] characterAtIndex:0];
        if ((value >= 'A' && value <= 'Z') || (value >= '0' && value <= '9')) {
            [self key:(uint8_t)value]; return;
        }
    }
    _modifiers = 0;
    [self updateModifiers];
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length <= 4096) [self send:IRText data:data];
}
@end
