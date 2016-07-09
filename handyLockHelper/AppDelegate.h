//
//  AppDelegate.h
//  handyLockHelper
//
//  Created by Bernard Maltais on 9/7/2013.
//  Copyright (c) 2013 Netputing Systems Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "IdleTimer.h"

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    
    __weak IBOutlet NSWindow *lockWindow;
    __weak IBOutlet NSWindow *window2;
    __weak IBOutlet NSSecureTextField *securePassword;
    NSTimer *screenSaverTimer;
    IdleTime * idle;
    __weak IBOutlet NSTextField *counter;
    __weak IBOutlet NSImageView *background;
}

//@property (assign) IBOutlet NSWindow *window;

- (void)startScreenSleepCountDown;

@end
