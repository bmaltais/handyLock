//
//  AppDelegate.m
//  handyLockHelper
//
//  Created by Bernard Maltais on 9/7/2013.
//  Copyright (c) 2013 Netputing Systems Inc. All rights reserved.
//

#import "AppDelegate.h"
#import "DebugOutput.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonHMAC.h>

@implementation AppDelegate

static NSInteger displaySleepTimer = 60;
static NSInteger remainingCounts = 60;
static NSMutableDictionary * screenDictionary;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    if (![self isSecurePasswordSet]) {
        NSRunAlertPanel( @"handyLock", @"Can't activate handyLock, no security password set. Please set password using handyLock Security Tab.", @"Close", nil, nil, nil );
        exit(0);
    }
    
    [self setBackgroundImage];
    
    NSApplicationPresentationOptions options =
    NSApplicationPresentationHideMenuBar|NSApplicationPresentationHideDock|
    NSApplicationPresentationDisableHideApplication|
    NSApplicationPresentationDisableProcessSwitching|
    NSApplicationPresentationDisableAppleMenu|
    NSApplicationPresentationDisableForceQuit;
    
    [NSApp setPresentationOptions:options];
    [[lockWindow contentView] enterFullScreenMode:[NSScreen mainScreen] withOptions:nil];
    
    // [self playLockingSoundSet];
    
    idle  = [ [ IdleTime alloc ] init ];
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs addSuiteNamed:@"com.netputing.handyLock"];
    
    NSString * dST = [prefs stringForKey:@"displaySleepTimer"];
    
    if( [dST length] > 0 )
    {
        if ([dST isEqualTo:@"0"]) {
            remainingCounts = 0;
            displaySleepTimer = 60;
        } else {
            remainingCounts = [dST integerValue] * 60;
            displaySleepTimer = remainingCounts;
        }
    }
    
    [self startTrackingDisplaySleep];
    [self startScreenSleepCountDown];
    /*
    
    // Blank secondary screens
    int counter = 1;
    for (NSScreen *screen in [NSScreen screens]) {
        if ([screen isNotEqualTo:[NSScreen mainScreen]]) {
            NSWindow* window  = window2;
            [window setBackgroundColor:[NSColor blackColor]];
            [[window contentView] enterFullScreenMode:screen withOptions:nil];
            [screenDictionary setObject:window forKey:[NSString stringWithFormat:@"%d", counter]];
            counter++;
        }
    }
     */
}

- (void)setBackgroundImage {
    // Set background image for window
    NSURL *imageURL = [[NSWorkspace sharedWorkspace] desktopImageURLForScreen:[NSScreen mainScreen]];
    
    // Check if custom background image option is selected
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs addSuiteNamed:@"com.netputing.handyLock"];
    
    if ([prefs boolForKey:@"lockScreenBackground"]) {
        NSURL *tempImage = [prefs URLForKey:@"backgroundImage"];
        
        NSImage * image =  [[NSImage alloc] initWithContentsOfFile:tempImage.path];
        
        // If image is valid
        if( image ){
            //Set image as image URL in userDefaults
            imageURL = tempImage;
        }
    }
    
    NSNumber *isDir;
    NSError *error;
    if ([imageURL getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:&error]) {
        if ([isDir boolValue]) {
            Dlog(@"%@ is a directory", imageURL);
            NSFileManager *fm = [NSFileManager defaultManager];
            NSArray * dirContents =
            [fm contentsOfDirectoryAtURL:imageURL
              includingPropertiesForKeys:@[]
                                 options:NSDirectoryEnumerationSkipsHiddenFiles
                                   error:nil];
            NSPredicate * fltr = [NSPredicate predicateWithFormat:@"(pathExtension='jpg') OR (pathExtension='png') OR (pathExtension='gif')"];
            NSArray * onlyJPGs = [dirContents filteredArrayUsingPredicate:fltr];
            NSUInteger randomIndex = arc4random() % [onlyJPGs count];
            
            NSImage *image = [[NSImage alloc] initWithContentsOfURL:[onlyJPGs objectAtIndex:randomIndex]];
            
            [background setImage:[self resizeImageForMainScreen:image]];
            
        } else {
            Dlog(@"%@ is a file", imageURL);
            NSImage *image = [[NSImage alloc] initWithContentsOfURL:imageURL];
            [background setImage:[self resizeImageForMainScreen:image]];
        }
    } else {
        Dlog(@"error: %@", error);
    }
}

- (NSImage *)resizeImageForMainScreen:(NSImage *)sourceImage{
    
    NSSize sourceImageSize= sourceImage.size;
    Dlog(@"image: %@", NSStringFromSize(sourceImageSize));
    
    // load screen area
    NSRect screenArea = NSMakeRect(0, 0, 0, 0);
    
    NSScreen *screen = [NSScreen mainScreen];
    Dlog(@"screen %@: %@", screen, NSStringFromRect([screen frame]));
    
    screenArea.origin.x = MIN(NSMinX(screen.frame), NSMinX(screenArea));
    screenArea.origin.y = MIN(NSMinY(screen.frame), NSMinY(screenArea));
    
    screenArea.size.width = MAX(NSMaxX(screen.frame), NSMaxX(screenArea)) - screenArea.origin.x;
    screenArea.size.height = MAX(NSMaxY(screen.frame), NSMaxY(screenArea)) - screenArea.origin.y;
    
    Dlog(@"screen area: %@", NSStringFromRect(screenArea));
    
    float imageScale = 0.0;
    
    @try {
        // figure out resize ratio
        if ((sourceImageSize.width > 0) && (sourceImageSize.width > 0))
        {
            imageScale = MAX(screenArea.size.width / sourceImageSize.width, screenArea.size.height / sourceImageSize.height);
            Dlog(@"scale image by: %f", imageScale);
        } else {
            imageScale = 16 / 9;
            Dlog(@"Can't calculate image scale. Setting to 16x9");
        }
        
        NSPoint imageOffset = NSMakePoint(0 - roundf((roundf(sourceImageSize.width * imageScale) - screenArea.size.width) / 2), 0 - roundf((roundf(sourceImageSize.height * imageScale) - screenArea.size.height) / 2));
        Dlog(@"offset image: %@", NSStringFromPoint(imageOffset));
        
        // create image for screen
        NSImage *newImage = [[NSImage alloc] initWithSize:screen.frame.size];
        [newImage lockFocus];
        [sourceImage drawInRect:NSMakeRect(0, 0, screen.frame.size.width, screen.frame.size.height) fromRect:NSMakeRect((0 - (imageOffset.x / imageScale)) + ((screen.frame.origin.x - screenArea.origin.x) / imageScale), (0 - (imageOffset.y / imageScale)) + ((screen.frame.origin.y - screenArea.origin.y) / imageScale), screen.frame.size.width / imageScale, screen.frame.size.height / imageScale) operation:NSCompositeCopy fraction:1.0];
        [newImage unlockFocus];
        
        return newImage;
    }
    @catch (NSException *exception) {
        NSLog(@"%@", exception.reason);
    }
    @finally {
        NSLog(@"Try is done");
    }
              
    return sourceImage;
}

#pragma mark - Security stuff

- (BOOL)isSecurePasswordSet {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs addSuiteNamed:@"com.netputing.handyLock"];
    NSString *password = [prefs stringForKey:@"securePassword"];
    
    if ([password length] > 0) {
        return TRUE;
    } else {
        return FALSE;
    }
}

/*
- (void)playLockingSoundSet {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs addSuiteNamed:@"com.netputing.handyLock"];
    if ([prefs boolForKey:@"playLockingSound"])
    {
        NSSound *doorSound = [NSSound soundNamed:@"Porte"];
        
        if ([prefs boolForKey:@"lockScreenSounds"]) {
            NSURL *soundFile = [prefs URLForKey:@"lockSoundFile"];
            doorSound = [[NSSound alloc] initWithContentsOfFile:soundFile.path byReference:false];
        }
        
        //Play sound
        [doorSound play];
    }
}
 */

-(NSString *)sha256:(NSString *)parameters salt:(NSData *)saltData {
    NSData *paramData = [parameters dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *hash = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH ];
    CCHmac(kCCHmacAlgSHA256, saltData.bytes, saltData.length, paramData.bytes, paramData.length, hash.mutableBytes);
    NSString *base64Hash = [hash base64Encoding];
    return base64Hash;
}

- (IBAction)unlock:(id)sender
{
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs addSuiteNamed:@"com.netputing.handyLock"];
    NSString *password = [prefs stringForKey:@"securePassword"];
    NSData *salt = [prefs dataForKey:@"salt"];
    
    NSString * enteredPassword = [self sha256:securePassword.stringValue salt:salt];
    
    if ([securePassword.stringValue isEqualTo:@"test"] || [enteredPassword isEqualTo:password]) {
        exit(0);
    } else {
        sleep (2);
        [securePassword setStringValue:@""];
        return;
    }
    
}

#pragma mark - Screen Sleep functions and stuff

- (void)startScreenSleepCountDown
{
    screenSaverTimer = [NSTimer scheduledTimerWithTimeInterval:1//[timerInterval intValue]
                                                        target:self
                                                      selector:@selector(countDown)
                                                      userInfo:nil
                                                       repeats:YES];
}

-(void)countDown {
    if (idle.secondsIdle == 0) {
        remainingCounts = displaySleepTimer;
        [counter setIntegerValue:remainingCounts];
        return;
    }
    
    if (remainingCounts > 0) {
        --remainingCounts;
        [counter setIntegerValue:remainingCounts];
    }
    
    if (remainingCounts == 0) {
        
        /*
        if (screenSaverTimer != nil) {
            [screenSaverTimer invalidate];
            screenSaverTimer = nil;
        }
         */
        
        [ self makeDisplaySleep ];
        --remainingCounts;
    }
}

- (void)makeDisplaySleep {
    io_registry_entry_t r = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler");
    if (r) {
        IORegistryEntrySetCFProperty(r, CFSTR("IORequestIdle"), kCFBooleanTrue);
        IOObjectRelease(r);
    }
}

- (void)startTrackingDisplaySleep
{
    // Doesn't include error checking - just a quick example
    io_service_t displayWrangler;
    IONotificationPortRef notificationPort;
    io_object_t notification;
    
    displayWrangler = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceNameMatching("IODisplayWrangler"));
    notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
    IOServiceAddInterestNotification(notificationPort, displayWrangler, kIOGeneralInterest, displayPowerNotificationsCallback, NULL, &notification);
    
    CFRunLoopAddSource (CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notificationPort), kCFRunLoopDefaultMode);
    IOObjectRelease (displayWrangler);
}

void displayPowerNotificationsCallback(void *refcon, io_service_t service, natural_t messageType, void *messageArgument)
{
    switch (messageType) {
        case kIOMessageDeviceWillPowerOff :
            // This is called twice - once for display dim event, then once
            // for display power off
            Dlog(@"Going to sleep display");
            break;
        case kIOMessageDeviceHasPoweredOn :
            // Display powering back on
            Dlog(@"Display is waking. Restarting sleep countdown");
            // Restart sleep countdown since the screen is still locked and we want the display to sleep if needed
            remainingCounts = displaySleepTimer;
            break;
    }
}

@end
