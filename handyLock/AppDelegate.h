//
//  AppDelegate.h
//  handyLock
//
//  Created by Bernard Maltais on 9/7/2013.
//  Copyright (c) 2013 Netputing Systems Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <IOBluetooth/IOBluetooth.h>
#import <IOBluetoothUI/IOBluetoothUI.h>
#import <IOBluetoothUI/objc/IOBluetoothDeviceSelectorController.h>
#import "NumberField.h"
#import "IdleTimer.h"
#import "VDKQueue.h"
#import "PollFrequencyNumber.h"

typedef enum _BPStatus {
	InRange,
	OutOfRange
} BPStatus;

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    NSWindow *__lockWindow;
    NSWindow *__appWindow;
    __weak IBOutlet NSWindow *passwordWindow;
	IOBluetoothDevice *device;
	NSTimer *timer;
    // NSTimer *screenSaverTimer;
    NSTimer *pollMonitoringTimer;
	BPStatus priorStatus;
	NSStatusItem *statusItem;
    VDKQueue * __fileMonitor;
    NSSlider *_reactionSpeed;
    
    NSMenu *myMenu;
	
	NSImage *outOfRangeImage;
	NSImage *outOfRangeAltImage;
	NSImage *inRangeImage;
	NSImage *inRangeAltImage;
	
    IBOutlet id checkUpdatesOnStartup;
    IBOutlet id hideApplicationOnStartup;
    IBOutlet id deviceName;
    IBOutlet id lockingEnabled;
    IBOutlet id prefsWindow;
    IBOutlet id progressIndicator;
    IBOutlet id distanceRange;
    IBOutlet id startAtLoginCheckbox;
    IBOutlet NSTextField *signalStrength;
    IBOutlet NSLevelIndicator *signalStrenghtGage;
    IBOutlet NSLevelIndicator *aboutSignalStrenghtGage;
    IBOutlet NSSecureTextField *pinCode;
    IBOutlet NSSecureTextField *verifyPinCode;
    // IBOutlet NSSecureTextField *setPinCode;
    // IBOutlet NSImageView *backgroundImage;
    IBOutlet NSTextField *farReading;
    IBOutlet NSTextField *nearReading;
    IBOutlet NumberField *displaySleepTimer;
    //IBOutlet NSTextField *versionTextField;
    IBOutlet NSTextField *aboutVersionTextField;
    //
    __weak IBOutlet NSTextField *BTSignalStrenghtText;
    __weak IBOutlet NSTextField *BTSignalStrenghtValueText;
    __weak IBOutlet NSTextField *BTSignalStrenghtDBText;
    //
    __weak IBOutlet PollFrequencyNumber *btPollFrequency;
    __weak IBOutlet NSButton *logToFileCheckbox;
    __weak IBOutlet NSTextField *outOfRangeAppField;
    __weak IBOutlet NSTextField *inRangeAppField;
    __weak IBOutlet NSTextField *deviceDistance;
    
    IdleTime * idle;
}

@property (assign) IBOutlet NSWindow *window;
@property (strong) IBOutlet NSWindow *appWindow;
@property (strong) IBOutlet NSSlider *reactionSpeed;
@property (retain) VDKQueue * fileMonitor;
@property (weak) IBOutlet NumberField *delayBeforeLocking;
@property (weak) IBOutlet NSPopUpButton *lockScreenMethodButton;
//@property (weak) IBOutlet NSPopUpButtonCell *lockScreenBackgroundButton;
//@property (weak) IBOutlet NSButton *setBackgroundButton;
@property (weak) NSOpenPanel *panel;

// License methods
-(void) addAppAsLoginItem:(NSString *)appPath;

// AppController methods
- (void)createMenuBar;
- (void)userDefaultsLoad;
- (void)userDefaultsSave;
- (bool)BTPowerState;
- (BOOL)isInRange;
- (void)menuIconInRange;
- (void)menuIconOutOfRange;
- (void)runInRangeScript;
- (void)runOutOfRangeScript;
//- (int)getLockStateChangeTime;
- (void)startMonitoring;
- (void)stopMonitoring;
//- (void)enableScreenSaver;
//- (void)disableScreenSaver;
//- (void)startScreenSleepCountDown;
//- (void)stopScreenSleepCountDown;
- (BOOL)canILockTheScreen;
- (BOOL)canIActivate;
//- (void)startTrackingDisplaySleep;
- (NSString *)currentVersion;
- (void)setVersionStrings;
- (IBAction)lockScreenMethodChanged:(id)sender;
- (IBAction)setBackgroundAction:(NSButton *)sender;

// UI methods
- (IBAction)changeDevice:(id)sender;
- (IBAction)removeDevice:(id)sender;
- (IBAction)checkForUpdates:(id)sender;
- (IBAction)showWindow:(id)sender;
//- (IBAction)getNearReading:(id)sender;
- (IBAction)handleEnaDisableHandyLock:(id)sender;
//- (IBAction)setSensitivity:(id)sender;
- (IBAction)getHelp:(id)sender;
- (IBAction)startAtLoginTriggered:(id)sender;
- (IBAction)openWebSite:(id)sender;
- (IBAction)donate:(id)sender;
- (IBAction)saveReactionSpeed:(id)sender;
- (IBAction)outOfRangeApplicationSelection:(id)sender;
- (IBAction)inRangeApplicationSelection:(id)sender;
- (IBAction)clearOutOfRangeApp:(NSButton *)sender;
- (IBAction)clearInRangeApp:(NSButton *)sender;
- (IBAction)setPasswordButton:(NSButton *)sender;
- (IBAction)openPasswordWindow:(NSButton *)sender;
- (IBAction)cancelSettingPassword:(NSButton *)sender;
- (IBAction)setLockSound:(NSButton *)sender;
- (IBAction)setUnlockSound:(NSButton *)sender;
- (IBAction)playLockSound:(NSButton *)sender;
- (IBAction)playUnlockSound:(NSButton *)sender;
- (void) restartMonitoringFiles;

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;

- (void)connectDevice;
- (void)checkExpiration;
//- (void)sleepDisplay:(NSTimer *)theTimer;

@end

@interface ScreenSaverController:NSObject + controller;
@end

@protocol ScreenSaverControl
- (double)screenSaverTimeRemaining;
- (void)restartForUser:fp16;
- (void)screenSaverStopNow;
- (void)screenSaverStartNow;
- (void)setScreenSaverCanRun:(char)fp19;
- (char)screenSaverCanRun;
- (char)screenSaverIsRunning;
@end
