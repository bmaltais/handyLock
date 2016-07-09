//
//  lockscreenValueTransformer.m
//  handyLock
//
//  Created by Bernard Maltais on 2015-01-18.
//  Copyright (c) 2015 Netputing Systems Inc. All rights reserved.
//

#import "lockscreenValueTransformer.h"

@implementation lockscreenValueTransformer
+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value {
    if (value == nil) return nil;
    
    if ([value integerValue] == 2) {
        return [NSNumber numberWithDouble: 1];
    } else {
        return [NSNumber numberWithDouble: 0];
    }
}

@end
