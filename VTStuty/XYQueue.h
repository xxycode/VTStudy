//
//  XYQueue.h
//  VTStuty
//
//  Created by XiaoXueYuan on 22/01/2018.
//  Copyright © 2018 xxycode. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface XYQueue : NSObject

@property (assign, nonatomic) NSInteger length;   // 元素个数

// 为了性能，以下函数设计为线程不安全的，调用者需用 GCD 自行管理
- (void)push:(id)elem;      // 入队
- (void)pop;                // 出队
- (id)front;                // 返回队头元素，没有返回 nil
- (id)rear;                 // 返回队尾元素
- (BOOL)isEmpty;            // 判空
- (NSArray *)allObjects;    // 返回队列中所有元素，顺序是队头到队尾
- (void)clear;              // 清空队列

@end
