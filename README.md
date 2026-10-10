1.用Animations.jar替换原来的应用，把AnimationsCache.txt和Animations.jar放在一起。

2.convert_to_iconcache.py是AI编写的，用于32×8 的图片/GIF 转换为本地播放所需的AnimationsCache数据。
  
  使用方法：
  
  2.1 安装依赖：
      pip install Pillow

  2.2 准备素材：
      可以到 https://awtrix.blueforcer.de/animations/ 或者其他地方下载下载 32×8 的图片或 GIF。
      全部放入 32x8_animations 文件夹。
  2.3 运行脚本：
      python convert_to_iconcache.py
  2.4 获取输出：
      生成的 AnimationsCache.txt 就是所需的AnimationsCache文件。
      将它放到 AWTRIX 的 Apps 目录下替换原文件即可。
  2.5 补充说明
      关于 tick 参数：
          静态图片设 tick=2000 或更大，避免频繁切换。
          GIF 动画根据原帧率设置，例如 10 FPS 可设 tick=100。

3.代码使用B4J V8.10,JDK1.8.10 进行编译的。
      
