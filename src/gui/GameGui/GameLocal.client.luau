local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local localPlayer = Players.LocalPlayer
local gameGui = script.Parent :: ScreenGui

local function waitPath(root: Instance, ...: string): Instance
	local current: Instance = root
	for _, name in ipairs({ ... }) do
		current = current:WaitForChild(name)
	end
	return current
end

local remotesFolder = waitPath(ReplicatedStorage, "Shared", "Remotes") :: Folder

local evMatchStart = waitPath(remotesFolder, "MatchStart") :: RemoteEvent
local evMatchCueShoot = waitPath(remotesFolder, "MatchCueShoot") :: RemoteEvent
local evMatchClick = waitPath(remotesFolder, "MatchClick") :: RemoteEvent
local evMatchRoundResult = waitPath(remotesFolder, "MatchRoundResult") :: RemoteEvent
local evMatchEnd = waitPath(remotesFolder, "MatchEnd") :: RemoteEvent
local evClaimReward = waitPath(remotesFolder, "ClaimReward") :: RemoteEvent

local camera = workspace.CurrentCamera
local baseFov = camera and camera.FieldOfView or 70
local matchBaseFov = baseFov
local matchCameraPart = nil
local cameraFollowConn = nil

local function stopCameraFollow()
	if cameraFollowConn then
		cameraFollowConn:Disconnect()
		cameraFollowConn = nil
	end
	matchCameraPart = nil
end

local function startCameraFollow(part: BasePart)
	if not camera then
		return
	end
	stopCameraFollow()
	matchCameraPart = part
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = part.CFrame
	cameraFollowConn = RunService.RenderStepped:Connect(function()
		if not matchCameraPart or not matchCameraPart:IsDescendantOf(game) or not camera then
			return
		end
		camera.CFrame = matchCameraPart.CFrame
	end)
end

local function restorePlayerCamera()
	if not camera then
		return
	end
	stopCameraFollow()
	camera.CameraType = Enum.CameraType.Custom
	local character = localPlayer.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	camera.FieldOfView = baseFov
end

local effectBlack = gameGui:WaitForChild("EffectBlack") :: Frame
local effectBlack2 = gameGui:WaitForChild("EffectBlack2") :: Frame
local effectWhiteFrame = gameGui:WaitForChild("EffectWhite") :: Frame
local effectWhiteFrame2 = gameGui:WaitForChild("EffectWhite2") :: Frame
local effectRed = gameGui:WaitForChild("EffectRed") :: Frame
local effectGreen = gameGui:WaitForChild("EffectGreen") :: Frame
local roundLabel = gameGui:WaitForChild("RoundLabel") :: TextLabel
local winLabel = gameGui:WaitForChild("WinLabel") :: TextLabel
local timeLabel = gameGui:WaitForChild("TimeLabel") :: TextLabel
local warnLabel = gameGui:WaitForChild("WarnLabel") :: TextLabel

local fireSoundTemplate = waitPath(ReplicatedStorage, "Sounds", "Fire") :: Sound
local dramaSoundTemplate = waitPath(ReplicatedStorage, "Sounds", "Drama") :: Sound
local buttonSoundTemplate = waitPath(ReplicatedStorage, "Sounds", "Button") :: Sound
local claimSoundTemplate = waitPath(ReplicatedStorage, "Sounds", "Claim") :: Sound
local errorSoundTemplate = waitPath(ReplicatedStorage, "Sounds", "Error") :: Sound

local winnerFrame = gameGui:WaitForChild("WinnerFrame") :: Frame
local claimButton = winnerFrame:WaitForChild("ClaimButton") :: GuiButton
local claimDoubleButton = winnerFrame:WaitForChild("ClaimDoubleButton") :: GuiButton
local rewardTextLabel = (winnerFrame:WaitForChild("Reward") :: Frame):WaitForChild("TextLabel") :: TextLabel

local bgFrame = gameGui:WaitForChild("Background") :: Frame

local MUSIC_LOBBY_VOLUME = 0.4
local MUSIC_MATCH_VOLUME = 0.15
local EARLY_SHOT_PENALTY_SECONDS = 3

local function setMusicVolume(volume: number)
	local folder = SoundService:FindFirstChild("BackgroundMusic")
	if not folder then
		return
	end
	for _, inst in ipairs(folder:GetChildren()) do
		if inst:IsA("Sound") then
			TweenService:Create(inst, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = volume }):Play()
		end
	end
end

local dramaSound: Sound? = nil
local dramaTween: Tween? = nil

local function stopDrama()
	if dramaTween then
		dramaTween:Cancel()
		dramaTween = nil
	end
	if dramaSound then
		dramaSound:Stop()
		dramaSound:Destroy()
		dramaSound = nil
	end
end

local function playDrama()
	stopDrama()
	local s = dramaSoundTemplate:Clone()
	s.Volume = 0
	s.Looped = true
	s.Parent = SoundService
	dramaSound = s
	s:Play()
	dramaTween = TweenService:Create(s, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 0.5,
	})
	dramaTween:Play()
end

local inMatch = false
local currentMatchId: string? = nil
local canShoot = false
local shootAtClock: number? = nil
local shootCued = false
local firedClickForThisShoot = false
local fovRampToken = 0
local resultUiToken = 0
local penaltyToken = 0
local penaltyActive = false

local function setResetLocked(locked: boolean)
	-- Best-effort: SetCore can error if called too early.
	task.spawn(function()
		local ok = pcall(function()
			if locked then
				StarterGui:SetCore("ResetButtonCallback", false)
			else
				StarterGui:SetCore("ResetButtonCallback", true)
			end
		end)
		if not ok then
			-- ignore
		end
	end)
end

local function setLobbyVisible(visible: boolean)
	local lobby = localPlayer:WaitForChild("PlayerGui"):FindFirstChild("LobbyGui")
	if lobby and lobby:IsA("ScreenGui") then
		lobby.Enabled = visible
	end
end

local function resetMatchVisuals()
	canShoot = false
	shootAtClock = nil
	shootCued = false
	firedClickForThisShoot = false
	roundLabel.Text = ""
	winLabel.Text = ""
	timeLabel.Text = ""
	roundLabel.Visible = false
	winLabel.Visible = false
	timeLabel.Visible = false
	warnLabel.Visible = false

	effectBlack.BackgroundTransparency = 1
	effectBlack2.BackgroundTransparency = 1
	effectWhiteFrame.BackgroundTransparency = 1
	effectWhiteFrame2.BackgroundTransparency = 1
	effectRed.BackgroundTransparency = 1
	effectGreen.BackgroundTransparency = 1
	winnerFrame.Visible = false
	bgFrame.BackgroundTransparency = 1
	penaltyActive = false

	if camera then
		camera.FieldOfView = matchBaseFov
	end
end

local function tweenTransparency(frame: Frame, to: number, duration: number)
	return TweenService:Create(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = to,
	})
end

local function dramaticPhase()
	if not camera then
		return
	end
	camera.FieldOfView = baseFov

	roundLabel.Text = "Get ready..."
	roundLabel.Visible = true
	playDrama()
	setMusicVolume(MUSIC_MATCH_VOLUME)

	-- black in + start ramping FOV slowly until SHOOT
	effectWhiteFrame.BackgroundTransparency = 1
	effectWhiteFrame2.BackgroundTransparency = 1
	tweenTransparency(effectBlack, 0.25, 0.35):Play()
	tweenTransparency(effectBlack2, 0.35, 0.35):Play()

	fovRampToken += 1
	local token = fovRampToken
	task.spawn(function()
		-- Keep zooming-in (FOV down) while we're in this round and before SHOOT cue
		while token == fovRampToken and inMatch and currentMatchId do
			-- if SHOOT already allowed, stop ramping (cue will reset)
			if canShoot then
				return
			end
			if camera then
				local target = math.max(baseFov - 25, camera.FieldOfView - 0.6)
				TweenService:Create(camera, TweenInfo.new(0.08, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
					FieldOfView = target,
				}):Play()
			end
			task.wait(0.08)
		end
	end)
end

local function shootCuePhase()
	if camera then
		TweenService:Create(camera, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = baseFov,
		}):Play()
	end
	tweenTransparency(effectBlack, 1, 0.12):Play()
	tweenTransparency(effectBlack2, 1, 0.12):Play()
	tweenTransparency(effectWhiteFrame, 1, 0.12):Play()
	tweenTransparency(effectWhiteFrame2, 1, 0.12):Play()
	roundLabel.Text = "SHOOT!"
	stopDrama()
end

local function playFireSound()
	local s = fireSoundTemplate:Clone()
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

local function playButtonSound()
	local s = buttonSoundTemplate:Clone()
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

local function playClaimSound()
	local s = claimSoundTemplate:Clone()
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

local function playErrorSound()
	local s = errorSoundTemplate:Clone()
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

local function ensureScale(label: GuiObject): UIScale
	local s = label:FindFirstChildOfClass("UIScale")
	if s then
		return s
	end
	local newS = Instance.new("UIScale")
	newS.Name = "UIScale"
	newS.Scale = 1
	newS.Parent = label
	return newS
end

local function setupHoverClickScale(button: GuiButton)
	local uiscale = button:FindFirstChildOfClass("UIScale")
	if not uiscale then
		uiscale = Instance.new("UIScale")
		uiscale.Name = "UIScale"
		uiscale.Scale = 1
		uiscale.Parent = button
	end

	local base = uiscale.Scale
	local hover = base * 1.06
	local click = base * 0.94
	local dur = 0.12
	local hovering = false

	local function tweenTo(s)
		TweenService:Create(uiscale, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = s }):Play()
	end

	button.MouseEnter:Connect(function()
		hovering = true
		tweenTo(hover)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		tweenTo(base)
	end)
	button.Activated:Connect(function()
		playButtonSound()
		tweenTo(click)
		task.delay(0.08, function()
			if button:IsDescendantOf(game) then
				tweenTo(hovering and hover or base)
			end
		end)
	end)
end

setupHoverClickScale(claimButton)
setupHoverClickScale(claimDoubleButton)

local winnerScale = ensureScale(winnerFrame)
winnerScale.Scale = 0.9
winnerFrame.Visible = false

local function setTimeLabelColor(label: TextLabel, secondsOrX: number)
	if secondsOrX < 0 then
		label.TextColor3 = Color3.fromRGB(255, 0, 0)
		return
	end
	if secondsOrX < 0.1 then
		label.TextColor3 = Color3.fromRGB(255, 0, 255)
	elseif secondsOrX < 0.2 then
		label.TextColor3 = Color3.fromRGB(34, 255, 0)
	elseif secondsOrX > 0.4 then
		label.TextColor3 = Color3.fromRGB(255, 0, 0)
	elseif secondsOrX > 0.25 then
		label.TextColor3 = Color3.fromRGB(255, 136, 0)
	else
		label.TextColor3 = Color3.fromRGB(34, 255, 0)
	end
end

local function formatTime(secondsOrX: number): string
	if secondsOrX < 0 then
		return "x"
	end
	return string.format("%.3fs", secondsOrX)
end

local function setWinnerFrameVisible(visible: boolean)
	if visible then
		winnerFrame.Visible = true
		winnerScale.Scale = 0.9
		TweenService:Create(winnerScale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(bgFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.45 }):Play()
	else
		local tw = TweenService:Create(winnerScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 })
		tw:Play()
		TweenService:Create(bgFrame, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
		task.delay(0.14, function()
			winnerFrame.Visible = false
		end)
	end
end

local function setTimeColor(seconds: number)
	if seconds < 0.1 then
		timeLabel.TextColor3 = Color3.fromRGB(255, 0, 255)
	elseif seconds < 0.2 then
		timeLabel.TextColor3 = Color3.fromRGB(34, 255, 0)
	elseif seconds > 0.4 then
		timeLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
	elseif seconds > 0.25 then
		timeLabel.TextColor3 = Color3.fromRGB(255, 136, 0)
	else
		-- 0.2s .. 0.25s
		timeLabel.TextColor3 = Color3.fromRGB(34, 255, 0)
	end
end

local function playerNameFromUserId(userId: number): string
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then
			return p.Name
		end
	end
	return tostring(userId)
end

local function showRoundResultUI(winnerUserId: number, reactionTime: number)
	resultUiToken += 1
	local token = resultUiToken

	local winnerName = playerNameFromUserId(winnerUserId)
	winLabel.Text = string.format("%s won the round with", winnerName)
	timeLabel.Text = string.format("%.3fs", reactionTime)
	setTimeColor(reactionTime)

	local winScale = ensureScale(winLabel)
	local timeScale = ensureScale(timeLabel)

	winLabel.Visible = true
	timeLabel.Visible = true
	winScale.Scale = 0.85
	timeScale.Scale = 0.85

	TweenService:Create(winScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(timeScale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	task.delay(3, function()
		if token ~= resultUiToken then
			return
		end
		local tw1 = TweenService:Create(winScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 })
		local tw2 = TweenService:Create(timeScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 })
		tw1:Play()
		tw2:Play()
		task.delay(0.12, function()
			if token ~= resultUiToken then
				return
			end
			winLabel.Visible = false
			timeLabel.Visible = false
		end)
	end)
end

local function flash(frame: Frame, midTransparency: number)
	frame.BackgroundTransparency = 1
	local inTw = tweenTransparency(frame, midTransparency, 0.08)
	local outTw = tweenTransparency(frame, 1, 0.12)
	inTw:Play()
	inTw.Completed:Connect(function()
		outTw:Play()
	end)
end

-- Any click on screen counts once per SHOOT cue.
localPlayer:GetMouse().Button1Down:Connect(function()
	if not inMatch or not currentMatchId then
		return
	end
	if penaltyActive then
		return
	end
	-- Only apply early-shot penalty BEFORE the SHOOT cue.
	if not shootCued then
		-- Early shot penalty
		playErrorSound()
		penaltyToken += 1
		local token = penaltyToken
		penaltyActive = true
		canShoot = false
		firedClickForThisShoot = false

		local scale = ensureScale(warnLabel)
		warnLabel.Visible = true
		scale.Scale = 0.9
		local warnInTween = TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 })
		warnInTween:Play()

		task.spawn(function()
			for t = EARLY_SHOT_PENALTY_SECONDS, 1, -1 do
				if token ~= penaltyToken then
					return
				end
				warnLabel.Text = string.format("You shoot to early! (%ds...)", t)
				task.wait(1)
			end
			if token ~= penaltyToken then
				return
			end
			warnLabel.Text = "You shoot to early! (0s...)"
			local tw = TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 })
			tw:Play()
			task.wait(0.12)
			if token ~= penaltyToken then
				return
			end
			warnLabel.Visible = false
			penaltyActive = false
			-- If SHOOT already happened during the penalty, allow shooting now.
			if shootCued then
				canShoot = true
				firedClickForThisShoot = false
			end
		end)
		return
	end

	-- After SHOOT cue, if we're still locked (e.g. penalty), do nothing.
	if not canShoot then
		return
	end

	if firedClickForThisShoot then
		return
	end
	firedClickForThisShoot = true
	local clientTime = shootAtClock and (os.clock() - shootAtClock) or 0
	evMatchClick:FireServer(currentMatchId, clientTime)
end)

evMatchStart.OnClientEvent:Connect(function(matchId, cameraPart)
	currentMatchId = matchId
	inMatch = true
	gameGui.Enabled = true
	setLobbyVisible(false)
	setResetLocked(true)
	if camera then
		-- capture player's current FOV so we can restore after match
		baseFov = camera.FieldOfView
		matchBaseFov = baseFov
	end
	if cameraPart and cameraPart:IsA("BasePart") then
		startCameraFollow(cameraPart)
	end
	resetMatchVisuals()
	dramaticPhase()
end)

evMatchCueShoot.OnClientEvent:Connect(function(matchId)
	if matchId ~= currentMatchId then
		return
	end
	fovRampToken += 1
	shootCuePhase()
	shootCued = true
	-- If player is penalized for early shot, they can't shoot until penalty clears.
	canShoot = not penaltyActive
	shootAtClock = os.clock()
	firedClickForThisShoot = false
end)

evMatchRoundResult.OnClientEvent:Connect(function(matchId, winnerUserId, loserUserId, reactionTime)
	if matchId ~= currentMatchId then
		return
	end

	canShoot = false
	firedClickForThisShoot = false

	-- After a round is won: show white during the break (not black).
	effectBlack.BackgroundTransparency = 1
	effectBlack2.BackgroundTransparency = 1
	effectWhiteFrame.BackgroundTransparency = 1
	effectWhiteFrame2.BackgroundTransparency = 1
	tweenTransparency(effectWhiteFrame, 0, 0.9):Play()
	tweenTransparency(effectWhiteFrame2, 0, 0.9):Play()

	playFireSound()

	if localPlayer.UserId == winnerUserId then
		flash(effectGreen, 0.2)
	elseif localPlayer.UserId == loserUserId then
		flash(effectRed, 0.2)
	end

	showRoundResultUI(winnerUserId, reactionTime)
end)

local pendingDoublePurchaseMatchId = nil

local function closeWinnerAndReturnToLobby()
	setWinnerFrameVisible(false)
	task.delay(0.15, function()
		inMatch = false
		currentMatchId = nil
		canShoot = false
		fovRampToken += 1
		setLobbyVisible(true)
		setResetLocked(false)
		restorePlayerCamera()
		stopDrama()
		setMusicVolume(MUSIC_LOBBY_VOLUME)
		gameGui.Enabled = false
		resetMatchVisuals()
	end)
end

local function getUserThumbnail(userId: number): string
	local ok, content = pcall(function()
		local image, _ = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		return image
	end)
	if ok and typeof(content) == "string" then
		return content
	end
	return ""
end

local function fillWinnerFrame(winnerUserId: number, loserUserId: number, myTimes: { number }, oppTimes: { number }, rewardAmount: number)
	local user1Image = winnerFrame:WaitForChild("User1Image") :: ImageLabel
	local user2Image = winnerFrame:WaitForChild("User2Image") :: ImageLabel
	local user1Label = winnerFrame:WaitForChild("User1Label") :: TextLabel
	local user2Label = winnerFrame:WaitForChild("User2Label") :: TextLabel
	local user1Condition = winnerFrame:WaitForChild("User1Condition") :: TextLabel
	local user2Condition = winnerFrame:WaitForChild("User2Condition") :: TextLabel

	local user1Frame = winnerFrame:WaitForChild("User1Frame") :: Frame
	local user2Frame = winnerFrame:WaitForChild("User2Frame") :: Frame

	local function setTimes(frame: Frame, times: { number })
		local t1 = frame:WaitForChild("Time1Label") :: TextLabel
		local t2 = frame:WaitForChild("Time2Label") :: TextLabel
		local t3 = frame:WaitForChild("Time3Label") :: TextLabel
		local list = { t1, t2, t3 }
		for i = 1, 3 do
			local v = times[i]
			if v == nil then
				v = -1
			end
			list[i].Text = formatTime(v)
			setTimeLabelColor(list[i], v)
		end
	end

	local myUserId = localPlayer.UserId
	local oppUserId = (myUserId == winnerUserId) and loserUserId or winnerUserId

	local function makeCircular(img: ImageLabel)
		img.BackgroundTransparency = 1
		img.ClipsDescendants = true
		local c = img:FindFirstChildOfClass("UICorner")
		if not c then
			c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = img
		else
			c.CornerRadius = UDim.new(0.5, 0)
		end
	end
	makeCircular(user1Image)
	makeCircular(user2Image)

	user1Image.Image = getUserThumbnail(myUserId)
	user2Image.Image = getUserThumbnail(oppUserId)

	user1Label.Text = "@" .. localPlayer.Name
	user2Label.Text = "@" .. playerNameFromUserId(oppUserId)

	if myUserId == winnerUserId then
		user1Condition.Text = "WINNER"
		user1Condition.TextColor3 = Color3.fromRGB(111, 255, 0)
		user2Condition.Text = "LOOSER"
		user2Condition.TextColor3 = Color3.fromRGB(255, 0, 0)
	else
		user1Condition.Text = "LOOSER"
		user1Condition.TextColor3 = Color3.fromRGB(255, 0, 0)
		user2Condition.Text = "WINNER"
		user2Condition.TextColor3 = Color3.fromRGB(111, 255, 0)
	end

	setTimes(user1Frame, myTimes)
	setTimes(user2Frame, oppTimes)

	rewardTextLabel.Text = tostring(rewardAmount)
end

claimButton.Activated:Connect(function()
	if not currentMatchId then
		return
	end
	playClaimSound()
	evClaimReward:FireServer(currentMatchId, "normal")
	closeWinnerAndReturnToLobby()
end)

-- Purchase finished handled by server receipt; UI closes on successful purchase via claim button flow.

claimDoubleButton.Activated:Connect(function()
	if not currentMatchId then
		return
	end
	pendingDoublePurchaseMatchId = currentMatchId
	playClaimSound()
	evClaimReward:FireServer(currentMatchId, "double")
	MarketplaceService:PromptProductPurchase(localPlayer, 3567279931)
	closeWinnerAndReturnToLobby()
end)

evMatchEnd.OnClientEvent:Connect(function(matchId, winnerUserId, loserUserId, myTimes, oppTimes, rewardAmount)
	if matchId ~= currentMatchId then
		return
	end

	-- End-of-match UI summary
	stopDrama()
	restorePlayerCamera()
	canShoot = false

	fillWinnerFrame(winnerUserId, loserUserId, myTimes, oppTimes, rewardAmount)
	setWinnerFrameVisible(true)
	setMusicVolume(MUSIC_LOBBY_VOLUME)
end)

-- Default hidden until server starts match
gameGui.Enabled = false

