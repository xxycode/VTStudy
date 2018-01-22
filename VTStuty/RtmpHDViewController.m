//
//  RtmpHDViewController.m
//  VTStuty
//
//  Created by XiaoXueYuan on 19/01/2018.
//  Copyright © 2018 xxycode. All rights reserved.
//

#import "RtmpHDViewController.h"
#import "rtmp.h"
#import <VideoToolbox/VideoToolbox.h>
#import "AAPLEAGLLayer.h"
#import "FrameObject.h"
#import "XYPriorityQueue.h"

typedef struct flvHeader{
    unsigned char type[4]; // UI8 * 3  "FLV"
    unsigned char versions; // UI8   版本号
    unsigned char stream_info;//UI8  流信息
    unsigned int length; // UI32  文件长度
}FLVHeader;

typedef struct flvtagHeader {
    unsigned char type;  // UI8   tag类型 音频(0x08) 视频(0x09) script data(0x12)
    unsigned int data_size; // UI24 数据区长度
    unsigned int timestemp; // UI24 时间戳
    unsigned char time_stamp_extended; //UI8 扩展时间戳
    unsigned int stream_id; //UI24 流id
}FLVTagHeader;

typedef struct flvtag {
    FLVTagHeader *header;
    unsigned char *data;
}FLVTag;

@interface RtmpHDViewController (){
//    char *buf;
//    int buffSize;
    int currentBuffSize;
    char *liveUrl;
    BOOL isPlaying;
    uint8_t *mSPS;
    long mSPSSize;
    uint8_t *mPPS;
    long mPPSSize;
    dispatch_queue_t readerQueue;
    dispatch_queue_t decodeQueue;
    dispatch_queue_t displayQueue;
    RTMP *rtmp;
    NSMutableData *buffData;
    NSLock *lock;
    VTDecompressionSessionRef mDecodeSession;
    CMFormatDescriptionRef  mFormatDescription;
    AAPLEAGLLayer *playerLayer;
    //优先队列 根据pts排序
    XYPriorityQueue *frames;
    NSMutableArray *sortedFrames;
}

@end

@implementation RtmpHDViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    CGFloat width = [UIScreen mainScreen].bounds.size.width;
    CGFloat height = width * 9 / 16;
    playerLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, self.navigationController.navigationBar.frame.size.height, width, height)];
    [self.view.layer addSublayer:playerLayer];
    lock = [[NSLock alloc] init];
    liveUrl = "rtmp://live.hkstv.hk.lxdns.com/live/hks";
    readerQueue = dispatch_queue_create("com.xxycode.rtmp_queue", NULL);
    decodeQueue = dispatch_queue_create("com.xxycode.decode_queue", NULL);
    displayQueue = dispatch_queue_create("com.xxycode.display_queue", NULL);
    frames = [[XYPriorityQueue alloc] initWithCompareBlock:^BOOL(id obj1, id obj2) {
        FrameObject *f1 = obj1;
        FrameObject *f2 = obj2;
        return f1.pts > f2.pts;
    }];
}

- (void)startReader{
    dispatch_async(readerQueue, ^{
        [self readData];
    });
}

- (void)startDecode{
    dispatch_async(decodeQueue, ^{
        while (isPlaying) {
            
            [lock lock];
            if (frames.length > 20) {
                FrameObject *f = [frames top];
                [frames pop];
                [lock unlock];
                CVImageBufferRef imgBuffer = (__bridge CVImageBufferRef)(f.imageBuffer);
                [playerLayer setPixelBuffer:imgBuffer];
                
                NSLog(@"buffsize:%d,pts:%d",frames.length,f.pts);
            }else{
                [lock unlock];
            }
            
            usleep(40 * 1000);
        }
        
    });
}

- (void)readData{
    rtmp = RTMP_Alloc();
    RTMP_Init(rtmp);
    rtmp -> Link.timeout = 10;
    if (!RTMP_SetupURL(rtmp, liveUrl)) {
        RTMP_Free(rtmp);
        NSLog(@"设置URL失败");
        return;
    }
    rtmp -> Link.lFlags |= RTMP_LF_LIVE;
    RTMP_SetBufferMS(rtmp, 60 * 1000);//1 mins
    if (!RTMP_Connect(rtmp, NULL)) {
        RTMP_Free(rtmp);
        NSLog(@"连接服务器失败");
        return;
    }
    if (!RTMP_ConnectStream(rtmp, 0)) {
        RTMP_Free(rtmp);
        NSLog(@"连接视频流失败");
        return;
    }
    int nRead;
    RTMPPacket pkg = {0};
    RTMPPacket *packet = &pkg;
    int timeout = 5 , cnt = 0;
    while (isPlaying) {
        nRead = RTMP_GetNextMediaPacket(rtmp, packet);
        if (nRead < 0) {
            if(cnt < timeout) {
                cnt++ ;
                usleep(50 * 1000); // 50ms
                continue ;
            }
        }
        cnt = 0;
        if (0x09 == packet -> m_packetType) {
            [self didReceiveVideoPacket:packet];
        }else if(0x08 == packet -> m_packetType){
            //NSLog(@"收到一个音频包");
        }else if(0x12 == packet -> m_packetType){
            [self didReceiveScriptPacket:packet];
        }
        RTMPPacket_Free(packet);
        //NSLog(@"Receive: %5dByte, Total: %5.2fkB\n",nRead,countBufSize*1.0/1024);
    }
}

- (void)didReceiveVideoPacket:(RTMPPacket *)packet{
    char *data = packet -> m_body;
    int header = getIntFromBuffer(data, 1);
    //int videoType = (header >> 4) & 0x0F;
    int videoCodec = (header & 0x0F);
    //printf("收到一个视频包，时间戳是：%d,帧类型是：%d,编码类型是：%d", packet -> m_nTimeStamp, videoType, videoCodec);
    if (videoCodec == 0x07) {
        //printf("这是一个h264编码的包，");
    
        int type = getIntFromBuffer(data +1, 1);
        if (type == 0) {
            printf("是一个有sps和pps的包\n");
            /* 1(video头) + 4(因为是avc所以多出4个字节，都是0x0) + 6(AVCDecoderConfigurationRecord前面的信息)
             * 详见 http://akagi201.org/post/http-flv-explained/
             */
            data += 1 + 4 + 6;
            mSPSSize = getIntFromBuffer(data, 2);
            mSPS = malloc(mSPSSize);
            //这里加2是因为SPS或者PPS的长度占2个字节
            data += 2;
            memcpy(mSPS, data, mSPSSize);
            //这里加1是因为有一个字节是表示sps或者pps的数量，而这个数量一般是1个
            data += mSPSSize + 1;
            mPPSSize = getIntFromBuffer(data, 2);
            mPPS = malloc(mPPSSize);
            data += 2;
            memcpy(mPPS, data, mPPSSize);
            [self initVideoToolBox];
        }else if (type == 1){
            //printf("是一个普通的nalu包\n");
            /*
             * 1(type 1关键帧 0普通帧)+1(固定0x01)+3(compositionTime是dts和pts之间的偏移)
             * 详见 http://blog.csdn.net/linux_vae/article/details/78421892
             */
            uint32_t data_size = packet -> m_nBodySize - (1 + 1 + 3);
            char *frame_data = data + (1 + 1 + 3);
            int cts = getIntFromBuffer(data + 1 + 1, 3);
            //printf("cts是：%d\n",cts);
            [self decodeVideoFrame:frame_data size:data_size dts:packet -> m_nTimeStamp pts:packet -> m_nTimeStamp + cts];
            //usleep(40 * 1000);
        }
        
    }
}

- (void)decodeVideoFrame:(char *)data size:(uint32_t)size dts:(uint32_t)dts pts:(uint32_t)pts{
    CVPixelBufferRef outputPixelBuffer = NULL;
    if (mDecodeSession) {
        CMBlockBufferRef blockBuffer = NULL;
        OSStatus status  = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                              (void*)data, size,
                                                              kCFAllocatorNull,
                                                              NULL, 0, size,
                                                              0, &blockBuffer);
        CMSampleTimingInfo timingInfo = {40, pts, dts};
//        CMSampleTimingInfo timingInfo;
//        timingInfo.decodeTimeStamp = CMTimeMake(1, 30000);
//        timingInfo.presentationTimeStamp = CMTimeMake(1, 30000);
//        timingInfo.duration = CMTimeMake(1, 30000);
        if(status == kCMBlockBufferNoErr) {
            CMSampleBufferRef sampleBuffer = NULL;
            const size_t sampleSizeArray[] = {size};
//            status = CMSampleBufferCreateReady(kCFAllocatorDefault,
//                                               blockBuffer,
//                                               mFormatDescription,
//                                               1, 0, NULL, 1, sampleSizeArray,
//                                               &sampleBuffer);
            status = CMSampleBufferCreate(kCFAllocatorDefault, blockBuffer, YES, NULL, NULL, mFormatDescription, 1, 1, &timingInfo, 1, sampleSizeArray, &sampleBuffer);
            if (status == kCMBlockBufferNoErr && sampleBuffer) {
                VTDecodeFrameFlags flags = 0;
                VTDecodeInfoFlags flagOut = 0;
                // 默认是同步操作。
                // 调用didDecompress，返回后再回调
                OSStatus decodeStatus = VTDecompressionSessionDecodeFrame(mDecodeSession,
                                                                          sampleBuffer,
                                                                          flags,
                                                                          &outputPixelBuffer,
                                                                          &flagOut);
                FrameObject *f = [FrameObject new];
                f.pts = pts;
                f.imageBuffer = (__bridge id)(outputPixelBuffer);
                [lock lock];
                [frames push:f];
                [lock unlock];
                if(decodeStatus == kVTInvalidSessionErr) {
                    NSLog(@"IOS8VT: Invalid session, reset decoder session");
                } else if(decodeStatus == kVTVideoDecoderBadDataErr) {
                    NSLog(@"IOS8VT: decode failed status=%d(Bad data)", decodeStatus);
                } else if(decodeStatus != noErr) {
                    NSLog(@"IOS8VT: decode failed status=%d", decodeStatus);
                }
                
                CFRelease(sampleBuffer);
            }
            CFRelease(blockBuffer);
        }
    }
    //[self presentBuffer:outputPixelBuffer];
    //[playerLayer setPixelBuffer:outputPixelBuffer];
    CFRelease(outputPixelBuffer);
    //NSLog(@"pts:%d",timeStamp);
    //usleep(40 * 1000);
}

- (void)didReceiveScriptPacket:(RTMPPacket *)packet{
    printf("收到一个ScriptPacket ");
    char *data = packet -> m_body;
    int amf_type = getIntFromBuffer(data, 1);
    int amf_size = getIntFromBuffer(data + 1, 2);
    char *amf_data = malloc(amf_size);
    memcpy(amf_data, data + 3, amf_size);
    printf("第一个amf类型是:%x,大小是:%d,内容:%s,",amf_type,amf_size,amf_data);
    amf_type = getIntFromBuffer(data + 3 + amf_size, 1);
    int arr_size = getIntFromBuffer(data + 3 + amf_size + 1, 3);
    printf("第二个amf类型是:%x,有%d个元素（貌似直播都是0个？）\n",amf_type,arr_size);
    free(amf_data);
}

unsigned int getIntFromBuffer(char *buffer, int len)
{
    unsigned int value = 0;
    for (int i = 0; i < len; i++)
    {
        value |= (buffer[i] & 0x000000FF) << ((len - i -1) * 8);
    }
    return value;
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
            callBackRecord.decompressionOutputCallback = didDecompressFrame;
            callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
            
            status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                  mFormatDescription,
                                                  NULL, attrs,
                                                  &callBackRecord,
                                                  &mDecodeSession);
            CFRelease(attrs);
            NSLog(@"create decompressionSession success~");
        } else {
            NSLog(@"IOS8VT: reset decoder session failed status=%d", status);
        }
        
        
    }
}

void didDecompressFrame( void *decompressionOutputRefCon, void *sourceFrameRefCon, OSStatus status, VTDecodeInfoFlags infoFlags, CVImageBufferRef imageBuffer, CMTime presentationTimeStamp, CMTime presentationDuration ){
    if (imageBuffer != NULL) {
//        typeof(RtmpHDViewController) *self = (__bridge RtmpHDViewController *)decompressionOutputRefCon;
//        [self presentBuffer:imageBuffer];
        CVPixelBufferRef *outputPixelBuffer = (CVPixelBufferRef *)sourceFrameRefCon;
        *outputPixelBuffer = CVPixelBufferRetain(imageBuffer);
        //NSLog(@"pts:%f",CMTimeGetSeconds(presentationTimeStamp));
    } else {
        NSLog(@"Error decompresssing frame at time: %.3f error: %d infoFlags: %u", (float)presentationTimeStamp.value/presentationTimeStamp.timescale, (int)status, (unsigned int)infoFlags);
    }
}

- (void)presentBuffer:(CVImageBufferRef)imageBuffer{
    dispatch_sync(displayQueue, ^{
        [playerLayer setPixelBuffer:imageBuffer];
        //usleep(40 * 1000);
    });
    
}

//- (void)receivedData:(void *)bytes length:(int)length{
//    [lock lock];
//    memmove(buf + currentBuffSize, bytes, length);
//    currentBuffSize += length;
//    [lock unlock];
//}

//- (void)decode{
//    if (!isPlaying) {
//        return;
//    }
//    NSLog(@"开始解码");
//    BOOL hasHeader = NO;
//    int currentOffset = 0;
//    //currentBuffSize = 10;
//    while (isPlaying) {
//        if (currentOffset < currentBuffSize) {
//            if (!hasHeader && currentBuffSize >= 9) {
//                FLVHeader *flvHeader = malloc(sizeof(FLVHeader));
//                [lock lock];
//                memmove(flvHeader -> type, buf, 3);
//                memmove(&(flvHeader -> versions), buf + 3, 1);
//                memmove(&(flvHeader -> stream_info), buf + 3 + 1, 1);
//                memmove(&(flvHeader -> length), buf + 3 + 1 + 1, 4);
//                [lock unlock];
//                flvHeader -> length = reverse_32(flvHeader -> length);
//                currentOffset += 9;
//                if (flvHeader -> stream_info & 0x04) {
//                    NSLog(@"有音频");
//                }
//                if (flvHeader -> stream_info & 0x01) {
//                    NSLog(@"有视频");
//                }
//                printf("=========== file header=============\n");
//                printf("type : %s\n", flvHeader -> type);
//                printf("versions : %u\n", flvHeader -> versions);
//                printf("stream_info : %u\n", flvHeader -> stream_info);
//                printf("length : %d\n", flvHeader -> length);
//                printf("====================================\n");
//                hasHeader = YES;
//                continue;
//            }
//            if (hasHeader) {
//                FLVTag *tag = malloc(sizeof(tag));
//                tag -> header = NULL;
//                tag -> data = NULL;
//                int lastTagSize = 0;
//                [lock lock];
//                memmove(&lastTagSize, buf + currentOffset, 4);
//                currentOffset += 4;
//                [lock unlock];
//                lastTagSize = reverse_32(lastTagSize);
//                if (lastTagSize < 0) {
//                    NSLog(@"lastTagSize小于0");
//                    continue;
//                }
//                tag -> header = malloc(sizeof(FLVTagHeader));
//                [lock lock];
//                memmove(&(tag -> header -> type), buf + currentOffset, 1);
//                memmove(&(tag -> header -> data_size), buf + currentOffset + 1, 3);
//                memmove(&(tag -> header -> timestemp), buf + currentOffset + 1 + 3, 3);
//                memmove(&(tag -> header -> time_stamp_extended), buf + currentOffset + 1 + 3 + 3, 1);
//                memmove(&(tag -> header -> stream_id), buf + currentOffset + 1 + 3 + 3 + 1, 3);
//                [lock unlock];
//                currentOffset += 11;
//                int dataSize = tag -> header -> data_size = reverse_24(tag -> header -> data_size);
//                tag -> header -> timestemp = reverse_24(tag -> header -> timestemp);
//                tag -> header -> stream_id = reverse_24(tag -> header -> stream_id);
//                printf("\nlast_data_size:%d\n",lastTagSize);
//                printf("======= tag header =======\n");
//                printf("tag_type:%x\n", tag -> header -> type);
//                printf("data_size:%d\n", tag -> header -> data_size);
//                printf("timestemp:%x\n", tag -> header -> timestemp);
//                printf("time_stamp_extended:%x\n", tag -> header-> time_stamp_extended);
//                printf("stream_id:%x\n", tag -> header -> stream_id);
//                printf("currentoffset:%d\n", currentOffset);
//                tag -> data = malloc(dataSize + 1);
//                [lock lock];
//                memmove(tag -> data, buf + currentOffset, dataSize);
//                [lock unlock];
//                currentOffset += dataSize;
//                if (currentOffset > currentBuffSize) {
//                    currentOffset -= (dataSize + 11 + 4);
//                }
//                free(tag -> header);
//                free(tag -> data);
//                free(tag);
//                usleep(40 * 1000);
//            }
//        }
//    }
//}

//int reverse_32(unsigned int a){
//    union {
//        int i;
//        char c[4];
//    } u, r;
//
//    u.i = a;
//    r.c[0] = u.c[3];
//    r.c[1] = u.c[2];
//    r.c[2] = u.c[1];
//    r.c[3] = u.c[0];
//
//    return r.i;
//}
//
//int reverse_24(unsigned int a){
//    union {
//        int i;
//        char c[4];
//    } u, r;
//
//    u.i = a;
//    r.c[0] = u.c[2];
//    r.c[1] = u.c[1];
//    r.c[2] = u.c[0];
//    r.c[3] = 0;
//
//    return r.i;
//}

- (void)doPlay{
    if (isPlaying) {
        return;
    }
    isPlaying = YES;
    [self startReader];
    [self startDecode];
}

- (IBAction)playAction:(id)sender{
    [self doPlay];
}
- (IBAction)stop:(id)sender {
    isPlaying = NO;
    RTMP_Free(rtmp);
}

@end
