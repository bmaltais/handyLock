//
//  DebugOutput.h
//  AirPrintDaemon
//
//  Created by Bernard Maltais on 11-04-17.
//  Copyright 2011 netputing.com. All rights reserved.
//

/************************************************************************
 * DebugOutput.h
 *
 * Definitions for DebugOutput class
 ************************************************************************/

// Enable debug (NSLog) wrapper code? Comment out next line to disable debug logging
// #define DEBUG 1

// Comment out to make version premament (does not expire at fix date)
// #define EXPIRATION 1

// Comment out to make version production (hide testing features)
// #define TESTING 1

// Uncomment to simulate expired trial
// #define SIMULATETRIALEXPIRED 1

// DLog is almost a drop-in replacement for NSLog
// DLog();
// DLog(@"here");
// DLog(@"value: %d", x);
// Unfortunately this doesn't work DLog(aStringVariable); you have to do this instead DLog(@"%@", aStringVariable);
#ifdef DEBUG
#       define Dlog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#       define Dlog(...)
#endif

#ifdef SIMULATETRIALEXPIRED
#       define kSIMTRIALEXPIRED TRUE
#else
#       define kSIMTRIALEXPIRED FALSE
#endif

#ifdef EXPIRATION
#       define kTESTVERSION TRUE
#else
#       define kTESTVERSION FALSE
#endif

#ifdef TESTING
#       define kTESTING TRUE
#else
#       define kTESTING FALSE
#endif

#define kEXPIRATIONDATE @"2026-06-01 00:00:00 +0500"
#define kHIDECOMPUTERNAMEENABLED @"hideComputerNameEnabled"
#define kRUNASSYSTEMENABLED @"runAsSystemEnabled"
#define kRESTARTBROWSERENABLED @"restartBrowserEnabled"
#define kMDNSLICENSE @"license"

// ALog always displays output regardless of the DEBUG setting
#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);