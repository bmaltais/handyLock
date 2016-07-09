//
//  PollFrequencyNumber.m
//  handyLock
//
//  Created by Bernard Maltais on 2014-10-02.
//  Copyright (c) 2014 Netputing Systems Inc. All rights reserved.
//

#import "PollFrequencyNumber.h"

@implementation PollFrequencyNumber

-(void) textDidEndEditing:(NSNotification *)aNotification {
    // replace content with its intValue ( or process the input's value differently )
    [self setIntValue:[self intValue]];
    if ([self intValue] < 2) {
        [self setIntValue:2];
    }
    if ([self intValue] > 60) {
        [self setIntValue:60];
    }
    
    // make sure the notification is sent back to any delegate
    //[[self delegate] controlTextDidEndEditing:aNotification];
}
@end
