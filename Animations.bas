B4J=true
Group="Default Group"
ModulesStructureVersion=1
Type=Class
Version=4.2
@EndOfDesignText@

Sub Class_Globals
	Dim App As AWTRIX
	Dim animationlist As List          ' 动画名称列表
	Dim animData As Map                ' 缓存解析后的动画数据: name -> Map("data":List, "tick":Int)
	Dim cacheLoaded As Boolean = False ' 本地缓存是否已加载

	' ---- 本地播放状态 ----
	Dim curFrames As List              ' 当前动画的所有帧
	Dim curFrameIdx As Int = 0         ' 当前帧索引
	Dim curFrameTick As Int = 200      ' 当前动画每帧间隔(ms)
	Dim lastFrameTime As Long = 0      ' 上一帧发送时间戳

	' ---- 可调参数 ----
	Dim MIN_FRAME_TICK As Int = 200    ' 每帧最小间隔(ms)，防止串口溢出

	Dim hasExited As Boolean = False
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
	App.Version ="1.8"
	App.Description = "Shows local 32x8 animations from AnimationsCache.txt."
	App.CoverIcon = 620
	App.Author = "Blueforcer"

	App.downloads = 0        ' 只读本地缓存，不下载
	App.Tick = 100

	App.MakeSettings
	Return "AWTRIX20"
End Sub

' ===================== 启动 =====================
Sub App_Started
	Try
		hasExited = False
		App.shouldShow = True
		curFrameIdx = 0
		lastFrameTime = 0
		curFrames = Null

		If Not(cacheLoaded) Then LoadLocalCache
		If curFrames = Null Then PickNextAnimation
	Catch
		Log("Error in App_Started: " & LastException)
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
		Log("Animations: AnimationsCache.txt not found")
	End If
End Sub

' 解析 iconcache 的 JSON 结构，仅保留 32x8 (256 像素/帧) 的动画
Private Sub ParseCache(raw As String)
	animationlist.Clear
	animData.Clear

	Dim lines As List = Regex.Split(CRLF, raw)
	For Each line As String In lines
		line = line.Trim
		If line.Length = 0 Or line.StartsWith("#") Then Continue

		Dim eqPos As Int = line.IndexOf("=")
		If eqPos <= 0 Then Continue

		Dim name As String = line.SubString2(0, eqPos).Trim
		Dim jsonValue As String = line.SubString(eqPos + 1).Trim.Replace("\","")

		Try
			Dim parser As JSONParser
			parser.Initialize(jsonValue)

			Dim d As Map
			d.Initialize

			If jsonValue.StartsWith("{") Then
				Dim item As Map = parser.NextObject
				If Not(item.ContainsKey("data")) Then Continue
				Dim data As List = item.Get("data")
				If Not(IsValid32x8(data)) Then Continue
				d.Put("data", data)
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
				If Not(IsValid32x8(dataList)) Then Continue
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
	Log("Animations: valid 32x8 entries = " & animationlist.Size)
End Sub

' 校验：每一帧都必须是 32x8（256 像素）
Private Sub IsValid32x8(data As List) As Boolean
	If data = Null Or data.Size = 0 Then Return False
	For Each frame As List In data
		If frame = Null Or frame.Size <> 256 Then Return False
	Next
	Return True
End Sub

' 随机挑一个动画
Private Sub PickNextAnimation
	If animationlist.Size = 0 Then
		curFrames = Null
		Return
	End If

	Dim tries As Int = 0
	Do While tries < 20
		Dim idx As Int = Rnd(0, animationlist.Size)
		Dim candidate As String = animationlist.Get(idx)
		Dim d As Map = animData.Get(candidate)
		If d <> Null Then
			Dim data As List = d.Get("data")
			If data <> Null And data.Size > 0 Then
				curFrames = data
				curFrameTick = d.Get("tick")
				If curFrameTick < MIN_FRAME_TICK Then curFrameTick = MIN_FRAME_TICK
				curFrameIdx = 0
				lastFrameTime = 0
				Log("Animations: play " & candidate & " (" & curFrames.Size & " frames, tick=" & curFrameTick & ")")
				Return
			End If
		End If
		tries = tries + 1
	Loop

	Log("Animations: no valid animation found")
	curFrames = Null
End Sub

' ===================== 渲染 =====================
Sub App_genFrame
	If hasExited Then Return

	If curFrames = Null Or curFrames.Size = 0 Then
		PickNextAnimation
		Return
	End If

	' ---- 节流 ----
	Dim effectiveTick As Int = curFrameTick
	If curFrames.Size = 1 Then effectiveTick = 2000

	Dim now As Long = DateTime.Now
	If lastFrameTime > 0 And (now - lastFrameTime) < effectiveTick Then Return
	lastFrameTime = now

	' ---- 取帧（仅 32x8）----
	Dim frame As List = curFrames.Get(curFrameIdx)
	Dim bmp(frame.Size) As Short
	For i = 0 To frame.Size - 1
		bmp(i) = frame.Get(i)
	Next

	App.drawBMP(0, 0, bmp, 32, 8)

	' ---- 推进 ----
	curFrameIdx = curFrameIdx + 1
	If curFrameIdx > curFrames.Size - 1 Then PickNextAnimation
End Sub

' ===================== 退出 =====================
Sub App_Exited
	hasExited = True
End Sub
