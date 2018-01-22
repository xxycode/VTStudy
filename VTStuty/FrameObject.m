//
//  FrameObject.m
//  VTStuty
//
//  Created by XiaoXueYuan on 22/01/2018.
//  Copyright © 2018 xxycode. All rights reserved.
//

#import "FrameObject.h"
#import <CoreVideo/CoreVideo.h>

@implementation FrameObject
- (void)dealloc{
    NSLog(@"frame dealloced");
//    CVImageBufferRef imgBuffer = (__bridge CVImageBufferRef)(self.imageBuffer);
//    CVPixelBufferRelease(imgBuffer);
}
@end
