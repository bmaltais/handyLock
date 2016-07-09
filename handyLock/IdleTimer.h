//
//  IdleTime.h
//  handyLock
//
//  Created by Bernard Maltais on 2013-01-13.
//
//

#include <IOKit/IOKitLib.h>

@interface IdleTime: NSObject
{
@protected
    
    mach_port_t   ioPort;
    io_iterator_t ioIterator;
    io_object_t   ioObject;
}

@property( readonly ) uint64_t timeIdle;
@property( readonly ) NSUInteger secondsIdle;

@end