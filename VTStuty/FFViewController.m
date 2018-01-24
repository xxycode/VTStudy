//
//  FFViewController.m
//  VTStuty
//
//  Created by XiaoXueYuan on 2018/1/15.
//  Copyright © 2018年 xxycode. All rights reserved.
//

#import "FFViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioUnit/AudioUnit.h>
#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libavutil/imgutils.h" 
#import "AAPLEAGLLayer.h"

@interface FFViewController (){
    //FFmpeg
    AVFormatContext *pFormatCtx;
    int             i, videoindex, audioindex;
    AVCodecContext  *pVideoCodecCtx,*pAudioCodecCtx;
    AVCodec         *pVideoCodec,*pAudioCodec;
    AVFrame *pFrame,*pFrameYUV;
    AVCodecParameters *codecParams;
    AVPacket *packet;
    NSTimeInterval fps;
    dispatch_queue_t decodeQueue;
    dispatch_queue_t displayQueue;
    AAPLEAGLLayer *playerLayer;
    NSMutableArray *videoBuffer;
    NSMutableArray *audioBuffer;
    NSLock *lock;
    BOOL isEnd;
}

@end

@implementation FFViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    decodeQueue = dispatch_queue_create("com.xxycode.h264decodequeue", NULL);
    displayQueue = dispatch_queue_create("com.xxycode.displayqueue", NULL);
    CGFloat width = [UIScreen mainScreen].bounds.size.width;
    CGFloat height = width * 9 / 16;
    playerLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, 64, width, height)];
    [self.view.layer addSublayer:playerLayer];
    videoBuffer = @[].mutableCopy;
    audioBuffer = @[].mutableCopy;
    lock = [[NSLock alloc] init];
    isEnd = NO;
    fps = 23;
}

- (void)play{
    NSTimeInterval t1 = [[NSDate date] timeIntervalSince1970];
    av_register_all();
    NSTimeInterval t2 = [[NSDate date] timeIntervalSince1970];
    printf("register用时:%lf\n",t2-t1);
    avformat_network_init();
    NSTimeInterval t3 = [[NSDate date] timeIntervalSince1970];
    printf("init net work用时:%lf\n",t3-t2);
    //return;
    //const char *filePath = [[[NSBundle mainBundle] pathForResource:@"Resource/curry" ofType:@"h264"] UTF8String];
    //本地文件
    //const char *filePath = "/Users/xiaoxueyuan/Desktop/p.mp4";
    //rtmp直播
    const char *filePath = "rtmp://live.hkstv.hk.lxdns.com/live/hks";
    //hls直播
    
    //const char *filePath = "http://live.hkstv.hk.lxdns.com/live/hks/playlist.m3u8";
    pFormatCtx = avformat_alloc_context();
    if (avformat_open_input(&pFormatCtx, filePath, NULL, NULL) != 0) {
        printf("Couldn't open input stream.\n");
        return;
    }
    NSTimeInterval t4 = [[NSDate date] timeIntervalSince1970];
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
        printf("Couldn't find stream information.\n");
        return;
    }
    NSTimeInterval t5 = [[NSDate date] timeIntervalSince1970];
    printf("获取媒体信息用时:%lf\n",t5-t4);
    videoindex = -1;
    audioindex = -1;
    for (i = 0; i < pFormatCtx -> nb_streams; ++i) {
        AVStream *stream = pFormatCtx -> streams[i];
        if (stream -> codecpar -> codec_type == AVMEDIA_TYPE_VIDEO) {
            fps = stream -> avg_frame_rate.num / stream -> avg_frame_rate.den;//每秒多少帧
            videoindex = i;
            pVideoCodec = avcodec_find_decoder(stream -> codecpar -> codec_id);
            pVideoCodecCtx = avcodec_alloc_context3(pVideoCodec);
            avcodec_parameters_to_context(pVideoCodecCtx, stream -> codecpar);
        }
        if (stream -> codecpar -> codec_type == AVMEDIA_TYPE_AUDIO) {
            audioindex = i;
            pAudioCodec = avcodec_find_decoder(stream -> codecpar -> codec_id);
            pAudioCodecCtx = avcodec_alloc_context3(pAudioCodec);
            avcodec_parameters_to_context(pAudioCodecCtx, stream -> codecpar);
        }
    }
    if (videoindex == -1) {
        printf("Didn't find a video stream.\n");
        return;
    }
    if (audioindex == -1) {
        printf("Didn't find a audio stream.\n");
        return;
    }
    if(avcodec_open2(pVideoCodecCtx, pVideoCodec,NULL) < 0){
        printf("Could not open audio codec.\n");
    }
    if (avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0) {
        printf("Could not open audio codec.\n");
    }
    pFrame = av_frame_alloc();
    packet = (AVPacket *)av_malloc(sizeof(AVPacket));
    [self renderVideo];
    while(!isEnd){
        if (videoBuffer.count < 30 && audioBuffer.count < 80) {
            av_read_frame(pFormatCtx, packet);
            if(packet -> stream_index == videoindex){
                avcodec_send_packet(pVideoCodecCtx, packet);
                avcodec_receive_frame(pVideoCodecCtx, pFrame);
                CVPixelBufferRef imageBuffer = converCVPixelBufferRefFromAVFrame(pFrame);
                [self didReceiveVideoBuffer:imageBuffer];
                av_packet_unref(packet);
                av_frame_unref(pFrame);
            }
            if (packet -> stream_index == audioindex) {
                NSLog(@"音频帧");
                avcodec_send_packet(pAudioCodecCtx, packet);
                avcodec_receive_frame(pAudioCodecCtx, pFrame);
                av_packet_unref(packet);
                av_frame_unref(pFrame);
            }
        }
        
    }
    isEnd = YES;
}

- (void)renderVideo{
    dispatch_async(displayQueue, ^{
        while (!isEnd) {
            static int  i = 0;
            [lock lock];
            if ([videoBuffer count] > 0) {
                
                CVPixelBufferRef imageBuffer = (__bridge CVPixelBufferRef)([videoBuffer firstObject]);
                [videoBuffer removeObjectAtIndex:0];
                [lock unlock];
                [playerLayer setPixelBuffer:imageBuffer];
                CVPixelBufferRelease(imageBuffer);
            }else{
                [lock unlock];
            }
            NSTimeInterval tPS = 1.0/1000;
            
            [NSThread sleepForTimeInterval:(1000 / fps) * tPS];
            NSLog(@"缓冲池数量%lu",(unsigned long)[videoBuffer count]);
            NSLog(@"播第%d帧~",i++);
        }
    });
    
}

- (void)initAutioSetting{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setPreferredIOBufferDuration:0.002 error:nil];
    [audioSession setPreferredSampleRate:44100.0 error:nil];
    [audioSession setActive:YES error:nil];
    AudioComponentDescription ioUnitDescription;
    ioUnitDescription.componentType = kAudioUnitType_Output;
    ioUnitDescription.componentSubType = kAudioUnitSubType_RemoteIO;
    ioUnitDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    ioUnitDescription.componentFlags = 0;
    ioUnitDescription.componentFlagsMask = 0;
    
    AUGraph processingGraph;
    NewAUGraph(&processingGraph);
    
    AUNode ioNode;
    AUGraphAddNode(processingGraph, &ioUnitDescription, &ioNode);
    
    AUGraphOpen(processingGraph);
    AudioUnit ioUnit;
    AUGraphNodeInfo(processingGraph, ioNode, NULL, &ioUnit);
    
    
}

 CVPixelBufferRef converCVPixelBufferRefFromAVFrame(AVFrame *avframe){
    if (!avframe || !avframe->data[0]) {
        return NULL;
    }
    
    CVPixelBufferRef outputPixelBuffer = NULL;
    
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             
                             @(avframe->linesize[0]), kCVPixelBufferBytesPerRowAlignmentKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferOpenGLESCompatibilityKey,
                             [NSDictionary dictionary], kCVPixelBufferIOSurfacePropertiesKey,
                             nil];
    
    
    if (avframe->linesize[1] != avframe->linesize[2]) {
        return  NULL;
    }
    
    size_t srcPlaneSize = avframe->linesize[1]*avframe->height/2;
    size_t dstPlaneSize = srcPlaneSize *2;
    uint8_t *dstPlane = malloc(dstPlaneSize);
    
    // interleave Cb and Cr plane
    for(size_t i = 0; i<srcPlaneSize; i++){
        dstPlane[2*i  ]=avframe->data[1][i];
        dstPlane[2*i+1]=avframe->data[2][i];
    }
    
    // printf("srcFrame  width____%d   height____%d \n",avframe->width,avframe->height);
    
    int ret = CVPixelBufferCreate(kCFAllocatorDefault,
                                  avframe->width,
                                  avframe->height,
                                  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                  (__bridge CFDictionaryRef)(options),
                                  &outputPixelBuffer);
    
    CVPixelBufferLockBaseAddress(outputPixelBuffer, 0);
    
    size_t bytePerRowY = CVPixelBufferGetBytesPerRowOfPlane(outputPixelBuffer, 0);
    size_t bytesPerRowUV = CVPixelBufferGetBytesPerRowOfPlane(outputPixelBuffer, 1);
    
    void* base =  CVPixelBufferGetBaseAddressOfPlane(outputPixelBuffer, 0);
    memcpy(base, avframe->data[0], bytePerRowY*avframe->height);
    
    base = CVPixelBufferGetBaseAddressOfPlane(outputPixelBuffer, 1);
    memcpy(base, dstPlane, bytesPerRowUV*avframe->height/2);
    
    CVPixelBufferUnlockBaseAddress(outputPixelBuffer, 0);
    
    free(dstPlane);
    
    if(ret != kCVReturnSuccess)
    {
        NSLog(@"CVPixelBufferCreate Failed");
        return NULL;
    }
    
    return outputPixelBuffer;
}

- (void)didReceiveVideoBuffer:(CVImageBufferRef)imageBuffer{
    if (imageBuffer == nil) {
        return;
    }
    [lock lock];
    [videoBuffer addObject:(__bridge id _Nonnull)(imageBuffer)];
    CVPixelBufferRef imgBuffer = NULL;
    if (videoBuffer.count > 30) {
        imgBuffer = (__bridge CVPixelBufferRef)videoBuffer[0];
        [videoBuffer removeObjectAtIndex:0];
    }
    [lock unlock];
    if (imgBuffer) {
        CVPixelBufferRelease(imgBuffer);
    }
}

- (void)didReceiveAudioBuffer:(id)audioBuffer{
    
}
- (IBAction)playAction:(id)sender {
    dispatch_async(decodeQueue, ^{
        [self play];
    });
}

@end
