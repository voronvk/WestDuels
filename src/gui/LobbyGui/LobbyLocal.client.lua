local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local lobbyGui = script.Parent
if not lobbyGui then
	warn("[LobbyLocal] script.Parent is nil")
	return
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
	label.Text = tostring(valueObj.Value)
	valueObj:GetPropertyChangedSignal("Value"):Connect(function()
		label.Text = tostring(valueObj.Value)
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

-- --- Shop UI ---
local shopButton = waitPath(lobbyGui, "Bottom", "Frame", "ShopButton")
local shopFrame = waitPath(lobbyGui, "ShopFrame")
local closeButton = waitPath(shopFrame, "CloseButton")

-- UI layout refs (para tweens al abrir/cerrar)
local leftFrame = waitPath(lobbyGui, "Left")
local bottomFrame = waitPath(lobbyGui, "Bottom")
local backGround = waitPath(lobbyGui, "BackGround")

local lighting = game:GetService("Lighting")
local blurEffect = lighting:WaitForChild("Blur")

local camera = workspace.CurrentCamera
local initialFov = camera and camera.FieldOfView or 70

-- Guardar estado inicial para poder revertir al cerrar
local initialLeftPos = leftFrame.Position
local initialBottomPos = bottomFrame.Position

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

		activeShopTweens = tweens

		for _, tw in ipairs(tweens) do
			tw:Play()
		end
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
		leftFrame.Position = initialLeftPos
		bottomFrame.Position = initialBottomPos
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

-- --- Start ---
bindLeaderstats()

