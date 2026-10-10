B4J=true
Group="Default Group"
ModulesStructureVersion=1
Type=Class
Version=4.2
@EndOfDesignText@

Sub Class_Globals
	Dim App As AWTRIX
	Dim animationlist As List          ' 动画名称列表
	Dim nextAnimation As String        ' 当前要播放的动画名
	Dim animData As Map                ' 缓存解析后的动画数据: name -> Map("data":List, "tick":Int)
	Dim cacheLoaded As Boolean = False ' 本地缓存是否已加载

	' ---- 本地播放状态 ----
	Dim curFrames As List              ' 当前动画的所有帧
	Dim curFrameIdx As Int = 0         ' 当前帧索引
	Dim curFrameTick As Int = 100      ' 当前动画每帧间隔(ms)
	Dim lastFrameTime As Long = 0      ' 上一帧发送时间戳
	Dim frameHold As Int = 0           ' 帧保持计数(用于把 tick 拆成多次 genFrame)

	' ---- 退出排空 ----
	Dim exiting As Boolean = False
	Dim exitDrainTicks As Int = 0

	' ---- 可调参数 ----
	Dim MIN_FRAME_TICK As Int = 200    ' 每帧最小间隔(ms)，防止串口溢出，可按需调大
	Dim DRAIN_TICKS As Int = 6         ' 退出前额外等待的 tick 数，让串口缓冲排空
	
	Dim appStartTime As Long = 0
	Dim PLAY_DURATION As Int = 20000   ' ★ 播放时长 20 秒
	
	Private curFrames As List
	Private animationIDs As List
	Private allAnimations As List
End Sub

' ignore
public Sub GetNiceName() As String
	Return App.Name
End Sub

' ignore
public Sub Run(Tag As String, Params As Map) As Object
	Return App.interface(Tag,Params)
End Sub

' ===================== 配置 App =====================
Public Sub Initialize() As String
	animationlist.Initialize
	animData.Initialize
	App.Initialize(Me,"App")
	App.Name ="Animations"
	App.Version ="1.7"
	App.Description = "Shows animations from the AWTRIX Cloud (local cache supported)."
	App.CoverIcon = 620
	App.Author = "Blueforcer"

	' ★ 需求1：如果本地已有缓存，则不需要下载处理器
	If File.Exists(File.Combine(File.DirApp,"Apps"),"AnimationsCache.txt") Then
		App.downloads = 0
	Else
		App.downloads = 1
	End If

	' ★ 需求2：把 tick 调大，降低单位时间发送量（默认 65 太激进）
	App.Tick = 100

	' ★ 需求3：锁定 App，AWTRIX 会等我们发 finish 才切换，避免"抢跑"导致串口冲突
	App.lock = True

	App.MakeSettings
	Return "AWTRIX20"
	
	' 统一初始化所有 List
	curFrames.Initialize
	animationIDs.Initialize
	allAnimations.Initialize
End Sub

' ===================== 启动 =====================
Sub App_Started
	Try
		App.shouldShow = True
		exiting = False
		exitDrainTicks = 0
		curFrameIdx = 0
		frameHold = 0
		lastFrameTime = 0
		appStartTime = DateTime.Now        ' ★ 记录本次播放开始时间

		' ★ 需求1：优先加载本地缓存
		If Not(cacheLoaded) Then
			LoadLocalCache
		End If

		' 选一个要播放的动画
		PickNextAnimation
	Catch
		Log("Error in App_Started: " & LastException)
		nextAnimation = "random"
	End Try
End Sub

' 读取本地缓存文件 AnimationsCache.txt
Private Sub LoadLocalCache
	Dim path As String = File.Combine(File.DirApp,"Apps")
	If File.Exists(path,"AnimationsCache.txt") Then
		Try
			Dim raw As String = File.ReadString(path,"AnimationsCache.txt")
			ParseCache(raw)
			cacheLoaded = True
			Log("Animations: loaded local cache, " & animationlist.Size & " animations")
		Catch
			Log("Animations: cache parse failed -> " & LastException)
			cacheLoaded = False
		End Try
	Else
		Log("Animations: no local cache, will download")
	End If
End Sub

' 解析 iconcache 的 JSON 结构
Private Sub ParseCache(raw As String)
	animationlist.Clear
	animData.Clear
    
	' 按行拆分 properties 文件
	Dim lines As List
	lines = Regex.Split(CRLF, raw)
    
	For Each line As String In lines
		line = line.Trim
		' 跳过空行和注释行（以#开头）
		If line.Length = 0 Or line.StartsWith("#") Then Continue
        
		' 找到第一个 = 分隔符
		Dim eqPos As Int = line.IndexOf("=")
		If eqPos <= 0 Then Continue
        
		Dim name As String = line.SubString2(0, eqPos).Trim
		Dim jsonValue As String = line.SubString(eqPos + 1).Trim
        
		' ★ 关键修复：去除 JSON 字符串中的转义反斜杠
		jsonValue = jsonValue.Replace("\", "")
        
		' 对每个值单独解析
		Dim parser As JSONParser
		parser.Initialize(jsonValue)
        
		' ... 以下解析逻辑保持不变 ...
		Dim d As Map
		d.Initialize
        
		If jsonValue.StartsWith("{") Then
			Dim item As Map = parser.NextObject
			d.Put("data", item.Get("data"))
			If item.ContainsKey("tick") Then
				d.Put("tick", item.Get("tick"))
			Else
				d.Put("tick", 100)
			End If
		Else If jsonValue.StartsWith("[") Then
			Dim frameList As List = parser.NextArray
			Dim dataList As List
			dataList.Initialize
			dataList.Add(frameList)
			d.Put("data", dataList)
			d.Put("tick", 100)
		Else
			Continue
		End If
        
		animData.Put(name, d)
		animationlist.Add(name)
	Next
End Sub


' 随机挑一个动画（可结合 App.settings 做白名单，这里保持简单）
Private Sub PickNextAnimation
	If animationlist.Size = 0 Then
		nextAnimation = "random"
		curFrames = Null
		Return
	End If
	Dim idx As Int = Rnd(0, animationlist.Size)
	nextAnimation = animationlist.Get(idx)
	Dim d As Map = animData.Get(nextAnimation)
	curFrames = d.Get("data")
	curFrameTick = d.Get("tick")
	If curFrameTick < MIN_FRAME_TICK Then curFrameTick = MIN_FRAME_TICK
	curFrameIdx = 0
	frameHold = 0
	lastFrameTime = DateTime.Now
	Log("Animations: play " & nextAnimation & " (" & curFrames.Size & " frames, tick=" & curFrameTick & ")")
End Sub

' ===================== 下载（仅当无缓存时） =====================
Sub App_startDownload(jobNr As Int)
	Select jobNr
		Case 1
			' ★ 需求1：有缓存就绝不发起下载
			If File.Exists(File.Combine(File.DirApp,"Apps"),"AnimationsCache.txt") Then
				Return
			End If
			App.Download("https://awtrix.blueforcer.de/animations/iconcache")
	End Select
End Sub

Sub App_evalJobResponse(Resp As JobResponse)
	Try
		If Resp.success Then
			Select Resp.jobNr
				Case 1
					' 把整份 iconcache 原样落盘，下次启动直接读本地
					File.WriteString(File.Combine(File.DirApp,"Apps"),"AnimationsCache.txt",Resp.ResponseString)
					ParseCache(Resp.ResponseString)
					cacheLoaded = True
					Log("Animations: downloaded & cached " & animationlist.Size & " animations")
			End Select
		End If
	Catch
		Log("Error in App_evalJobResponse: " & LastException)
	End Try
End Sub

Sub App_genFrame
	If curFrames.IsInitialized = False Then curFrames.Initialize
	If animationIDs.IsInitialized = False Then animationIDs.Initialize

	' ---- 退出排空 ----
	If exiting Then
		If exitDrainTicks > 0 Then
			exitDrainTicks = exitDrainTicks - 1
			Return
		Else
			App.finish
			Return
		End If
	End If

	' ★ 播放超过 20 秒 → 请求平滑退出，交给 AWTRIX 切换下一个应用
	If DateTime.Now - appStartTime >= PLAY_DURATION Then
		Log("Animations: 20s reached, exiting...")
		RequestExit
		Return
	End If
	
	' ---- 无帧数据时回退 ----
	If curFrames = Null Or curFrames.Size = 0 Then
		App.customCommand(CreateMap("type":"animation","ID":nextAnimation))
		Return
	End If

	' ---- 节流：单帧动画至少停留 2 秒 ----
	Dim effectiveTick As Int = curFrameTick
	If curFrames.Size = 1 Then effectiveTick = 2000

	Dim now As Long = DateTime.Now
	If lastFrameTime > 0 And (now - lastFrameTime) < effectiveTick Then
		Return
	End If
	lastFrameTime = now

	' ---- 取当前帧，按实际像素数推断尺寸 ----
	Dim frame As List = curFrames.Get(curFrameIdx)
	Dim bmp(frame.Size) As Short
	For i = 0 To frame.Size - 1
		bmp(i) = frame.Get(i)
	Next

	Dim w As Int, h As Int
	Select frame.Size
		Case 64
			w = 8 : h = 8          ' ★ 你的数据都是 8×8 图标
		Case 256
			w = 32 : h = 8
		Case Else
			Log("Animations: unexpected frame size " & frame.Size & ", skip")
			curFrameIdx = curFrameIdx + 1
			If curFrameIdx > curFrames.Size - 1 Then PickNextAnimation
			Return
	End Select
	
	' 如果希望 8×8 图标居中显示，把 x 改成 (32 - w) / 2，即 12
	App.drawBMP(0, 0, bmp, w, h)

	' ---- 推进帧索引，整个动画播完才换 ----
	curFrameIdx = curFrameIdx + 1
	If curFrameIdx > curFrames.Size - 1 Then
		PickNextAnimation
	End If
End Sub

' ===================== 退出 =====================
Sub App_Exited
	exiting = False
	exitDrainTicks = 0
End Sub

' 供外部/定时器调用：请求平滑退出（先排空再 finish）
Public Sub RequestExit
	exiting = True
	exitDrainTicks = DRAIN_TICKS
End Sub
