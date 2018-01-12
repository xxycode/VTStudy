//
//  ViewController.m
//  VTStuty
//
//  Created by XiaoXueYuan on 2018/1/11.
//  Copyright © 2018年 xxycode. All rights reserved.
//

#import "ViewController.h"
#import <VideoToolbox/VideoToolbox.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"Resource/curry" ofType:@"h264"];
    NSFileHandle *fileHandler = [NSFileHandle fileHandleForReadingAtPath:filePath];
    
}


@end
