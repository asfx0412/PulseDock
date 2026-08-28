#import "TemperatureBridge.h"
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t depth);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

static double PDReadForMatcher(int page, int usage) {
    NSDictionary *matching = @{ @"PrimaryUsagePage": @(page), @"PrimaryUsage": @(usage) };
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) return 0;
    IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)matching);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) { CFRelease(client); return 0; }

    double hottest = 0;
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        CFTypeRef rawName = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        NSString *name = rawName ? (__bridge NSString *)rawName : nil;
        NSString *lower = name.lowercaseString;
        BOOL excluded = [lower containsString:@"battery"] || [lower containsString:@"nand"] ||
                        [lower containsString:@"tcal"] || [lower containsString:@"voltage"] ||
                        [lower containsString:@"current"] || [lower containsString:@"power"];
        // The matching usage page already limits this collection to thermal
        // services. Product keys change between SoC generations, so accept all
        // non-static die/package sensors instead of hard-coding M-series names.
        if (!excluded) {
            IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, 15, 0, 0);
            if (event != NULL) {
                double value = IOHIDEventGetFloatValue(event, 15 << 16);
                if (value >= 10 && value <= 115 && value > hottest) hottest = value;
                CFRelease(event);
            }
        }
        if (rawName) CFRelease(rawName);
    }
    CFRelease(services);
    CFRelease(client);
    return hottest;
}

double PDReadChipTemperature(void) {
    double legacy = PDReadForMatcher(0xff00, 0x0005);
    double modern = PDReadForMatcher(0xff08, 0x0003);
    return legacy > modern ? legacy : modern;
}
