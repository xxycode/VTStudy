//
//  ViewController.m
//  VTStuty
//
//  Created by XiaoXueYuan on 2018/1/11.
//  Copyright © 2018年 xxycode. All rights reserved.
//

#import "ViewController.h"
#import <VideoToolbox/VideoToolbox.h>
#import "AAPLEAGLLayer.h"
#define LL long long

@interface ViewController (){
    dispatch_queue_t decodeQueue;
    dispatch_queue_t displayQueue;
    NSInputStream *inputStream;
    NSFileHandle *inpuFileHandler;
    NSString *filePath;
    uint8_t *mSPS;
    long mSPSSize;
    uint8_t *mPPS;
    long mPPSSize;
    VTDecompressionSessionRef mDecodeSession;
    CMFormatDescriptionRef  mFormatDescription;
    AAPLEAGLLayer *playerLayer;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    CGFloat width = [UIScreen mainScreen].bounds.size.width;
    CGFloat height = width * 9 / 16;
    playerLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, self.navigationController.navigationBar.frame.size.height, width, height)];
    [self.view.layer addSublayer:playerLayer];
    decodeQueue = dispatch_queue_create("com.xxycode.h264decodequeue", NULL);
    displayQueue = dispatch_queue_create("com.xxycode.displayqueue", NULL);
    filePath = [[NSBundle mainBundle] pathForResource:@"Resource/curry" ofType:@"h264"];
    inputStream = [[NSInputStream alloc] initWithFileAtPath:filePath];
    
    
}

- (IBAction)action:(id)sender{
    dispatch_async(decodeQueue, ^{
        [self decodeFile];
    });
}

- (void)decodeFile{
    if (inpuFileHandler == nil) {
        inpuFileHandler = [NSFileHandle fileHandleForReadingAtPath:filePath];
    }
        LL fileSize = [[[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil] objectForKey:NSFileSize] longLongValue];
        
       // while ([inputStream hasBytesAvailable]) {
        
        LL offset = 0;
    
    
        int count = 0;
        BOOL isEnd = NO;
        while (!isEnd) {
            int bCount = 0;
            int hCount = 0;
            LL frameSize = 0;
            LL beginOffset = offset;
            NSData *frameData = nil;
            while (1) {
                @autoreleasepool{
                    if (offset >= fileSize) {
                        isEnd = YES;
                        return;
                    }
                    [inpuFileHandler seekToFileOffset:offset];
                    NSData *data = [inpuFileHandler readDataOfLength:1];
                    uint8_t *inputBuffer = (uint8_t *)data.bytes;
                    uint8_t val = inputBuffer[0];
                    if (val == 0) {
                        bCount++;
                        frameSize++;
                    }else if (val == 1 && bCount == 3){
                        bCount = 0;
                        hCount++;
                        frameSize++;
                        if (hCount == 2 || offset == fileSize - 1) {
                            [inpuFileHandler seekToFileOffset:beginOffset];
                            frameData = [inpuFileHandler readDataOfLength:frameSize-4];
                            offset++;
                            break;
                        }
                    }else{
                        bCount = 0;
                        frameSize++;
                    }
                    offset++;
                }
            }
            //NSLog(@"%@",frameData);
            [self decodeData:frameData];
            offset -= 4;
            count++;
        }
        NSLog(@"总共有%d个nalu",count);
        

    
        
    
}

- (void)decodeData:(NSData *)data{
    uint8_t *packetBuffer = (uint8_t *)data.bytes;
    int nalType = packetBuffer[4] & 0x1F;
    switch (nalType) {
        case 0x05:
            //NSLog(@"Nal type is IDR frame");
            [self initVideoToolBox];
            [self decodeFrame:data];
            break;
        case 0x07:
            //NSLog(@"Nal type is SPS");
            mSPSSize = data.length - 4;
            mSPS = malloc(mSPSSize);
            memcpy(mSPS, packetBuffer + 4, mSPSSize);
            break;
        case 0x08:
            //NSLog(@"Nal type is PPS");
            mPPSSize = data.length - 4;
            mPPS = malloc(mPPSSize);
            memcpy(mPPS, packetBuffer + 4, mPPSSize);
            break;
        default:
            //NSLog(@"Nal type is B/P frame");
            [self decodeFrame:data];
            break;
    }
}

- (void)decodeFrame:(NSData *)data{
    uint8_t *pb = (uint8_t *)data.bytes;
    LL packetSize = data.length;
    uint8_t *packetBuffer = malloc(packetSize);
    memcpy(packetBuffer, pb, packetSize);
    
    uint32_t nalSize = (uint32_t)(packetSize - 4);
    uint8_t *pNalSize = (uint8_t*)(&nalSize);
    packetBuffer[0] = *(pNalSize + 3);
    packetBuffer[1] = *(pNalSize + 2);
    packetBuffer[2] = *(pNalSize + 1);
    packetBuffer[3] = *(pNalSize);
    
    if (mDecodeSession) {
        CMBlockBufferRef blockBuffer = NULL;
        OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                              (void *)packetBuffer, packetSize,
                                                              kCFAllocatorNull,
                                                              NULL, 0, packetSize,
                                                              0, &blockBuffer);
        if(status == kCMBlockBufferNoErr) {
            CMSampleBufferRef sampleBuffer = NULL;
            const size_t sampleSizeArray[] = {packetSize};
            status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                               blockBuffer,
                                               mFormatDescription,
                                               1, 0, NULL, 1, sampleSizeArray,
                                               &sampleBuffer);
            if (status == kCMBlockBufferNoErr && sampleBuffer) {
                VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
                VTDecodeInfoFlags flagOut = 0;
                VTDecompressionSessionDecodeFrame(mDecodeSession,
                                                  sampleBuffer,
                                                  flags,
                                                  NULL,
                                                  &flagOut);
                
                
                CFRelease(sampleBuffer);
            }
            CFRelease(blockBuffer);
        }
    }
}

- (void)initVideoToolBox {
    if (!mDecodeSession) {
        const uint8_t* parameterSetPointers[2] = {mSPS, mPPS};
        const size_t parameterSetSizes[2] = {mSPSSize, mPPSSize};
        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                              2, //param count
                                                                              parameterSetPointers,
                                                                              parameterSetSizes,
                                                                              4, //nal start code size
                                                                              &mFormatDescription);
        if(status == noErr) {
            CFDictionaryRef attrs = NULL;
            const void *keys[] = { kCVPixelBufferPixelFormatTypeKey };
            //      kCVPixelFormatType_420YpCbCr8Planar is YUV420
            //      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange is NV12
            uint32_t v = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
            const void *values[] = { CFNumberCreate(NULL, kCFNumberSInt32Type, &v) };
            attrs = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
            
            VTDecompressionOutputCallbackRecord callBackRecord;
            callBackRecord.decompressionOutputCallback = didDecompress;
            callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
            
            status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                  mFormatDescription,
                                                  NULL, attrs,
                                                  &callBackRecord,
                                                  &mDecodeSession);
            CFRelease(attrs);
        } else {
            NSLog(@"IOS8VT: reset decoder session failed status=%d", status);
        }
        
        
    }
}

UIImage* uiImageFromPixelBuffer(CVPixelBufferRef p) {
    CIImage* ciImage = [CIImage imageWithCVPixelBuffer:p];
    
    CIContext* context = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer : @(YES)}];
    
    CGRect rect = CGRectMake(0, 0, CVPixelBufferGetWidth(p), CVPixelBufferGetHeight(p));
    CGImageRef videoImage = [context createCGImage:ciImage fromRect:rect];
    
    UIImage* image = [UIImage imageWithCGImage:videoImage];
    CGImageRelease(videoImage);
    
    return image;
}

- (void)presentBuffer:(CVImageBufferRef)imageBuffer{
    dispatch_sync(displayQueue, ^{
        [playerLayer setPixelBuffer:imageBuffer];
        usleep(40 * 1000);
    });
    
}

void didDecompress( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    //static int i = 0;
        if (imageBuffer != NULL) {
//            if (i < 5) {
//                UIImage *img = uiImageFromPixelBuffer(imageBuffer);
//                UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
//                i++;
//            }
            
            __weak __block typeof(ViewController) *weakSelf = (__bridge ViewController *)decompressionOutputRefCon;
            
//            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(40 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
//                [weakSelf presentImage:uiImageFromPixelBuffer(imageBuffer)];
//            });
               [weakSelf presentBuffer:imageBuffer];
            NSNumber *framePTS = nil;
            if (CMTIME_IS_VALID(presentationTimeStamp)) {
                framePTS = [NSNumber numberWithDouble:CMTimeGetSeconds(presentationTimeStamp)];
            } else{
                //NSLog(@"Not a valid time for image buffer:");
            }
            
            if (framePTS) { //find the correct position for this frame in the output frames array
               
                NSLog(@"pts:%ld",(long)framePTS.integerValue);
            }
    } else {
        //NSLog(@"Error decompresssing frame at time: %.3f error: %d infoFlags: %u", (float)presentationTimeStamp.value/presentationTimeStamp.timescale, (int)status, (unsigned int)infoFlags);
    }
}

@end
