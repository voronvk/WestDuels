local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")

local localPlayer = Players.LocalPlayer

local lobbyGui = script.Parent
if not lobbyGui then
	warn("[LobbyLocal] script.Parent is nil")
	return
end

local buttonSoundTemplate: Sound? = nil
do
	local sounds = ReplicatedStorage:FindFirstChild("Sounds")
	if sounds then
		local s = sounds:FindFirstChild("Button")
		if s and s:IsA("Sound") then
			buttonSoundTemplate = s
		end
	end
end

local function playButtonSound()
	if not buttonSoundTemplate then
		return
	end
	local s = buttonSoundTemplate:Clone()
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

local function waitPath(root, ...)
	local current = root
	for _, part in ipairs({...}) do
		current = current:WaitForChild(part)
	end
	return current
end

local function getUIScale(obj)
	return obj:FindFirstChildOfClass("UIScale")
end

local function setupHoverClickScale(imageButton)
	local wiredAttrName = "LobbyUIScaleWired"
	local uiscale = getUIScale(imageButton)
	if not uiscale then
		return
	end
	if imageButton:GetAttribute(wiredAttrName) then
		return
	end
	imageButton:SetAttribute(wiredAttrName, true)

	local baseScale = uiscale.Scale
	local hoverScale = baseScale * 1.08
	local clickScale = baseScale * 0.95
	local duration = 0.15
	local isHovering = false

	local function tweenTo(scale)
		TweenService:Create(uiscale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = scale,
		}):Play()
	end

	imageButton.MouseEnter:Connect(function()
		isHovering = true
		tweenTo(hoverScale)
	end)

	imageButton.MouseLeave:Connect(function()
		isHovering = false
		tweenTo(baseScale)
	end)

	local function doClick()
		playButtonSound()
		tweenTo(clickScale)
		task.delay(0.08, function()
			if imageButton:IsDescendantOf(game) then
				tweenTo(isHovering and hoverScale or baseScale)
			end
		end)
	end

	-- Activated cubre mouse/teclado en general; MouseButton1Click cubre más casos.
	imageButton.Activated:Connect(doClick)
	imageButton.MouseButton1Click:Connect(doClick)
end

-- --- Leaderstats (Cash/Wins) ---
local function bindLabelToValue(label, valueObj)
	local function formatShort(n: number): string
		local abs = math.abs(n)
		if abs >= 1_000_000_000 then
			local v = n / 1_000_000_000
			return string.format("%.1fB", v):gsub("%.0B$", "B")
		elseif abs >= 1_000_000 then
			local v = n / 1_000_000
			return string.format("%.1fM", v):gsub("%.0M$", "M")
		elseif abs >= 1_000 then
			local v = n / 1_000
			return string.format("%.1fk", v):gsub("%.0k$", "k")
		else
			return tostring(math.floor(n + 0.5))
		end
	end

	local function setText(v: number)
		label.Text = formatShort(v)
	end

	setText(tonumber(valueObj.Value) or 0)
	local animToken = 0
	local lastValue = tonumber(valueObj.Value) or 0

	local function animateTo(newValue: number)
		animToken += 1
		local token = animToken

		local startValue = lastValue
		local duration = 0.6
		local t0 = os.clock()

		while token == animToken do
			local a = (os.clock() - t0) / duration
			if a >= 1 then
				break
			end
			local eased = 1 - (1 - a) * (1 - a)
			local v = startValue + (newValue - startValue) * eased
			setText(v)
			task.wait()
		end
		setText(newValue)
		lastValue = newValue
	end

	valueObj:GetPropertyChangedSignal("Value"):Connect(function()
		local newValue = tonumber(valueObj.Value) or 0
		if newValue > lastValue then
			animateTo(newValue)
		else
			animToken += 1
			setText(newValue)
			lastValue = newValue
		end
	end)
end

local function bindLeaderstats()
	local leaderstats = localPlayer:WaitForChild("leaderstats")
	local cash = leaderstats:WaitForChild("Cash")
	local wins = leaderstats:WaitForChild("Wins")

	local coinsLabel = waitPath(lobbyGui, "Left", "CoinsFrame", "CoinsLabel")
	local winsLabel = waitPath(lobbyGui, "Left", "WinsFrame", "WinsLabel")

	bindLabelToValue(coinsLabel, cash)
	bindLabelToValue(winsLabel, wins)
end

-- --- Quests UI ---
local questSyncEvent: RemoteEvent? = nil
do
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local remotes = shared:WaitForChild("Remotes")
	questSyncEvent = remotes:WaitForChild("QuestSync") :: RemoteEvent
end

local rightFrame = waitPath(lobbyGui, "Right")
local refreshButton = waitPath(rightFrame, "Refreshbutton") :: GuiButton
setupHoverClickScale(refreshButton)

local questsContainer = waitPath(rightFrame, "Frame")
local questFrames = {}
for _, child in ipairs(questsContainer:GetDescendants()) do
	if child:IsA("Frame") and child.Name == "QuestFrame" and child:FindFirstChild("FillFrame") then
		table.insert(questFrames, child)
	end
end
table.sort(questFrames, function(a, b)
	return a.LayoutOrder < b.LayoutOrder
end)

local function formatRewardCoins(reward: number): string
	-- show (+5K) style
	local k = math.floor((reward or 0) / 1000 + 0.5)
	return string.format("(+%dK)", k)
end

local function updateQuestFrame(frame: Frame, questData)
	local titleLabel = frame:FindFirstChild("TextLabel")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = questData.title or "Quest"
	end

	local rewardIcon = frame:FindFirstChildWhichIsA("ImageLabel")
	if rewardIcon and rewardIcon:IsA("ImageLabel") then
		local rewardLabel = rewardIcon:FindFirstChild("TextLabel")
		if rewardLabel and rewardLabel:IsA("TextLabel") then
			rewardLabel.Text = formatRewardCoins(questData.reward)
		end
	end

	local fillFrame = frame:FindFirstChild("FillFrame")
	if fillFrame and fillFrame:IsA("Frame") then
		local progLabel = fillFrame:FindFirstChild("TextLabel")
		if progLabel and progLabel:IsA("TextLabel") then
			progLabel.Text = string.format("%d/%d", questData.progress or 0, questData.target or 0)
		end
		local filler = fillFrame:FindFirstChild("Filler")
		if filler and filler:IsA("Frame") then
			local progress = (questData.progress or 0)
			local target = math.max(questData.target or 1, 1)
			local ratio = math.clamp(progress / target, 0, 1)
			TweenService:Create(filler, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.new(ratio, 0, 1, 0),
			}):Play()
		end
	end
end

if questSyncEvent then
	questSyncEvent.OnClientEvent:Connect(function(questsPayload)
		if typeof(questsPayload) ~= "table" then
			return
		end
		for i, frame in ipairs(questFrames) do
			local q = questsPayload[i]
			if q then
				updateQuestFrame(frame, q)
			end
		end
	end)
end

refreshButton.Activated:Connect(function()
	MarketplaceService:PromptProductPurchase(localPlayer, 3567311604)
end)

-- --- Shop UI ---
local shopButton = waitPath(lobbyGui, "Bottom", "Frame", "ShopButton")
local playButton = waitPath(lobbyGui, "Bottom", "Frame", "Playbutton") :: GuiButton
local shopFrame = waitPath(lobbyGui, "ShopFrame")
local closeButton = waitPath(shopFrame, "CloseButton")

-- Play button -> join queue
local joinQueueEvent: RemoteEvent? = nil
do
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local remotes = shared:WaitForChild("Remotes")
	joinQueueEvent = remotes:WaitForChild("JoinQueue") :: RemoteEvent
end

playButton.MouseButton1Click:Connect(function()
	if joinQueueEvent then
		joinQueueEvent:FireServer()
	end
end)

-- UI layout refs (para tweens al abrir/cerrar)
local leftFrame = waitPath(lobbyGui, "Left")
local bottomFrame = waitPath(lobbyGui, "Bottom")
local rightFrame = waitPath(lobbyGui, "Right")
local backGround = waitPath(lobbyGui, "BackGround")

local lighting = game:GetService("Lighting")
local blurEffect = lighting:WaitForChild("Blur")

local camera = workspace.CurrentCamera
local initialFov = camera and camera.FieldOfView or 70

-- Guardar estado inicial para poder revertir al cerrar
local initialLeftPos = leftFrame.Position
local initialBottomPos = bottomFrame.Position
local initialRightPos = rightFrame.Position

local function syncBottomUnlocked()
	-- Default: visible unless server explicitly locks it
	local attr = localPlayer:GetAttribute("BottomUnlocked")
	local unlocked = (attr == nil) or (attr == true)
	if unlocked then
		bottomFrame.Visible = true
		bottomFrame.Position = initialBottomPos
	else
		bottomFrame.Visible = false
	end
end
localPlayer:GetAttributeChangedSignal("BottomUnlocked"):Connect(syncBottomUnlocked)
syncBottomUnlocked()

-- Asegura baseline de transparencia según lo pedido:
-- inicial en 1 (invisible), al abrir -> 0.25, al cerrar -> 1
backGround.BackgroundTransparency = 1

-- Config base de estado inicial
shopButton.Active = true
shopButton.Selectable = true
closeButton.Active = true
closeButton.Selectable = true

shopFrame.Visible = false
local shopOpen = false
local shopAnimId = 0
local activeShopTweens = {}

-- Animación de abrir/cerrar con UIScale
local shopScale = getUIScale(shopFrame)
if not shopScale then
	shopScale = Instance.new("UIScale")
	shopScale.Name = "UIScale"
	shopScale.Scale = 0.9
	shopScale.Parent = shopFrame
end

local shopOpenFrom = shopScale.Scale
local shopOpenTo = 1
local shopCloseTo = 0.9
local shopDuration = 0.18

local function setShopVisible(visible)
	shopAnimId += 1
	local thisAnimId = shopAnimId
	if visible == shopOpen then
		return
	end
	-- Actualiza el target desde el inicio para que Close funcione
	-- incluso si el usuario clica durante el tween de apertura.
	shopOpen = visible

	local tweenInfo = TweenInfo.new(shopDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if visible then
		-- Si veníamos de un cierre rápido mientras se abren tweens, cancelamos los anteriores.
		for _, tw in ipairs(activeShopTweens) do
			tw:Cancel()
		end
		activeShopTweens = {}

		shopFrame.Visible = true
		shopScale.Scale = shopOpenFrom

		local leftExitPos = UDim2.new(
			initialLeftPos.X.Scale,
			initialLeftPos.X.Offset - leftFrame.AbsoluteSize.X - 20,
			initialLeftPos.Y.Scale,
			initialLeftPos.Y.Offset
		)

		local bottomExitPos = UDim2.new(
			initialBottomPos.X.Scale,
			initialBottomPos.X.Offset,
			initialBottomPos.Y.Scale,
			initialBottomPos.Y.Offset + bottomFrame.AbsoluteSize.Y + 20
		)

		local rightExitPos = UDim2.new(
			initialRightPos.X.Scale,
			initialRightPos.X.Offset + rightFrame.AbsoluteSize.X + 20,
			initialRightPos.Y.Scale,
			initialRightPos.Y.Offset
		)

		local tweens = {}
		table.insert(tweens, TweenService:Create(shopScale, tweenInfo, { Scale = shopOpenTo }))
		if camera then
			table.insert(tweens, TweenService:Create(camera, tweenInfo, { FieldOfView = initialFov + 10 }))
		end
		if blurEffect then
			table.insert(tweens, TweenService:Create(blurEffect, tweenInfo, { Size = 24 }))
		end
		if backGround then
			table.insert(tweens, TweenService:Create(backGround, tweenInfo, { BackgroundTransparency = 0.25 }))
		end
		table.insert(tweens, TweenService:Create(leftFrame, tweenInfo, { Position = leftExitPos }))
		table.insert(tweens, TweenService:Create(bottomFrame, tweenInfo, { Position = bottomExitPos }))
		table.insert(tweens, TweenService:Create(rightFrame, tweenInfo, { Position = rightExitPos }))

		activeShopTweens = tweens

		for _, tw in ipairs(tweens) do
			tw:Play()
		end
		-- Hide frames after the open tween so they fully disappear.
		task.delay(shopDuration, function()
			if thisAnimId ~= shopAnimId then
				return
			end
			-- Only hide if still open
			if shopOpen then
				leftFrame.Visible = false
				bottomFrame.Visible = false
				rightFrame.Visible = false
			end
		end)
		-- No esperamos a Completed: si durante esto se cierra, la cancelación evita races.
	else
		-- Cancelar tweens del "abrir" para que el cierre sea inmediato.
		for _, tw in ipairs(activeShopTweens) do
			tw:Cancel()
		end
		activeShopTweens = {}

		-- Cierre inmediato (sin tween): solo OFF y revertir estado visual.
		shopFrame.Visible = false
		shopScale.Scale = shopCloseTo
		leftFrame.Visible = true
		bottomFrame.Visible = true
		rightFrame.Visible = true
		leftFrame.Position = initialLeftPos
		bottomFrame.Position = initialBottomPos
		rightFrame.Position = initialRightPos
		if backGround then
			backGround.BackgroundTransparency = 1
		end
		if camera then
			camera.FieldOfView = initialFov
		end
		if blurEffect then
			blurEffect.Size = 0
		end
	end
end

-- --- Queue UI (hide Lobby UI + show Leave button) ---
local queueTweenDuration = 0.22
local queueTweenInfo = TweenInfo.new(queueTweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local leaveQueueEvent: RemoteEvent? = nil
do
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local remotes = shared:WaitForChild("Remotes")
	leaveQueueEvent = remotes:WaitForChild("LeaveQueue") :: RemoteEvent
end

local leaveButton = waitPath(lobbyGui, "LeaveButton") :: GuiButton
leaveButton.Visible = false

local leaveScale = leaveButton:FindFirstChildOfClass("UIScale")
if not leaveScale then
	leaveScale = Instance.new("UIScale")
	leaveScale.Name = "UIScale"
	leaveScale.Scale = 1
	leaveScale.Parent = leaveButton
end

setupHoverClickScale(leaveButton)

local inQueue = false

local function tweenLobbyFramesDown()
	leftFrame.Visible = true
	bottomFrame.Visible = true

	local leftExitPos = UDim2.new(
		initialLeftPos.X.Scale,
		initialLeftPos.X.Offset,
		initialLeftPos.Y.Scale,
		initialLeftPos.Y.Offset + leftFrame.AbsoluteSize.Y + 20
	)
	local bottomExitPos = UDim2.new(
		initialBottomPos.X.Scale,
		initialBottomPos.X.Offset,
		initialBottomPos.Y.Scale,
		initialBottomPos.Y.Offset + bottomFrame.AbsoluteSize.Y + 20
	)

	TweenService:Create(leftFrame, queueTweenInfo, { Position = leftExitPos }):Play()
	TweenService:Create(bottomFrame, queueTweenInfo, { Position = bottomExitPos }):Play()

	task.delay(queueTweenDuration, function()
		if inQueue and leftFrame:IsDescendantOf(game) then
			leftFrame.Visible = false
		end
		if inQueue and bottomFrame:IsDescendantOf(game) then
			bottomFrame.Visible = false
		end
	end)
end

local function restoreLobbyFrames()
	leftFrame.Visible = true
	bottomFrame.Visible = true
	leftFrame.Position = initialLeftPos
	bottomFrame.Position = initialBottomPos
end

local function setQueueUI(enabled: boolean)
	if enabled == inQueue then
		return
	end
	inQueue = enabled

	if enabled then
		-- Ensure shop is closed while queued.
		if shopOpen then
			setShopVisible(false)
		end
		shopButton.Active = false
		shopButton.Selectable = false

		tweenLobbyFramesDown()
		leaveButton.Visible = true
	else
		shopButton.Active = true
		shopButton.Selectable = true

		leaveButton.Visible = false
		restoreLobbyFrames()
	end
end

local function syncLobbyEnabled()
	-- When in a match, LobbyGui must be fully hidden and no queue UI should show.
	if localPlayer:GetAttribute("InMatch") == true then
		lobbyGui.Enabled = false
		-- ensure the leave UI isn't visible if the match starts while queued
		if inQueue then
			inQueue = false
			leaveButton.Visible = false
			restoreLobbyFrames()
		end
		return
	end
	lobbyGui.Enabled = true
end

leaveButton.MouseButton1Click:Connect(function()
	if leaveQueueEvent then
		leaveQueueEvent:FireServer()
	end
end)

-- Queue state (set by server when entering/leaving StartPart)
local function syncQueueStateFromAttr()
	-- Queue UI only when not in match
	if localPlayer:GetAttribute("InMatch") == true then
		setQueueUI(false)
		return
	end
	setQueueUI(localPlayer:GetAttribute("InQueue") == true)
end
localPlayer:GetAttributeChangedSignal("InQueue"):Connect(syncQueueStateFromAttr)
syncQueueStateFromAttr()

localPlayer:GetAttributeChangedSignal("InMatch"):Connect(function()
	syncLobbyEnabled()
	syncQueueStateFromAttr()
end)
syncLobbyEnabled()

-- --- Top buttons & scrolls ---
local topFrame = waitPath(shopFrame, "TopFrame")
local centerFrame = waitPath(shopFrame, "CenterFrame")

local coinsButton = waitPath(topFrame, "CoinsButton")
local featuredButton = waitPath(topFrame, "FeaturedButton")
local passesButton = waitPath(topFrame, "PassesButton")
local casesButton = waitPath(topFrame, "CasesButton")

local coinsScrolling = waitPath(centerFrame, "CoinsScrolling")
local featuredScrolling = waitPath(centerFrame, "FeaturedScrolling")
local passesScrolling = waitPath(centerFrame, "PassesScrolling")
local casesScrolling = waitPath(centerFrame, "CasesScrolling")

local function setScrolling(visibleKey)
	coinsScrolling.Visible = visibleKey == "Coins"
	featuredScrolling.Visible = visibleKey == "Featured"
	passesScrolling.Visible = visibleKey == "Passes"
	casesScrolling.Visible = visibleKey == "Cases"
end

local function setTopButtonSelected(selectedButton)
	local function setBtnStyle(btn, selected)
		if selected then
			btn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			btn.BackgroundTransparency = 0
		else
			btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			btn.BackgroundTransparency = 0.3
		end
	end

	setBtnStyle(coinsButton, selectedButton == coinsButton)
	setBtnStyle(featuredButton, selectedButton == featuredButton)
	setBtnStyle(passesButton, selectedButton == passesButton)
	setBtnStyle(casesButton, selectedButton == casesButton)
end

local function wireTopButton(button, visibleKey)
	button.Activated:Connect(function()
		-- Scrolls: solo Visible/Not Visible (sin animaciones)
		setScrolling(visibleKey)
		setTopButtonSelected(button)
	end)
end

-- Inicial: Featured seleccionado y FeaturedScrolling visible
setupHoverClickScale(shopButton)
setupHoverClickScale(closeButton)
setupHoverClickScale(coinsButton)
setupHoverClickScale(featuredButton)
setupHoverClickScale(passesButton)
setupHoverClickScale(casesButton)

setScrolling("Featured")
setTopButtonSelected(featuredButton)

closeButton.Activated:Connect(function()
	setShopVisible(false)
end)
closeButton.MouseButton1Click:Connect(function()
	setShopVisible(false)
end)

shopButton.Activated:Connect(function()
	setShopVisible(true)
	-- Asegurar que al abrir se mantiene Featured seleccionado (como pediste)
	setScrolling("Featured")
	setTopButtonSelected(featuredButton)
end)

-- Bottom: aplicar scale a CUALQUIER ImageButton hijo de Bottom.Frame
do
	local bottomContainer = waitPath(lobbyGui, "Bottom", "Frame")
	for _, inst in ipairs(bottomContainer:GetDescendants()) do
		if inst:IsA("ImageButton") then
			setupHoverClickScale(inst)
		end
	end
end

-- CenterFrame: aplicar scale a CUALQUIER ImageButton dentro de ShopFrame.CenterFrame
do
	for _, inst in ipairs(centerFrame:GetDescendants()) do
		if inst:IsA("ImageButton") then
			setupHoverClickScale(inst)
		end
	end
end

wireTopButton(coinsButton, "Coins")
wireTopButton(featuredButton, "Featured")
wireTopButton(passesButton, "Passes")
wireTopButton(casesButton, "Cases")

-- --- Devproducts (Coins bundles) ---
do
	local coinsScrolling = waitPath(centerFrame, "CoinsScrolling")

	local productIdByButtonName = {
		CoinBundle = 3567401315,
		MegaCoinBundle = 3567401728,
		SuperCoinBundle = 3567401813,
		UltraCoin = 3567401947,
		LegendaryCoin = 3567402052,
	}

	local function wireDevProductButton(btn: Instance, productId: number)
		if not btn:IsA("GuiButton") then
			return
		end
		btn.Activated:Connect(function()
			MarketplaceService:PromptProductPurchase(localPlayer, productId)
		end)
	end

	local function wireWithin(root: Instance)
		for _, inst in ipairs(root:GetDescendants()) do
			if inst:IsA("GuiButton") then
				local pid = productIdByButtonName[inst.Name]
				if pid then
					wireDevProductButton(inst, pid)
				end
			end
		end
	end

	local list1 = coinsScrolling:FindFirstChild("List")
	local list2 = coinsScrolling:FindFirstChild("List2")
	if list1 then
		wireWithin(list1)
	end
	if list2 then
		wireWithin(list2)
	end
	if not list1 and not list2 then
		-- fallback in case the hierarchy changes
		wireWithin(coinsScrolling)
	end

	-- Close Shop when purchase finishes (user hit OK/Close in Roblox prompt)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(player: Player, productId: number, wasPurchased: boolean)
		if player ~= localPlayer then
			return
		end
		if wasPurchased then
			-- If receipt is granted, server will also fire RobuxPurchase (sound).
			setShopVisible(false)
		end
	end)

	-- More reliable: close shop when server confirms any devproduct receipt.
	do
		local shared = ReplicatedStorage:WaitForChild("Shared")
		local remotes = shared:WaitForChild("Remotes")
		local evRobuxPurchase = remotes:WaitForChild("RobuxPurchase") :: RemoteEvent
		evRobuxPurchase.OnClientEvent:Connect(function()
			setShopVisible(false)
		end)
	end
end

-- --- Start ---
bindLeaderstats()

