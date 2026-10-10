import json
from PIL import Image
import os

def rgb_to_16bit(r, g, b):
    """将 RGB 转换为 16 位色值"""
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)

def image_to_frame(img, width=32, height=8):
    """将 PIL Image 转换为像素值列表（长度 = width * height）"""
    img = img.convert('RGB').resize((width, height))
    pixels = list(img.getdata())
    return [rgb_to_16bit(r, g, b) for r, g, b in pixels]

def convert_to_iconcache(input_path, output_path, animation_id, tick=100):
    """将图片/GIF 转换为 iconcache 格式"""
    frames = []
    
    if input_path.lower().endswith('.gif'):
        # 处理 GIF 动画
        img = Image.open(input_path)
        for frame_idx in range(img.n_frames):
            img.seek(frame_idx)
            frames.append(image_to_frame(img))
    else:
        # 处理静态图片
        img = Image.open(input_path)
        frames.append(image_to_frame(img))
    
    # 构建条目
    entry = {"data": frames, "tick": tick}
    line = f"{animation_id}={json.dumps(entry)}"
    
    # 写入文件（追加模式）
    with open(output_path, 'a', encoding='utf-8') as f:
        f.write(line + '\n')
    
    print(f"已转换: {input_path} -> ID: {animation_id}, 帧数: {len(frames)}")

# ---- 使用示例 ----
# 1. 准备一个文件夹，里面放所有 32x8 的图片/GIF
# 2. 修改下面的路径
input_folder = "./32x8_animations"      # 你的图片文件夹
output_file = "AnimationsCache.txt"     # 输出的 iconcache 文件

# 清空或创建输出文件
open(output_file, 'w').close()

# 遍历文件夹，逐个转换
for filename in os.listdir(input_folder):
    if filename.lower().endswith(('.png', '.jpg', '.jpeg', '.gif')):
        filepath = os.path.join(input_folder, filename)
        # 用文件名（不含扩展名）作为动画 ID
        anim_id = os.path.splitext(filename)[0]
        convert_to_iconcache(filepath, output_file, anim_id, tick=100)

print(f"\n转换完成！共处理 {len(os.listdir(input_folder))} 个文件")
print(f"输出文件: {output_file}")