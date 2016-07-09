//
//  AppDelegate.m
//  handyLock
//
//  Created by Bernard Maltais on 9/7/2013.
//  Copyright (c) 2013 Netputing Systems Inc. All rights reserved.
//

#import "AppDelegate.h"
#import "DebugOutput.h"
#import <Security/Security.h>
//#import "HLKeychainBindings.h"
//#import "HLKeychainBindingsController.h"
#include <IOKit/IOMessage.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <CommonCrypto/CommonHMAC.h>

@implementation AppDelegate

@synthesize appWindow=__appWindow;
@synthesize fileMonitor=__fileMonitor;
@synthesize reactionSpeed=_reactionSpeed;
@synthesize lockScreenMethodButton;
//@synthesize lockScreenBackgroundButton;
//@synthesize setBackgroundButton;
@synthesize delayBeforeLocking;
@synthesize panel;

static bool gLockScreenOn = FALSE;
static bool gEnabledLockEngine = TRUE;
static bool gIsTryingToConnect = FALSE;
static NSInteger gBTPollFrequency = 0;
static connectionTime = 0;
// static NSString *serviceName = @"com.netputing.handyLock";
static double lowpassRSSI = 0;
// static bool gAboutToSleepDisplay = FALSE;
//static int gNoConnectionCount = 0;
static bool gMonitoringStarted = FALSE;
//static int lockStateChange = 0;
static NSUInteger innactivityOffset = 0;
static double baseDBM = -45;
static bool screenIsLockedByOSX = false;

#pragma mark -
#pragma mark Delegate Methods

+ (void)initialize
{
    // get real path of plist file.
    NSString *userDefaultsValuesPath=[[NSBundle mainBundle] pathForResource:@"defaults" ofType:@"plist"];
    
    // load the default values for the user defaults
    NSDictionary *userDefaultsValuesDict=[NSDictionary dictionaryWithContentsOfFile:userDefaultsValuesPath];
    
    // set them in the standard user defaults
    [[NSUserDefaults standardUserDefaults] registerDefaults:userDefaultsValuesDict];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    if (gLockScreenOn)
        return NSTerminateLater;
    else
        return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	[self stopMonitoring];
    [device closeConnection];
    [self userDefaultsSave];
}

- (void)awakeFromNib
{
    [ self checkExpiration ];
    if (![self BTPowerState])
        NSRunAlertPanel( @"handyLock", @"Bluetooth does not appear to be turned ON on your Mac. handyLock will not function properly until Bluetooth is turned on.", @"OK, I understand!", nil, nil, nil );
    
    priorStatus = OutOfRange;
    
    [self createMenuBar];
    
    inRangeImage = [NSImage imageNamed:@"lock"];
    [inRangeImage setTemplate:YES];
    [statusItem setImage:inRangeImage];
	[self userDefaultsLoad];
    [ self setVersionStrings ];
    [ self updateMenuItems];
    [ self detectIfScreenIsLockedOrUnlocked ];
    
    idle  = [ [ IdleTime alloc ] init ];
    
}

- (void)windowWillClose:(NSNotification *)aNotification
{
	[self userDefaultsSave];
	[self stopMonitoring];
    priorStatus = InRange;
    // gEnabledLockEngine = TRUE;
	[self startMonitoring];
}

#pragma mark - login start stuff

-(void) addAppAsLoginItem:(NSString *)appPath
{
    // Call using [ self addAppAsLoginItem:[ bundle bundlePath ]];
    
    CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
    
    // Create a reference to the shared file list.
    // We are adding it to the current user only.
    // If we want to add it all users, use
    // kLSSharedFileListGlobalLoginItems instead of
    //kLSSharedFileListSessionLoginItems
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems,
                                                            NULL);
    if (loginItems)
    {
        //Insert an item to the list.
        LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems,
                                                                     kLSSharedFileListItemLast,
                                                                     NULL,
                                                                     NULL,
                                                                     url,
                                                                     NULL,
                                                                     NULL);
        if (item)
        {
            CFRelease(item);
        }
    }
    
    if (loginItems)
    {
        CFRelease(loginItems);
    }
}

-(void) deleteAppAsLoginItem:(NSString *)appPath
{
	// NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
    
	// Create a reference to the shared file list.
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems, NULL);
    
	if (loginItems) {
		UInt32 seedValue;
		//Retrieve the list of Login Items and cast them to
		// a NSArray so that it will be easier to iterate.
		NSArray  *loginItemsArray = (NSArray *)CFBridgingRelease(LSSharedFileListCopySnapshot(loginItems, &seedValue));
		
		for(int i=0 ; i< [loginItemsArray count]; i++)
        {
			LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)loginItemsArray[i];
			//Resolve the item with URL
			if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &url, NULL) == noErr)
            {
				NSString * urlPath = [(__bridge NSURL*)url path];
                NSRange aRange = [urlPath rangeOfString:appPath];
                if (aRange.location != NSNotFound)
                {
                    //if ([urlPath compare:appPath] == NSOrderedSame){
					LSSharedFileListItemRemove(loginItems,itemRef);
				}
			}
		}
	}
}

-(BOOL) checkAppFromLoginItem:(NSString *)appPath
{
    BOOL retval = NO;
    
    // This will retrieve the path for the application
    // For example, /Applications/test.app
    //
    CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
    
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL,
                                                            kLSSharedFileListSessionLoginItems, NULL);
    
    if (loginItems)
    {
        UInt32 seedValue;
        //
        // Retrieve the list of Login Items and cast them to
        // a NSArray so that it will be easier to iterate.
        //
        NSArray  *loginItemsArray = (__bridge NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
        
        for(int i=0; i< [loginItemsArray count]; i++)
        {
            LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)loginItemsArray[i];
            //
            // Resolve the item with URL
            //
            if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &url, NULL) == noErr)
            {
                NSString * urlPath = [(__bridge NSURL*)url path];
                if ([urlPath compare:appPath] == NSOrderedSame)
                {
                    retval = YES;
                    break;
                }
            }
        }
        
        CFRelease(loginItems);
        CFRelease((__bridge CFTypeRef)(loginItemsArray));
    }
    
    return retval;
}

- (void)detectIfScreenIsLockedOrUnlocked {
    NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
    /*
    [center addObserver:self
               selector:@selector(screenLocked)
                   name:@"com.apple.screenIsLocked"
                 object:nil
     ];
    [center addObserver:self
               selector:@selector(screenUnlocked)
                   name:@"com.apple.screenIsUnlocked"
                 object:nil
     ];
     */
    [center addObserver:self
               selector:@selector(screenLocked)
                   name:@"com.apple.sessionDidMoveOffConsole"
                 object:nil
     ];
    [center addObserver:self
               selector:@selector(screenUnlocked)
                   name:@"com.apple.sessionDidMoveOnConsole"
                 object:nil
     ];
    
    // The following section will log Notifications name seen on the Mac
    
    /*
    [center addObserver: self
               selector:@selector(receive:)
                   name:nil
                 object:nil
     ];
     */
}

-(void) receive: (NSNotification*) notification {
    //printf("%s\n", [[notification name] UTF8String] );
    [self logToFile:[NSString stringWithFormat:@"Notification name: %@\n",[notification name]]];
}

- (void)screenLocked
{
    Dlog(@"Screen is locked!");
    screenIsLockedByOSX = true;
    [self runInRangeScript];
    
}
- (void)screenUnlocked
{
    Dlog(@"Screen is unlocked!");
    screenIsLockedByOSX = false;
}

#pragma mark -
#pragma mark AppController Methods

- (void)createMenuBar
{
	//NSMenu *myMenu;
	//NSMenuItem *menuItem;
    
	// Menu for status bar item
	myMenu = [[NSMenu alloc] init];
    [myMenu insertItemWithTitle:@"Preferences..." action:@selector(showWindow:) keyEquivalent:@"" atIndex:0];
    [myMenu insertItemWithTitle:@"Disable handyLock" action:@selector(handleEnaDisaMenuItem) keyEquivalent:@"" atIndex:1];
    //[myMenu insertItemWithTitle:@"Lock my Mac" action:@selector(lockWithOSXLogin) keyEquivalent:@"l" atIndex:2];
    
    // Prefences menu item
	//menuItem = [myMenu addItemWithTitle:@"Preferences..." action:@selector(showWindow:) keyEquivalent:@""];
	//[menuItem setTarget:self];
    //[myMenu addItemWithTitle:@"Disable handyLock" action:@selector(enableLocking:) keyEquivalent:@""];
    
    // Separator
    [myMenu addItem:[NSMenuItem separatorItem]];
	
	// Quit menu item
	[myMenu addItemWithTitle:@"Quit handyLock" action:@selector(terminate:) keyEquivalent:@""];
	
	// Space on status bar
	statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
	
	// Attributes of space on status bar
	[statusItem setHighlightMode:YES];
	[statusItem setMenu:myMenu];
    
	//[self menuIconOutOfRange];
}

-(void)updateMenuItems
{
    //NSMenuItem *menuItem;
    
    // Menu for status bar item
    [myMenu removeItemAtIndex:1];
    if ([lockingEnabled state]) {
        [myMenu insertItemWithTitle:@"Disable handyLock" action:@selector(handleEnaDisableHandyLockMenuAction) keyEquivalent:@"" atIndex:1];
    } else {
        [myMenu insertItemWithTitle:@"Enable handyLock" action:@selector(handleEnaDisableHandyLockMenuAction) keyEquivalent:@"" atIndex:1];
    }
}

// This is used when the user click directly on the on off button
- (IBAction)handleEnaDisableHandyLock:(id)sender {
    if ([lockingEnabled state]) {
        if ([ self canIActivate]) {
            [self enableLocking];
        } else {
            [self disableLocking];
        }
    } else {
        [self disableLocking];
    }
}

// This is used when the user select the menu item
- (void)handleEnaDisableHandyLockMenuAction {
    if ([lockingEnabled state]) {
        [self disableLocking];
    } else {
        if ([ self canIActivate]) {
            [self enableLocking];
        }
    }
}

- (void)handleTimer:(NSTimer *)theTimer
{
	if( [self isInRange] )
	{
		if( priorStatus == OutOfRange )
		{
			priorStatus = InRange;
			
			//[self menuIconInRange];
			[self runInRangeScript];
		}
	}
	else
	{
		if( priorStatus == InRange )
		{
			priorStatus = OutOfRange;
			
			innactivityOffset = idle.secondsIdle;
		}
        
        if ((idle.secondsIdle - innactivityOffset ) >= [delayBeforeLocking integerValue]) {
            [self runOutOfRangeScript];
        } else {
            Dlog(@"Wait time to lock: %lu", (idle.secondsIdle - innactivityOffset ));
        }

	}
}

#pragma mark - Bluetooth functions

- (bool)BTPowerState
{
    return IOBluetoothPreferenceGetControllerPowerState();
}

- (void)connectDevice
{
    Dlog(@"Told to connect to device");
    /*
    if (!gIsTryingToConnect) {
        gIsTryingToConnect = TRUE;
        Dlog(@"Trying to connect to %@", [device name])
        [device openConnection];
    }
     */
    gIsTryingToConnect = true;
    [device openConnection];
    gIsTryingToConnect = false;
    connectionTime = 0;
}

- (void)reconnectDevice
{
    //Dlog(@"Told to connect to device");
    /*
     if (!gIsTryingToConnect) {
     gIsTryingToConnect = TRUE;
     Dlog(@"Trying to connect to %@", [device name])
     [device openConnection];
     }
     */
    [device closeConnection];
    gIsTryingToConnect = true;
    connectionTime = 0;
    [device openConnection];
    gIsTryingToConnect = false;
}

- (BOOL)isInRange
{
    // Decrement counter
    //[self getLockStateChangeTime];
    
    BluetoothHCIRSSIValue RSSI = [nearReading doubleValue]; /* Valid Range: -127 to +20 */
    
    if (device) {
        if (![device isConnected])
        {
            if (!gIsTryingToConnect) {
                gIsTryingToConnect = true;
                // Run on a seperate thread
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    [self connectDevice];
                });
            }
            
            [self logToFile:[NSString stringWithFormat:@"-127,%@\n", [farReading stringValue]]];
            
            if (idle.secondsIdle == 0 && !gLockScreenOn) {
                return true;
            } else {
                return false;
            }
        }
        else
        {
            connectionTime = connectionTime + btPollFrequency.intValue;

            RSSI = [device rawRSSI];
            
            // The followinf if disconnect and reconnect to the device to prevent a disconnect bug after 60 seconds
            
            if (connectionTime > 50) {
                [self stopMonitoring];
                // Run on a seperate thread
                dispatch_async(dispatch_get_global_queue(0, 0), ^{
                    [self reconnectDevice];
                });
                sleep(2);
                [self startMonitoring];
            }
            
            
            if (RSSI < -127 || RSSI > 20) {
                return false;
            }
            
            [nearReading setIntegerValue:RSSI];
            
            if (!gLockScreenOn)
            {
                //if (RSSI > lowpassRSSI) {
                //    lowpassRSSI = RSSI;
                //} else {
                    lowpassRSSI = ([self.reactionSpeed doubleValue] * lowpassRSSI) + ((1.0 - [self.reactionSpeed doubleValue]) * RSSI);
                //}
                
            }
            else
            {
                lowpassRSSI = RSSI;
            }
            
            [signalStrength setStringValue:[NSString stringWithFormat:@"%.02f", lowpassRSSI]];
            [signalStrenghtGage setFloatValue:[[NSNumber numberWithChar:lowpassRSSI] floatValue]];
            [self logToFile:[NSString stringWithFormat:@"%.02f,%@\n", lowpassRSSI, [farReading stringValue]]];
            
            // If there is activity on the computer and the screen is not locked then let's adjust the base balue to the new value
            if ((idle.secondsIdle == 0 && !gLockScreenOn) || [[farReading stringValue] isEqualTo:@"0"]) {
                NSInteger distanceRangeVal = [[distanceRange stringValue] integerValue];
                
                // CHeck if new signal reading - distance range is less than current far reading. If yes lower value right away. If not then apply lowpass when raising value to prevent increasing out of range value too quickly
                //if ((RSSI - distanceRangeVal) < [farReading doubleValue]) {
                    [farReading setStringValue:[NSString stringWithFormat:@"%.02f", [signalStrength floatValue] - distanceRangeVal]];
                //} else {
                //    double tempVal = ([self.reactionSpeed doubleValue] * [farReading doubleValue]) + ((1.0 - [self.reactionSpeed doubleValue]) * RSSI);
                //    [farReading setStringValue:[NSString stringWithFormat:@"%.02f", tempVal - distanceRangeVal]];
                //}
                
                [signalStrenghtGage setWarningValue:[nearReading doubleValue]-(distanceRangeVal/2)];
                [signalStrenghtGage setCriticalValue:[nearReading doubleValue]-distanceRangeVal+1];
                
                //[ self setSensitivity:self ];
                Dlog(@"Setting new base value to RSSI value");
            }
            
            //-- Calculate device distance based on RSSI signal strenght --
            
            if (idle.secondsIdle == 0) {
                baseDBM = [signalStrenghtGage floatValue];
            }
            
            //float A = [farReading floatValue] + [[distanceRange stringValue] integerValue];
            // float A = -46.0; // Reference RSSI value at 1 meter
            float n = 2; // Path-loss exponent inside
            float distance;
            
            distance = pow(10.0,((baseDBM - lowpassRSSI)/(10.0*n)));
            //[deviceDistance setFloatValue:distance];
            [deviceDistance setStringValue:[NSString stringWithFormat:@"%.02f", distance]];
            
            //--
            
            return (lowpassRSSI >= [farReading doubleValue]);
        }
    }
    
    return false;
}

- (void)menuIconInRange
{
	//[statusItem setImage:inRangeImage];
	//[statusItem setAlternateImage:inRangeAltImage];
    
	//[statusItem	setTitle:@"O"];
}

- (void)menuIconOutOfRange
{
	//[statusItem setImage:outOfRangeImage];
	//[statusItem setAlternateImage:outOfRangeAltImage];
    
    //	[statusItem setTitle:@"X"];
}

- (BOOL)newVersionAvailable
{
    Dlog(@"Checking for new version");
    
    NSString *thisShortVersion = [[ NSBundle bundleForClass: [ self class ]] infoDictionary ][@"CFBundleShortVersionString"];
    NSArray *thisVersion = [thisShortVersion componentsSeparatedByString:@"."];
    int curVersionMajor = [thisVersion[0] intValue];
	int curVersionMinor = [thisVersion[1] intValue];
    int curVersionMicro = [thisVersion[2] intValue];
    // int curVersionPico = [thisVersion[3] intValue];
    
    Dlog(@"Got this version from application: %@.", thisShortVersion );
    
    // Get latest version from url
    
    NSURL *url = [NSURL URLWithString:@"http://netputing.com/files/handylockv1"];
    // NSURL *url = [NSURL URLWithString:@"http://netputing.com/app/latest.html"];
    NSData *textData = [NSData dataWithContentsOfURL:url];
    NSString *verString = [[NSString alloc] initWithData:textData encoding:NSASCIIStringEncoding];
    NSArray *version = [verString componentsSeparatedByString:@"."];
	
	int newVersionMajor  = [version[0] intValue];
	int newVersionMinor = [version[1] intValue];
    int newVersionMicro = [version[2] intValue];
    
    int newVersionTotal = (newVersionMicro * 10) + (newVersionMinor *100) + (newVersionMajor * 1000);
    int curVersionTotal = (curVersionMicro * 10) + (curVersionMinor *100) + (curVersionMajor * 1000);
    
    if (curVersionTotal < newVersionTotal) {
        return TRUE;
    }
	
	return NO;
}

- (void)runInRangeScript
{
    if (gLockScreenOn) {
        gLockScreenOn = FALSE;
        
        NSNotificationCenter *center = [[NSWorkspace sharedWorkspace] notificationCenter];
        [center removeObserver:self name:NSWorkspaceDidTerminateApplicationNotification object:nil];
        
        [self stopAppHelper];
    }
}

- (void)runOutOfRangeScript
{
    Dlog(@"Idle time %lu", [idle secondsIdle]);
    if ([self canILockTheScreen])
    {
        gLockScreenOn = TRUE;
        
        NSNotificationCenter *center = [[NSWorkspace sharedWorkspace] notificationCenter];
        [center addObserver:self selector:@selector(appTerminated:) name:NSWorkspaceDidTerminateApplicationNotification object:nil];
        
        [self startAppHelper];
    }
}

- (void)startMonitoring
{
	if( !gMonitoringStarted )
	{
        Dlog(@"Was asked to start monitoring");
        gMonitoringStarted = TRUE;
		timer = [NSTimer scheduledTimerWithTimeInterval:[btPollFrequency intValue]//[timerInterval intValue]
												 target:self
											   selector:@selector(handleTimer:)
											   userInfo:nil
												repeats:YES];
        
        pollMonitoringTimer = [NSTimer scheduledTimerWithTimeInterval:1//[timerInterval intValue]
                                                 target:self
                                               selector:@selector(handlePollChange:)
                                               userInfo:nil
                                                repeats:YES];
        
	}
    else
    {
        Dlog(@"Was asked to start monitoring... but already monitoring. Are you nuts?");
    }
}

- (void)restartMonitoring
{
    if (gMonitoringStarted) {
        [self stopMonitoring];
        [self startMonitoring];
    }
}

- (void)stopMonitoring
{
    gMonitoringStarted = FALSE;
    if (timer != nil) {
        [timer invalidate];
        timer = nil;
    }
    
    if (pollMonitoringTimer != nil) {
        [pollMonitoringTimer invalidate];
        pollMonitoringTimer = nil;
    }
}

- (BOOL)isSecurePasswordSet {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSString *password = [prefs stringForKey:@"securePassword"];
    
    if ([password length] > 0) {
        return TRUE;
    } else {
        return FALSE;
    }
}

- (BOOL)canILockTheScreen
{
    if (![ self BTPowerState])
        return FALSE;
    
    if (![self isSecurePasswordSet]) {
        Dlog(@"Can't lock screen, no password set");
        return FALSE;
    }
    
    if (!device)
        return FALSE;
    
    if (gLockScreenOn)
        return FALSE;
    
    if ([lockingEnabled state] == NSOffState)
        return FALSE;
    
    if (!gEnabledLockEngine)
        return FALSE;
    
    if (screenIsLockedByOSX)
        return FALSE;
    
    return TRUE;
}

- (BOOL)canIActivate
{
	if (![self isSecurePasswordSet]) {
        Dlog(@"Can't activate, no password set");
        // We set the checkbox off right away to give the user some feedback before displaying the alert
        [lockingEnabled setState:false];
        NSRunAlertPanel( @"handyLock", @"Can't activate handyLock, no security password set. Please set a password in the following window.", @"Close", nil, nil, nil );
        //[self setPasswordButton:nil];
        [self openPasswordWindow:nil];
        return FALSE;
    }
    
    if (!device) {
        Dlog(@"Can't activate, no device configured");
        // We set the checkbox off right away to give the user some feedback before displaying the alert
        [lockingEnabled setState:false];
        NSRunAlertPanel( @"handyLock", @"Can't activate, no device configured.", @"Close", nil, nil, nil );
        return FALSE;
    }
    
    return TRUE;
}

- (void)userDefaultsLoad
{
	NSUserDefaults *defaults;
	NSData *deviceAsData;
	
	defaults = [NSUserDefaults standardUserDefaults];
    // Check if a bool key is set in the defaults file. If it is not then the defaults file is not there or invalid.
    if ([defaults objectForKey:@"updating"])
    {
        // Device
        deviceAsData = [defaults objectForKey:@"device"];
        if( [deviceAsData length] > 0 )
        {
            device = [NSKeyedUnarchiver unarchiveObjectWithData:deviceAsData];
            [deviceName setStringValue:[NSString stringWithFormat:@"%@ (%@)",
                                        [device nameOrAddress], [device addressString]]];
            priorStatus = InRange;
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                [self connectDevice];
            });
        }
        
        // Distance range
        if( [[defaults stringForKey:@"distanceRange"] length] > 0 )
        {
            [distanceRange setStringValue:[defaults stringForKey:@"distanceRange"]];
            
        }
        
        // Reaction speed
        if( [[defaults stringForKey:@"reactionSpeed"] length] > 0 )
        {
            [self.reactionSpeed setStringValue:[defaults stringForKey:@"reactionSpeed"]];
            
        }
        
        // Display sleep timer
        if( [[defaults stringForKey:@"displaySleepTimer"] length] > 0 )
        {
            [displaySleepTimer setStringValue:[defaults stringForKey:@"displaySleepTimer"]];
        }
        
        /*
        // Near Reading
        if ([[defaults stringForKey:@"nearReading"] length] > 0 )
        {
            [nearReading setStringValue:[defaults stringForKey:@"nearReading"]];
            
            [self setSensitivity:self];
        }
         */
        
        // Distance range
        if( [[defaults stringForKey:@"btPollFrequency"] length] > 0 )
        {
            gBTPollFrequency = [defaults integerForKey:@"btPollFrequency"];
        }
        
        // Check for updates on startup
        [ checkUpdatesOnStartup setState:[defaults boolForKey:@"updating"] ? NSOnState : NSOffState];
        if( [ checkUpdatesOnStartup state ] ) {
            if( [self newVersionAvailable] )
            {
                if( NSRunAlertPanel( @"handyLock", @"A new version of handyLock is available for download.",
                                    @"Close", @"Download", nil, nil ) == NSAlertAlternateReturn )
                {
                    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://netputing.com/applications/handylock/"]];
                }
            }
        }
        
        // Locking enabled
        [ lockingEnabled setState:[defaults boolForKey:@"enabled"] ? NSOnState : NSOffState];
        [self setDisplayTextColor];
        if(  [ lockingEnabled state] ) {
            [ self startMonitoringFiles ];
        }
        
        // Start at login enabled
        [ startAtLoginCheckbox setState:[defaults boolForKey:@"startAtLogin"] ? NSOnState : NSOffState];
        //BOOL startAtLogin = [defaults boolForKey:@"startAtLogin"];
        
        
        // Hide application on startup
        [ hideApplicationOnStartup setState:[defaults boolForKey:@"hideApplicationOnStartup"] ? NSOnState : NSOffState];
        //BOOL hideOnStartup = [defaults boolForKey:@"hideApplicationOnStartup"];
        if( [ hideApplicationOnStartup state ] ) {
            [ self hideWindow];
            //[ self showWindow:self];
        }
    }
    
    [self startMonitoring];
}

- (void)userDefaultsSave
{
	NSUserDefaults *defaults;
	NSData *deviceAsData;
	
	defaults = [NSUserDefaults standardUserDefaults];
	
	// Locking enabled
	BOOL locking = ( [lockingEnabled state] == NSOnState ? TRUE : FALSE );
	[defaults setBool:locking forKey:@"enabled"];
	
	// Update checking
	BOOL updating = ( [checkUpdatesOnStartup state] == NSOnState ? TRUE : FALSE );
	[defaults setBool:updating forKey:@"updating"];
    
    // Hide application on startup
	BOOL hideOnStartup = ( [hideApplicationOnStartup state] == NSOnState ? TRUE : FALSE );
	[defaults setBool:hideOnStartup forKey:@"hideApplicationOnStartup"];
    
    // Start at login
	BOOL startAtLogin = ( [startAtLoginCheckbox state] == NSOnState ? TRUE : FALSE );
	[defaults setBool:startAtLogin forKey:@"startAtLogin"];
	
	// Distance range
	[defaults setObject:[distanceRange stringValue] forKey:@"distanceRange"];
    
    // Reaction speed
	[defaults setObject:[self.reactionSpeed stringValue] forKey:@"reactionSpeed"];
    
    /*
    // Near reading
    [defaults setObject:[nearReading stringValue] forKey:@"nearReading"];
     */
    
    // Display Sleep
    [defaults setObject:[displaySleepTimer stringValue] forKey:@"displaySleepTimer"];
    
    
    // BT Poll Frequency
    [defaults setObject:[btPollFrequency stringValue] forKey:@"btPollFrequency"];
    
    //
    [defaults setObject:[outOfRangeAppField stringValue] forKey:@"outOfRangeApp"];
    [defaults setObject:[inRangeAppField stringValue] forKey:@"inRangeApp"];
    
	// Device
	if( device ) {
		deviceAsData = [NSKeyedArchiver archivedDataWithRootObject:device];
		[defaults setObject:deviceAsData forKey:@"device"];
	}
    else
    {
        [defaults removeObjectForKey:@"device"];
    }
	
	[defaults synchronize];
}

/*
#pragma mark - Screen Sleep functions and stuff

- (void)enableScreenSaver
{
    // if ([self getSystemSleepDisplayTimer] > 0) {
    if ([displaySleepTimer intValue] > 0) {
        gRestartSleepTimer = TRUE;
        [self startScreenSleepCountDown];
    }
}

- (void)disableScreenSaver
{
    gScreenSleepTimerCountDown = -1;
    [self stopScreenSleepCountDown];
}

- (void)startScreenSleepCountDown
{
    screenSaverTimer = [NSTimer scheduledTimerWithTimeInterval:1//[timerInterval intValue]
                                                        target:self
                                                      selector:@selector(sleepDisplay:)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)stopScreenSleepCountDown
{
    if (screenSaverTimer != nil) {
        [screenSaverTimer invalidate];
        screenSaverTimer = nil;
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
            Dlog(@"Display is waking");
            if (gLockScreenOn) {
                Dlog(@"Restarting sleep countdown");
                // Restart sleep countdown since the screen is still locked and we want the display to sleep if needed
                gRestartSleepTimer = TRUE;
            }
            break;
    }
}

- (void)startScreenSaver
{
    
    [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/Frameworks/ScreenSaver.framework/Versions/A/Resources/ScreenSaverEngine.app"];
    
}


- (void)sleepMAC
{
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:@"tell application \"System Events\" to sleep"];
    NSDictionary *errorInfo;
    [script executeAndReturnError:&errorInfo];
}

- (void)makeDisplaySleep {
    io_registry_entry_t r = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler");
    if (r) {
        IORegistryEntrySetCFProperty(r, CFSTR("IORequestIdle"), kCFBooleanTrue);
        IOObjectRelease(r);
    }
}

- (void)sleepDisplay:(NSTimer *)theTimer
{
    if (gRestartSleepTimer)
    {
        gRestartSleepTimer = FALSE;
        gScreenSleepTimerCountDown = [ displaySleepTimer intValue ] * 60;
        // gScreenSleepTimerCountDown = [self getSystemSleepDisplayTimer] * 60;
    }
    else
    {
        if (gScreenSleepTimerCountDown == 0)
        {
            [self makeDisplaySleep];
        }
        
        if (idle.secondsIdle == 0) {
            Dlog(@"User was active on computer. Resetting sleep timer");
            gScreenSleepTimerCountDown = [ displaySleepTimer intValue ] * 60;
        }
        
        if (gScreenSleepTimerCountDown > -1) {
            Dlog(@"Reducing by 1: %d", gScreenSleepTimerCountDown);
            gScreenSleepTimerCountDown = gScreenSleepTimerCountDown - 1;
        }
    }
}

- (NSInteger)getSystemSleepDisplayTimer
{
    NSString *path = @"/Library/Preferences/SystemConfiguration/com.apple.PowerManagement.plist";
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:path]) {
        Dlog(@"The file exists");
        NSDictionary *myDic = [[NSDictionary alloc] initWithContentsOfFile:path];
        NSDictionary *customProfile = myDic[@"Custom Profile"];
        NSDictionary *acPower = customProfile[@"AC Power"];
        NSInteger sleepTimer = [acPower[@"Display Sleep Timer"] integerValue];
        return sleepTimer;
        
    } else {
        Dlog(@"The file does not exist");
        return 0;
    }
}
 */

#pragma mark - App version functions

- (NSString *) currentVersion
{
    NSDictionary * bundleDictionary = [[ NSBundle bundleForClass: [ self class ]] infoDictionary ];
    NSString *thisVersion = bundleDictionary[@"CFBundleVersion"];
    
    return thisVersion;
}

- (void)setVersionStrings
{
    NSString *versionString = [ NSString stringWithFormat:@"v%@", [ self currentVersion ]];
    
    [aboutVersionTextField setStringValue:versionString ];
}

#pragma mark -
#pragma mark Interface Methods

- (IBAction)changeDevice:(id)sender
{
    [progressIndicator setHidden:FALSE];
    [progressIndicator startAnimation:nil];
    
    [deviceName setStringValue:@"Select the desired Bluetooth device for proximity lock"];
    [lockingEnabled setState:NSOffState];
    
	IOBluetoothDeviceSelectorController *deviceSelector;
	deviceSelector = [IOBluetoothDeviceSelectorController deviceSelector];
	[deviceSelector runModal];
	
	NSArray *results;
	results = [deviceSelector getResults];
	
	if( !results )
    {
        if (device) {
            [ device closeConnection];
        }
        
        device = nil;
        [ self userDefaultsSave ];
        
        [progressIndicator stopAnimation:nil];
        [progressIndicator setHidden:TRUE];
        
        return;
    }
    
	device = results[0];
    
    // Attempting to pair with bt device
    // [device requestAuthentication];
    [ self connectDevice ];
    
    sleep(1);
    
    if (![device isPaired]) {
        NSRunAlertPanel( @"handyLock", @"The device is not paired with your Mac. The application will now work properly. Make sure to pair it 1st using the OSX System Preference panel application.", @"OK", nil, nil, nil );
    }
    
    // NSRunAlertPanel( @"handyLock", @"Put your phone in the location where it will typically be located when you work at your Mac.", @"Take reading", nil, nil, nil );
    
    BluetoothHCIRSSIValue RSSI = -50; /* Valid Range: -127 to +20 */
    
    RSSI = [device rawRSSI];
    NSInteger tmpVal = RSSI;
    
    [ nearReading setStringValue:[NSString stringWithFormat:@"%ld", tmpVal]];
    [ farReading setStringValue:[NSString stringWithFormat:@"%ld", tmpVal - [distanceRange integerValue]]];
    
    
	[ deviceName setStringValue:[NSString stringWithFormat:@"%@ (%@)",
                                 [device nameOrAddress],
                                 [device addressString]]];
    [ self userDefaultsSave ];
    
    [progressIndicator stopAnimation:nil];
    [progressIndicator setHidden:TRUE];
}

- (IBAction)removeDevice:(id)sender {
    [deviceName setStringValue:@"Select Bluetooth device"];
    [lockingEnabled setState:NSOffState];
    
	if (device) {
        [ device closeConnection];
    }
    
    device = nil;
    [ self userDefaultsSave ];
}

- (IBAction)checkForUpdates:(id)sender
{
	if( [self newVersionAvailable] )
	{
		if( NSRunAlertPanel( @"handyLock", @"A new version of handyLock is available for download.",
							@"Close", @"Download", nil, nil ) == NSAlertAlternateReturn )
		{
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://netputing.com/applications/handylock/"]];
		}
	}
	else
	{
		NSRunAlertPanel( @"handyLock", @"You have the latest version.", @"Close", nil, nil, nil );
	}
}

- (void)setDisplayTextColor {
    if ([lockingEnabled state]) {
        NSColor *color = [NSColor controlTextColor];
        [BTSignalStrenghtText setTextColor:color];
        [BTSignalStrenghtValueText setTextColor:color];
        [BTSignalStrenghtDBText setTextColor:color];
    } else {
        NSColor *color = [NSColor disabledControlTextColor];
        [BTSignalStrenghtText setTextColor:color];
        [BTSignalStrenghtValueText setTextColor:color];
        [BTSignalStrenghtDBText setTextColor:color];
    }
}

- (void)enableLocking {
    [ lockingEnabled setState:NSOnState ];
    [ self updateMenuItems];
    [ self setDisplayTextColor ];
    [ self userDefaultsSave ];
}

- (void)disableLocking {
    [ lockingEnabled setState:NSOffState ];
    [ self updateMenuItems];
    [ self setDisplayTextColor ];
    [ self userDefaultsSave ];
}

/*
- (IBAction)setSensitivity:(id)sender {
    NSInteger distanceRangeVal = [[distanceRange stringValue] integerValue];
    
    // [farReading setStringValue:[NSString stringWithFormat:@"%f", [nearReading doubleValue] - distanceRangeVal]];
    [farReading setStringValue:[NSString stringWithFormat:@"%f", [signalStrength floatValue] - distanceRangeVal]];
    [signalStrenghtGage setWarningValue:[nearReading doubleValue]-(distanceRangeVal/2)];
    [signalStrenghtGage setCriticalValue:[nearReading doubleValue]-distanceRangeVal+1];
    
    
}
 */

- (IBAction)getHelp:(id)sender {
    NSString *thisVersion = [self currentVersion];
    
    NSMutableString * body = [NSMutableString stringWithFormat:@"handyLock version: %@\n\n", thisVersion];
    
    [body appendFormat:@"Please find my feedback below:\n\n"];
    
    NSString * urlString = [NSString stringWithFormat:@"mailto:support@netputing.com?subject=handyLock Feedback&body=%@", body];
    
    NSString * escapedUrlString = [urlString stringByAddingPercentEscapesUsingEncoding:
                                   NSUTF8StringEncoding];
    BOOL success = [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:escapedUrlString]];
    if (!success)
    {
        Dlog(@"Feedback URL with error: %@", escapedUrlString);
        NSAlert * alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:@"Ok"];
        [alert setMessageText:@"HandyLock encountered an error."];
        [alert setInformativeText:@"It could not open an appropriate email composition window."];
        [alert setAlertStyle:NSCriticalAlertStyle];
        [alert beginSheetModalForWindow:[NSApp mainWindow]  modalDelegate:self didEndSelector:nil contextInfo:nil];
    }
}

- (IBAction)startAtLoginTriggered:(id)sender {
    NSString * appBundle = [[NSBundle mainBundle] bundlePath ];
    
    if ([startAtLoginCheckbox state] == NSOnState) {
        if (![ self checkAppFromLoginItem:appBundle]) {
            [ self addAppAsLoginItem:appBundle];
            if (![ self checkAppFromLoginItem:appBundle]) {
                NSRunAlertPanel(@"Warning!", @"I was not able to add the item to the \"Login Items\" list.", @"OK", nil, nil);
                [startAtLoginCheckbox setState:NSOffState];
            }
            else
            {
                [ self startMonitoringFiles ];
            }
        }
    }
    else
    {
        [ self stopMonitoringFiles ];
        if ([ self checkAppFromLoginItem:appBundle]) {
            NSURL *url = [[NSURL alloc] initWithString:[[NSBundle mainBundle] bundlePath ]];
            NSString * appName = [url.path lastPathComponent];
            [ self deleteAppAsLoginItem:appName];
        }
    }
}

- (IBAction)openWebSite:(id)sender {
    [[ NSWorkspace sharedWorkspace ] openURL:[NSURL URLWithString:@"http://netputing.com/applications/handylock/" ]];
}

- (IBAction)donate:(id)sender {
    [[ NSWorkspace sharedWorkspace ] openURL:[NSURL URLWithString:@"http://www.netputing.com/contact/donatehandylock/" ]];
}

- (IBAction)saveReactionSpeed:(id)sender {
    [ self userDefaultsSave ];
}

- (void)showWindow:(id)sender
{
	// gEnabledLockEngine = FALSE;
    [prefsWindow center];
    [prefsWindow makeKeyAndOrderFront:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)hideWindow
{
    [self.appWindow orderOut:self];
}

- (void)checkExpiration
{
    
    NSDate * now = [NSDate date];
    NSDate * mile = [[NSDate alloc] initWithString:kEXPIRATIONDATE];
    NSComparisonResult result = [now compare:mile];
    
    Dlog(@"%@", now);
    Dlog(@"%@", mile);
    
    if(result==NSOrderedDescending)
    {
        NSRunAlertPanel(@"Version Expired!", @"This test version of handyLock has expired. Please download a new one from http://netputing.com", @"OK", nil, nil);
        
        [[ NSWorkspace sharedWorkspace ] openURL:[NSURL URLWithString:@"http://netputing.com/applications/handylock/" ]];
        
        exit(0);
    }
}

#pragma mark - File Monitoring

- (void) startMonitoringFiles
{
    self.fileMonitor = [[VDKQueue alloc] init];
    self.fileMonitor.delegate = (id)self;
    
    [self.fileMonitor addPath:[[NSBundle mainBundle] bundlePath ]];
}

- (void) stopMonitoringFiles
{
    self.fileMonitor.delegate = nil;
    self.fileMonitor = nil;
}

- (IBAction)clearInRangeApp:(NSButton *)sender {
    [inRangeAppField setStringValue:@""];
    [self userDefaultsSave];
}

- (IBAction)clearOutOfRangeApp:(NSButton *)sender {
    [outOfRangeAppField setStringValue:@""];
    [self userDefaultsSave];
}

- (void) restartMonitoringFiles
{
    [ self stopMonitoringFiles];
    [ self startMonitoringFiles];
}

- (void) handlePollChange:(NSTimer *)theTimer
{
    if (gBTPollFrequency != [btPollFrequency intValue]) {
        gBTPollFrequency = [btPollFrequency intValue];
        [self restartMonitoring];
    }
    [self userDefaultsSave];
}

-(void) VDKQueue:(VDKQueue *)queue receivedNotification:(NSString*)noteName forPath:(NSString*)fpath
{
    Dlog(@"Received notification about path: %@ with notification of: %@", fpath, noteName);
    
    if ([fpath isEqualToString:[[NSBundle mainBundle] bundlePath ]] )
    {
        NSURL *url = [[NSURL alloc] initWithString:[[NSBundle mainBundle] bundlePath ]];
        NSString * appName = [url.path lastPathComponent];
        
        [ self deleteAppAsLoginItem:appName];
        
        [ self stopMonitoringFiles ];
        [ startAtLoginCheckbox setState:NSOffState ];
        [ self userDefaultsSave ];
        
        
        NSRunAlertPanel(@"handyLock", @"handyLock was moved to a new folder. Removing login item for safety. Quit the application before turning \"Start at login\" on again.", @"OK", nil, nil, nil);
    }
}

- (void) startAppHelper
{
    [self playLockingSoundSet];
    
    Dlog(@"Locking selection is: %ld", (long)[lockScreenMethodButton integerValue]);
    [self logToFile:@"Locking screen"];
    
    if ([lockScreenMethodButton indexOfSelectedItem] == 0) {
        [self lockWithOSXLogin];
    } else if ([lockScreenMethodButton indexOfSelectedItem] == 1) {
        [self lockWithScreenSaver];
    } else if ([lockScreenMethodButton indexOfSelectedItem] == 2) {
        [self lockWithHelper];
    } else if ([lockScreenMethodButton indexOfSelectedItem] == 3) {
        [self lockWithOSXLockScreen];
    }
    
    // Check if the option to only run in/out of range was not selected
    if ([lockScreenMethodButton indexOfSelectedItem] != 4) {
        // Start timer to blank screen when we are supposed to since we block the automatic one
        //[ self enableScreenSaver ];
    }
    
    [[NSWorkspace sharedWorkspace] launchApplication:outOfRangeAppField.stringValue];
}

- (void) stopAppHelper
{
    if ([lockScreenMethodButton indexOfSelectedItem] == 2) {
        
        // NSRunAlertPanel(@"handyLock", @"killing lock helper.", @"OK", nil, nil, nil);
        
        [self playUnlockingSoundSet];
        
        NSString * bundleIdentifier = @"com.netputing.handyLockHelper";
        
        NSArray * runningApps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier];
        for (NSRunningApplication * daemon in runningApps)
        {
            [daemon terminate];
        }
    } /* else if ([lockScreenMethodButton indexOfSelectedItem] == 4) {
        [[NSWorkspace sharedWorkspace] launchApplication:inRangeAppField.stringValue];
    } */
    
    [[NSWorkspace sharedWorkspace] launchApplication:inRangeAppField.stringValue];
}

- (void) logToFile:(NSString *)savedString
{
    if (![logToFileCheckbox state]) {
        // Check if we need to log. If not, return;
        return;
    }
    
    NSString *documentTXTPath = [@"~/Documents/handyLockRSSI.csv" stringByExpandingTildeInPath];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath:documentTXTPath])
    {
        [@"Date-Time,RawRSSI,Out of range RSSI\n" writeToFile:documentTXTPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    
    NSDateFormatter *DateFormatter=[[NSDateFormatter alloc] init];
    [DateFormatter setDateFormat:@"yyyy-MM-dd hh:mm:ss"];
    //NSLog(@"%@",[DateFormatter stringFromDate:[NSDate date]]); idle.secondsIdle > [delayBeforeLocking
    NSString *finalString = [NSString stringWithFormat:@"%@,%@", [DateFormatter stringFromDate:[NSDate date]], savedString];
    NSFileHandle *myHandle = [NSFileHandle fileHandleForWritingAtPath:documentTXTPath];
    [myHandle seekToEndOfFile];
    [myHandle writeData:[finalString dataUsingEncoding:NSUTF8StringEncoding]];
    
}

- (void) lockWithOSXLogin
{
    runCommand(@"/System/Library/CoreServices/Menu\\ Extras/User.menu/Contents/Resources/CGSession -suspend");
}

- (void) lockWithHelper
{
    NSString *bundlePath = [[NSBundle mainBundle] resourcePath];
    NSString *srcDaemonApp = [bundlePath stringByAppendingPathComponent:@"handyLockHelper.app"];
    NSURL * fileURL = [NSURL fileURLWithPath: srcDaemonApp];
    [[NSWorkspace sharedWorkspace] launchApplicationAtURL:fileURL
                                                  options:NSWorkspaceLaunchDefault
                                            configuration:nil error:nil];
}

- (void) lockWithScreenSaver
{
    [[ScreenSaverController controller] screenSaverStartNow];
}

- (void) lockWithOSXLockScreen
{
    io_registry_entry_t r = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler");
    if (r) {
        IORegistryEntrySetCFProperty(r, CFSTR("IORequestIdle"), sleep ? kCFBooleanTrue : kCFBooleanFalse);
        IOObjectRelease(r);
    }
}

- (IBAction)lockScreenMethodChanged:(id)sender
{
    if (([lockScreenMethodButton indexOfSelectedItem] == 1) || ([lockScreenMethodButton indexOfSelectedItem] == 3)) {
        
        NSString * askForPassword = runCommand(@"defaults read com.apple.screensaver askForPassword");
        NSString * askForPasswordelay= runCommand(@"defaults read com.apple.screensaver askForPasswordDelay");
        
        if (([askForPassword integerValue] != 1) || ([askForPasswordelay integerValue] != 0)) {
            NSRunAlertPanel(@"handyLock", @"Your OSX Security Security Preference is not set to ask for a password when the ScreenSaver is deactivated. handyLock will set it and present you the configuration panel for your validation. Simply close it if all is OK.", @"OK", nil, nil, nil);
            runCommand(@"defaults write com.apple.screensaver askForPassword 1");
            runCommand(@"defaults write com.apple.screensaver askForPasswordDelay 0");
            [self launchSecurityPreferences];
        }
    }
    
    if ([lockScreenMethodButton indexOfSelectedItem] == 2) {
        
        NSString * askForPassword = runCommand(@"defaults read com.apple.screensaver askForPassword");
        
        if ([askForPassword integerValue] == 1) {
            NSRunAlertPanel(@"handyLock", @"Your OSX Security Security Preference is set to ask for a password. This will prevent  the handyLock custom lock screen from working properly. handyLock will unset it and present you the resulting configuration panel for your validation. Simply close it if all is OK.", @"OK", nil, nil, nil);
            runCommand(@"defaults write com.apple.screensaver askForPassword 0");
            [self launchSecurityPreferences];
        }
    }
}

- (IBAction)setBackgroundAction:(NSButton *)sender {
 
        NSArray *fileTypes = [[NSArray alloc] initWithObjects:@"bmp", @"jpg", @"jp2", @"png", @"gif", @"jpeg", nil];
        self.panel = [NSOpenPanel openPanel];
        [self.panel setCanChooseDirectories:NO];
        [self.panel setCanCreateDirectories:NO];
        [self.panel setCanChooseFiles:YES];
        [self.panel setAllowedFileTypes:fileTypes];
        [self.panel setPrompt:@"Select image"];
        
        [self.panel setDirectoryURL:[NSURL fileURLWithPath:@"~/Documents"]];
        
        [self.panel beginSheetModalForWindow:[NSApp mainWindow] completionHandler:^(NSInteger result)
         {
             if (result == NSFileHandlingPanelOKButton)
             {
                 NSArray *urls = [self.panel URLs];
                 for (NSURL *url in urls)
                 {
                     // First, check if the URL is a file URL, as opposed to a web address, etc.
                     if (url.isFileURL)
                     {
                         // Check if it is an image
                             NSImage * image =  [[NSImage alloc] initWithContentsOfFile:url.path];
                             
                             if (image) {
                                 NSUserDefaults *defaults;
                                 
                                 defaults = [NSUserDefaults standardUserDefaults];
                                 
                                 [defaults setURL:url forKey:@"backgroundImage"];
                                 
                                 [defaults synchronize];
                             }
                             else
                             {
                                 NSRunAlertPanel(@"ALERT", @"%@ is NOT an image. Please select a valid image!", @"OK", nil, nil, url.path);
                             }
                         
                     }
                 }
             }
         }];
}

- (IBAction)btPollFrequencyUpdateAction:(id)sender
{
    NSRunAlertPanel( @"handyLock", @"Valid range is between 2 and 60 seconds. Setting value to 2 seconds", @"Close", nil, nil, nil );
    if ([btPollFrequency intValue] < 2 ) {
        NSRunAlertPanel( @"handyLock", @"Valid range is between 2 and 60 seconds. Setting value to 2 seconds", @"Close", nil, nil, nil );
        [btPollFrequency setIntValue:2];
    } else if ([btPollFrequency intValue] > 60) {
        NSRunAlertPanel( @"handyLock", @"Valid range is between 2 and 60 seconds. Setting value to 60 seconds", @"Close", nil, nil, nil );
        [btPollFrequency setIntValue:60];
    } else {
        [btPollFrequency setIntValue:[btPollFrequency intValue]];
    }
}

NSString *runCommand(NSString *commandToRun)
{
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/sh"];
    
    NSArray *arguments = [NSArray arrayWithObjects:
                          @"-c" ,
                          [NSString stringWithFormat:@"%@", commandToRun],
                          nil];
    NSLog(@"run command: %@",commandToRun);
    [task setArguments: arguments];
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle *file;
    file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *data;
    data = [file readDataToEndOfFile];
    
    NSString *output;
    output = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    return output;
}

- (void)launchAndQuitSecurityPreferences;
{
    // necessary for screen saver setting changes to take effect on file-vault-enabled systems when going from a askForPasswordDelay setting of zero to a non-zero setting
    NSAppleScript *kickSecurityPreferencesScript = [[NSAppleScript alloc] initWithSource:
                                                     @"tell application \"System Preferences\"\n"
                                                     @"     tell anchor \"General\" of pane \"com.apple.preference.security\" to reveal\n"
                                                     @"     activate\n"
                                                     @"end tell\n"
                                                     @"delay 0\n"
                                                     @"tell application \"System Preferences\" to quit"];
    [kickSecurityPreferencesScript executeAndReturnError:nil];
}

- (void)launchSecurityPreferences;
{
    // necessary for screen saver setting changes to take effect on file-vault-enabled systems when going from a askForPasswordDelay setting of zero to a non-zero setting
    NSAppleScript *kickSecurityPreferencesScript = [[NSAppleScript alloc] initWithSource:
                                                    @"tell application \"System Preferences\"\n"
                                                    @"     tell anchor \"General\" of pane \"com.apple.preference.security\" to reveal\n"
                                                    @"     activate\n"
                                                    @"end tell"];
    [kickSecurityPreferencesScript executeAndReturnError:nil];
}

- (void)appTerminated:(NSNotification *)note
{
    NSString *app = [NSString stringWithFormat:@"%@", [note userInfo][@"NSApplicationName"]];
    
    Dlog(@"Terminated app: %@", app);
    if ([app isEqualToString:@"handyLockHelper"])
    {
        NSNotificationCenter *center = [[NSWorkspace sharedWorkspace] notificationCenter];
        [center removeObserver:self name:NSWorkspaceDidTerminateApplicationNotification object:nil];
        
        gLockScreenOn = FALSE;
        priorStatus = InRange;
        
        // [self showWindow:self];
        
        [self disableLocking];
        
        NSRunAlertPanel( @"handyLock", @"A manual unlock request was placed. As a result handyLock has been disabled to prevent further automatic locking. Please remember to enable it again when ready.", @"OK", nil, nil, nil );
    }
}

- (IBAction)outOfRangeApplicationSelection:(id)sender
{
    NSArray *fileTypes = [[NSArray alloc] initWithObjects:@"app", @"APP", nil];// autorelease];
    self.panel = [NSOpenPanel openPanel];
    [self.panel setCanChooseDirectories:NO];
    [self.panel setCanCreateDirectories:NO];
    [self.panel setCanChooseFiles:YES];
    [self.panel setAllowedFileTypes:fileTypes];
    [self.panel setPrompt:@"Select out of range Application"];
    
    [self.panel setDirectoryURL:[NSURL fileURLWithPath:@"/Applications"]];
    
    [self.panel beginSheetModalForWindow:[NSApp mainWindow] completionHandler:^(NSInteger result)
     {
         if (result == NSFileHandlingPanelOKButton)
         {
             NSArray *urls = [self.panel URLs];
             for (NSURL *url in urls)
             {
                 // First, check if the URL is a file URL, as opposed to a web address, etc.
                 if (url.isFileURL)
                 {
                     BOOL isDir = NO;
                     // Verify that the file exists
                     // and is indeed a directory (isDirectory is an out parameter)
                     if ([[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir]
                         && isDir)
                     {
                         
                         NSString *app = [url.path lastPathComponent];
                         //NSString *theAppName = [app stringByDeletingPathExtension];
                         [outOfRangeAppField setStringValue:app];
                         [self userDefaultsSave];
                     }
                     else
                     {
                         NSRunAlertPanel(@"ALERT", @"%@ is NOT an app. Please select an app!", @"OK", nil, nil, url.path);
                     }
                 }
             }
         }
     }];
}

- (IBAction)inRangeApplicationSelection:(id)sender
{
    NSArray *fileTypes = [[NSArray alloc] initWithObjects:@"app", @"APP", nil];// autorelease];
    self.panel = [NSOpenPanel openPanel];
    [self.panel setCanChooseDirectories:NO];
    [self.panel setCanCreateDirectories:NO];
    [self.panel setCanChooseFiles:YES];
    [self.panel setAllowedFileTypes:fileTypes];
    [self.panel setPrompt:@"Select in of range Application"];
    
    [self.panel setDirectoryURL:[NSURL fileURLWithPath:@"/Applications"]];
    
    [self.panel beginSheetModalForWindow:[NSApp mainWindow] completionHandler:^(NSInteger result)
     {
         if (result == NSFileHandlingPanelOKButton)
         {
             NSArray *urls = [self.panel URLs];
             for (NSURL *url in urls)
             {
                 // First, check if the URL is a file URL, as opposed to a web address, etc.
                 if (url.isFileURL)
                 {
                     BOOL isDir = NO;
                     // Verify that the file exists
                     // and is indeed a directory (isDirectory is an out parameter)
                     if ([[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir]
                         && isDir)
                     {
                         
                         NSString *app = [url.path lastPathComponent];
                         //NSString *theAppName = [app stringByDeletingPathExtension];
                         [inRangeAppField setStringValue:app];
                         [self userDefaultsSave];
                     }
                     else
                     {
                         NSRunAlertPanel(@"ALERT", @"%@ is NOT an app. Please select an app!", @"OK", nil, nil, url.path);
                     }
                 }
             }
         }
     }];
}


- (IBAction)setPasswordButton:(NSButton *)sender {
    NSUserDefaults * defaults = [NSUserDefaults standardUserDefaults];
    
    if ([pinCode.stringValue isEqualTo:verifyPinCode.stringValue] && [pinCode.stringValue isNotEqualTo:@""]) {
        NSData * salt = [self getRandomBytes:256];
        NSString * hashedPassword = [self sha256:pinCode.stringValue salt:salt];
        [defaults setObject:hashedPassword forKey:@"securePassword"];
        [defaults setObject:salt forKey:@"salt"];
        [defaults synchronize];
        [pinCode setStringValue:@""];
        [verifyPinCode setStringValue:@""];
        //NSRunAlertPanel(@"SUCCESS", @"Password has been successfully set.", @"OK", nil, nil);
        [NSApp endSheet:passwordWindow];
        [passwordWindow orderOut:self];
        
    } else {
        if ([pinCode.stringValue isEqualTo:@""]) {
            NSRunAlertPanel(@"ALERT", @"Password can't be empty! Please enter a valid password", @"OK", nil, nil);
        } else {
            NSRunAlertPanel(@"ALERT", @"Passwords don't match! Please enter the same password twice", @"OK", nil, nil);
        }
    }
}

- (IBAction)cancelSettingPassword:(NSButton *)sender {
    [NSApp endSheet:passwordWindow];
    [passwordWindow orderOut:self];
}

- (IBAction)setLockSound:(NSButton *)sender {
    NSArray *fileTypes = [[NSArray alloc] initWithObjects:@"mp3", @"m4a", nil];
    self.panel = [NSOpenPanel openPanel];
    [self.panel setCanChooseDirectories:NO];
    [self.panel setCanCreateDirectories:NO];
    [self.panel setCanChooseFiles:YES];
    [self.panel setAllowedFileTypes:fileTypes];
    [self.panel setPrompt:@"Select lock sound"];
    
    [self.panel setDirectoryURL:[NSURL fileURLWithPath:@"~/Documents"]];
    
    [self.panel beginSheetModalForWindow:[NSApp mainWindow] completionHandler:^(NSInteger result)
     {
         if (result == NSFileHandlingPanelOKButton)
         {
             NSArray *urls = [self.panel URLs];
             for (NSURL *url in urls)
             {
                 // First, check if the URL is a file URL, as opposed to a web address, etc.
                 if (url.isFileURL)
                 {
                     // Check if it is an image
                     NSSound *doorSound = [[NSSound alloc] initWithContentsOfFile:url.path byReference:false];
                     
                     if (doorSound) {
                         NSUserDefaults *defaults;
                         
                         defaults = [NSUserDefaults standardUserDefaults];
                         
                         [defaults setURL:url forKey:@"lockSoundFile"];
                         
                         [defaults synchronize];
                     }
                     else
                     {
                         NSRunAlertPanel(@"ALERT", @"%@ is NOT a valid sound file. Please select a valid file!", @"OK", nil, nil, url.path);
                     }
                     
                 }
             }
         }
     }];
}

- (IBAction)setUnlockSound:(NSButton *)sender {
    NSArray *fileTypes = [[NSArray alloc] initWithObjects:@"mp3", @"m4a", nil];
    self.panel = [NSOpenPanel openPanel];
    [self.panel setCanChooseDirectories:NO];
    [self.panel setCanCreateDirectories:NO];
    [self.panel setCanChooseFiles:YES];
    [self.panel setAllowedFileTypes:fileTypes];
    [self.panel setPrompt:@"Select unlock sound"];
    
    [self.panel setDirectoryURL:[NSURL fileURLWithPath:@"~/Documents"]];
    
    [self.panel beginSheetModalForWindow:[NSApp mainWindow] completionHandler:^(NSInteger result)
     {
         if (result == NSFileHandlingPanelOKButton)
         {
             NSArray *urls = [self.panel URLs];
             for (NSURL *url in urls)
             {
                 // First, check if the URL is a file URL, as opposed to a web address, etc.
                 if (url.isFileURL)
                 {
                     // Check if it is an image
                     NSSound *doorSound = [[NSSound alloc] initWithContentsOfFile:url.path byReference:false];
                     
                     if (doorSound) {
                         NSUserDefaults *defaults;
                         
                         defaults = [NSUserDefaults standardUserDefaults];
                         
                         [defaults setURL:url forKey:@"unlockSoundFile"];
                         
                         [defaults synchronize];
                     }
                     else
                     {
                         NSRunAlertPanel(@"ALERT", @"%@ is NOT a valid sound file. Please select a valid file!", @"OK", nil, nil, url.path);
                     }
                     
                 }
             }
         }
     }];
}

- (IBAction)playLockSound:(NSButton *)sender {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSSound *doorSound = [NSSound soundNamed:@"Porte"];
    
    if ([prefs boolForKey:@"customLockScreenSounds"]) {
        NSURL *soundFile = [prefs URLForKey:@"lockSoundFile"];
        doorSound = [[NSSound alloc] initWithContentsOfFile:soundFile.path byReference:false];
    }
    
    //Play sound
    [doorSound play];
}


- (IBAction)playUnlockSound:(NSButton *)sender {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSSound *doorSound = [NSSound soundNamed:@"Porte"];
    
    if ([prefs boolForKey:@"customUnlockScreenSounds"]) {
        NSURL *soundFile = [prefs URLForKey:@"unlockSoundFile"];
        doorSound = [[NSSound alloc] initWithContentsOfFile:soundFile.path byReference:false];
    }
    
    //Play sound
    [doorSound play];
    
}

- (void)playLockingSoundSet {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs boolForKey:@"playLockingSound"])
    {
        NSSound *doorSound = [NSSound soundNamed:@"Porte"];
        
        if ([prefs boolForKey:@"customLockScreenSounds"]) {
            NSURL *soundFile = [prefs URLForKey:@"lockSoundFile"];
            doorSound = [[NSSound alloc] initWithContentsOfFile:soundFile.path byReference:false];
        }
        
        //Play sound
        [doorSound play];
    }
}

- (void)playUnlockingSoundSet {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if ([prefs boolForKey:@"playUnlockingSound"])
    {
        NSSound *doorSound = [NSSound soundNamed:@"Porte"];
        
        if ([prefs boolForKey:@"customUnlockScreenSounds"]) {
            NSURL *soundFile = [prefs URLForKey:@"unlockSoundFile"];
            doorSound = [[NSSound alloc] initWithContentsOfFile:soundFile.path byReference:false];
        }
        
        //Play sound
        [doorSound play];
    }
}

- (IBAction)openPasswordWindow:(NSButton *)sender {
    [passwordWindow makeFirstResponder:pinCode];
    [NSApp beginSheet:passwordWindow modalForWindow:[NSApp mainWindow] modalDelegate:self didEndSelector:nil contextInfo:nil];
}

-(NSData *)getRandomBytes:(NSUInteger)length {
    return [[NSFileHandle fileHandleForReadingAtPath:@"/dev/random"] readDataOfLength:length];
}

-(NSString *)sha256:(NSString *)parameters salt:(NSData *)saltData {
    NSData *paramData = [parameters dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *hash = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH ];
    CCHmac(kCCHmacAlgSHA256, saltData.bytes, saltData.length, paramData.bytes, paramData.length, hash.mutableBytes);
    NSString *base64Hash = [hash base64Encoding];
    return base64Hash;
}

@end
