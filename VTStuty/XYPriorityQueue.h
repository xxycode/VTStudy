//
//  XYPriorityQueue.h
//  VTStuty
//
//  Created by XiaoXueYuan on 22/01/2018.
//  Copyright © 2018 xxycode. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef BOOL (^CompareBlock)(id obj1, id obj2);     // CompareBlock 返回 true 升序，false 降序

@interface XYPriorityQueue : NSObject

@property (assign, nonatomic) NSInteger length;     // 元素个数

// 必须用这个函数初始化对象
- (instancetype)initWithCompareBlock:(CompareBlock)cmp NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)new NS_UNAVAILABLE;

// 为了性能，以下函数设计为线程不安全的，调用者需用 GCD 自行管理
- (void)push:(id)elem;                      // 入队
- (void)pop;                                // 出队
- (void)pushWithArray:(NSArray *)array;     // 所有数组元素入队
- (id)top;                                  // 返回队头元素，没有返回 nil
- (BOOL)isEmpty;                            // 判空
- (void)clear;                              // 清空队列
- (NSArray *)allObjects;                    // 返回队列中所有元素，顺序是队头到队尾

@end
