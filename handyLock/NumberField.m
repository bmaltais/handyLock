//
//  NumberField.m
//  handyLock
//
//  Created by Bernard Maltais on 2013-01-13.
//
//

#import "NumberField.h"

@implementation NumberField

-(void) textDidEndEditing:(NSNotification *)aNotification {
	// replace content with its intValue ( or process the input's value differently )
	[self setIntValue:[self intValue]];
    if ([self intValue] < 0) {
        [self setIntValue:0];
    }
    if ([self intValue] > 180) {
        [self setIntValue:180];
    }
	// make sure the notification is sent back to any delegate
	//[[self delegate] controlTextDidEndEditing:aNotification];
}
@end
