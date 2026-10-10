
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
	Dim PLAY_DURATION As Int = 60000   ' ★ 播放时长 60 秒
	
	Dim finishedSent As Boolean = False
	
	Dim hasExited As Boolean = False
	
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
		hasExited = False                ' ★ 重置
		App.shouldShow = True
		exiting = False
		exitDrainTicks = 0
		finishedSent = False
		curFrameIdx = 0
		frameHold = 0
		lastFrameTime = 0
		appStartTime = DateTime.Now
		nextAnimation = ""
		curFrames = Null

		If Not(cacheLoaded) Then LoadLocalCache
		PickNextAnimation
	Catch
		Log("Error in App_Started: " & LastException)
		nextAnimation = ""
		curFrames = Null
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
    
	Dim lines As List
	lines = Regex.Split(CRLF, raw)
    
	For Each line As String In lines
		line = line.Trim
		If line.Length = 0 Or line.StartsWith("#") Then Continue
        
		Dim eqPos As Int = line.IndexOf("=")
		If eqPos <= 0 Then Continue
        
		Dim name As String = line.SubString2(0, eqPos).Trim
		Dim jsonValue As String = line.SubString(eqPos + 1).Trim
		jsonValue = jsonValue.Replace("\", "")
        
		Try
			Dim parser As JSONParser
			parser.Initialize(jsonValue)
            
			Dim d As Map
			d.Initialize
            
			If jsonValue.StartsWith("{") Then
				Dim item As Map = parser.NextObject
				If Not(item.ContainsKey("data")) Then Continue   ' ★ 过滤
				Dim data As List = item.Get("data")
				If data = Null Or data.Size = 0 Then Continue    ' ★ 过滤
				d.Put("data", data)
				If item.ContainsKey("tick") Then
					d.Put("tick", item.Get("tick"))
				Else
					d.Put("tick", 100)
				End If
			Else If jsonValue.StartsWith("[") Then
				Dim frameList As List = parser.NextArray
				If frameList = Null Or frameList.Size = 0 Then Continue
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
		Catch
			Log("Animations: skip broken entry " & name & " -> " & LastException)
		End Try
	Next
	Log("Animations: valid entries = " & animationlist.Size)
End Sub


' 随机挑一个动画（可结合 App.settings 做白名单，这里保持简单）
Private Sub PickNextAnimation
	If animationlist.Size = 0 Then
		nextAnimation = ""
		curFrames = Null
		Return
	End If
    
	' ★ 最多尝试 20 次，一定能找到一个有数据的动画
	Dim tries As Int = 0
	Do While tries < 20
		Dim idx As Int = Rnd(0, animationlist.Size)
		Dim candidate As String = animationlist.Get(idx)
		Dim d As Map = animData.Get(candidate)
		If d <> Null Then
			Dim data As List = d.Get("data")
			If data <> Null And data.Size > 0 Then
				nextAnimation = candidate
				curFrames = data
				curFrameTick = d.Get("tick")
				If curFrameTick < MIN_FRAME_TICK Then curFrameTick = MIN_FRAME_TICK
				curFrameIdx = 0
				frameHold = 0
				lastFrameTime = DateTime.Now
				Log("Animations: play " & nextAnimation & " (" & curFrames.Size & " frames, tick=" & curFrameTick & ")")
				Return
			End If
		End If
		tries = tries + 1
	Loop
    
	' 全都不行 → 直接退出，别卡着
	Log("Animations: no valid animation found, exit")
	nextAnimation = ""
	curFrames = Null
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
	' ★ 第一行：如果 AWTRIX 已经把我们切走了，绝对不要再发任何数据
	If hasExited Then Return

	If curFrames.IsInitialized = False Then curFrames.Initialize
	If animationIDs.IsInitialized = False Then animationIDs.Initialize

	' ---- 退出排空 ----
	If exiting Then
		If exitDrainTicks > 0 Then
			exitDrainTicks = exitDrainTicks - 1
			Return
		End If
		If Not(finishedSent) Then
			finishedSent = True
			App.finish
			Return
		End If
		Return
	End If

	' ---- 20 秒超时 ----
	If DateTime.Now - appStartTime >= PLAY_DURATION Then
		RequestExit
		Return
	End If

	' ---- 无有效帧 ----
	If curFrames = Null Or curFrames.Size = 0 Then
		PickNextAnimation
		If curFrames = Null Or curFrames.Size = 0 Then
			RequestExit
		End If
		Return
	End If

	' ---- 节流 ----
	Dim effectiveTick As Int = curFrameTick
	If curFrames.Size = 1 Then effectiveTick = 2000

	Dim now As Long = DateTime.Now
	If lastFrameTime > 0 And (now - lastFrameTime) < effectiveTick Then
		Return
	End If
	lastFrameTime = now

	' ---- 取帧 ----
	Dim frame As List = curFrames.Get(curFrameIdx)
	Dim bmp(frame.Size) As Short
	For i = 0 To frame.Size - 1
		bmp(i) = frame.Get(i)
	Next

	Dim w As Int, h As Int, x As Int
	Select frame.Size
		Case 64
			w = 8 : h = 8 : x = 12
		Case 256
			w = 32 : h = 8 : x = 0
		Case Else
			curFrameIdx = curFrameIdx + 1
			If curFrameIdx > curFrames.Size - 1 Then PickNextAnimation
			Return
	End Select
	
	App.drawBMP(x, 0, bmp, w, h)
	
	' ---- 推进 ----
	curFrameIdx = curFrameIdx + 1
	If curFrameIdx > curFrames.Size - 1 Then
		PickNextAnimation
	End If
End Sub

' ===================== 退出 =====================
Sub App_Exited
	hasExited = True                     ' ★ 关键：标记已退出
	exiting = False
	exitDrainTicks = 0
	finishedSent = False
End Sub

' 供外部/定时器调用：请求平滑退出（先排空再 finish）
Public Sub RequestExit
	exiting = True
	exitDrainTicks = DRAIN_TICKS
End Sub
