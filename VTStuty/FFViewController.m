//
//  FFViewController.m
//  VTStuty
//
//  Created by XiaoXueYuan on 2018/1/15.
//  Copyright © 2018年 xxycode. All rights reserved.
//

#import "FFViewController.h"

#include "libavcodec/avcodec.h"
#include "libavformat/avformat.h"
#include "libswscale/swscale.h"
#include "libavutil/imgutils.h" 
#import "AAPLEAGLLayer.h"

@interface FFViewController (){
    //FFmpeg
    AVFormatContext *pFormatCtx;
    int             i, videoindex;
    AVCodecContext  *pCodecCtx;
    AVCodec         *pCodec;
    AVFrame *pFrame,*pFrameYUV;
    AVCodecParameters *codecParams;
    AVPacket *packet;
    dispatch_queue_t decodeQueue;
    dispatch_queue_t displayQueue;
    AAPLEAGLLayer *playerLayer;
}

@end

@implementation FFViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    decodeQueue = dispatch_queue_create("com.xxycode.h264decodequeue", NULL);
    displayQueue = dispatch_queue_create("com.xxycode.displayqueue", NULL);
    CGFloat width = [UIScreen mainScreen].bounds.size.width;
    CGFloat height = width * 9 / 16;
    playerLayer = [[AAPLEAGLLayer alloc] initWithFrame:CGRectMake(0, self.navigationController.navigationBar.frame.size.height, width, height)];
    [self.view.layer addSublayer:playerLayer];
    
    
}

- (void)play{
    av_register_all();
    //const char *filePath = [[[NSBundle mainBundle] pathForResource:@"Resource/curry" ofType:@"h264"] UTF8String];
    //本地文件
    //const char *filePath = "/Users/xiaoxueyuan/Desktop/p.mp4";
    //rtmp直播
    //const char *filePath = "rtmp://live.hkstv.hk.lxdns.com/live/hks";
    //mp4文件
    const char *filePath = "https://f.us.sinaimg.cn/003WdJnIlx07hoToANwc01040203KRYH0k03.mp4?label=mp4_720p&template=26&Expires=1516024014&ssig=YWbnwJl8P8&KID=unistore,video";
    pFormatCtx = avformat_alloc_context();
    if (avformat_open_input(&pFormatCtx, filePath, NULL, NULL) != 0) {
        printf("Couldn't open input stream.\n");
        return;
    }
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
        printf("Couldn't find stream information.\n");
        return;
    }
    videoindex = -1;
    for (i = 0; i < pFormatCtx -> nb_streams; ++i) {
        AVStream *stream = pFormatCtx -> streams[i];
        if (stream -> codecpar -> codec_type == AVMEDIA_TYPE_VIDEO) {
            videoindex = i;
            pCodec = avcodec_find_decoder(stream->codecpar -> codec_id);
            pCodecCtx = avcodec_alloc_context3(pCodec);
            avcodec_parameters_to_context(pCodecCtx, stream -> codecpar);

            break;
        }
    }
    if (videoindex == -1) {
        printf("Didn't find a video stream.\n");
        return;
    }
    if(avcodec_open2(pCodecCtx, pCodec,NULL) < 0){
        printf("Could not open codec.\n");
    }
    pFrame = av_frame_alloc();
    
    packet = (AVPacket *)av_malloc(sizeof(AVPacket));
    while(av_read_frame(pFormatCtx, packet) >= 0){
        //int ret, got_picture;
        if(packet -> stream_index == videoindex){
        
//            ret = avcodec_decode_video2(pCodecCtx, pFrame, &got_picture, packet);
//            if(ret < 0){
//                printf("Decode Error.\n");
//                //return -1;
//            }
            avcodec_send_packet(pCodecCtx, packet);
            
            avcodec_receive_frame(pCodecCtx, pFrame);
            CVPixelBufferRef imageBuffer = converCVPixelBufferRefFromAVFrame(pFrame);
            [self presentBuffer:imageBuffer];
            CVBufferRelease(imageBuffer);
            av_packet_unref(packet);
        }
    }
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

- (void)presentBuffer:(CVImageBufferRef)imageBuffer{
    dispatch_sync(displayQueue, ^{
        [playerLayer setPixelBuffer:imageBuffer];
        usleep(40 * 1000);
    });
    
}
- (IBAction)playAction:(id)sender {
    dispatch_async(decodeQueue, ^{
        [self play];
    });
}

@end
