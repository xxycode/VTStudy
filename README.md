# VTStudy
(实在受不了自己的英语了，改成中文文档吧)  
这是我音视频编解码学习的一个demo，会不定期更新。  
由于GitHub限制，ffmpeg的库上传不了，所以请 [点击这里](https://pan.baidu.com/s/1eTV59gm) (提取码:gi3q)下载ffmpeg
  库，当然你也可以自己编译。下载完之后按下图把ffmpeg库复制到工程。  
![img](http://out3mnggr.bkt.clouddn.com/QQ20180122-160052@2x.png?v=123)  
#### 更新日志
##### 2018-1-21
1. 新增librtm+videotoolbox来播放直播流，做了简单的消除累计延迟处理，就是粗暴的丢帧，硬解相对于软解，在cpu和内存上面都有所减少。  
##### 2018-1-17
1. 新增videotoolbox硬解码h264文件并且使用OpenGL ES来绘制画面，由于h264文件里面并没有携带pts信息所以视频是按dts显示的，会有卡顿的感觉，这里需要自己计算pts，目前还没做.
2. 新增ffmpeg播放视频画面，支持本地文件(mp4 h264 flv)，网络文件(mp4 flv rtmp)，用的是ffmpeg的软解。  

### 参考文章
[WWDC 2014 sample code](https://github.com/master-nevi/WWDC-2014/tree/master/Using%20video%20toolbox%20to%20decode%20compressed%20sample%20buffers)   
[iOS 系统中，H.264 视频流可以硬件解码吗？ 具体如何实现？](https://www.zhihu.com/question/20692215)   
[100行代码实现最简单的基于FFMPEG+SDL的视频播放器（SDL1.x）](http://blog.csdn.net/leixiaohua1020/article/details/8652605)  
[最简单的基于librtmp的示例：接收（RTMP保存为FLV）](http://blog.csdn.net/leixiaohua1020/article/details/42104893)  
[直播协议 HTTP-FLV 详解](http://akagi201.org/post/http-flv-explained/)  
[直播服务器简单实现 http_flv和hls 内网直播桌面](http://www.cnblogs.com/luconsole/p/6079534.html)  
