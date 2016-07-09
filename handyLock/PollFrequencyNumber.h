//
//  PollFrequencyNumber.h
//  handyLock
//
//  Created by Bernard Maltais on 2014-10-02.
//  Copyright (c) 2014 Netputing Systems Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PollFrequencyNumber : NSTextField { }

-(void) textDidEndEditing:(NSNotification *)aNotification;

@end