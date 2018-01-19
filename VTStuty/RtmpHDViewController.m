//
//  RtmpHDViewController.m
//  VTStuty
//
//  Created by XiaoXueYuan on 19/01/2018.
//  Copyright © 2018 xxycode. All rights reserved.
//

#import "RtmpHDViewController.h"
#import "rtmp.h"

#define MAX_BUFF_SIZE 1024 * 1024 * 30;

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
    dispatch_queue_t readerQueue;
    dispatch_queue_t decodeQueue;
    RTMP *rtmp;
    NSMutableData *buffData;
    NSLock *lock;
}

@end

@implementation RtmpHDViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    lock = [[NSLock alloc] init];
    liveUrl = "rtmp://live.hkstv.hk.lxdns.com/live/hks";
    readerQueue = dispatch_queue_create("com.xxycode.rtmp_queue", NULL);
    decodeQueue = dispatch_queue_create("com.xxycode.decode_queue", NULL);
}

- (void)startReader{
    dispatch_async(readerQueue, ^{
        [self readData];
    });
}

- (void)startDecode{
    dispatch_async(decodeQueue, ^{
        //[self decode];
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
            NSLog(@"收到一个音频包");
        }
        RTMPPacket_Free(packet);
        //NSLog(@"Receive: %5dByte, Total: %5.2fkB\n",nRead,countBufSize*1.0/1024);
    }
}

- (void)didReceiveVideoPacket:(RTMPPacket *)packet{
    NSLog(@"收到一个视频包，时间戳是：%d",packet -> m_nTimeStamp);
    
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
}

@end
