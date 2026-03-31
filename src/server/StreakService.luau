local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local TextChatService = game:GetService("TextChatService")

local STREAK_DS = DataStoreService:GetDataStore("WestDuels_Streak_v1")

local StreakGuiTemplate = ServerStorage:WaitForChild("StreakGui")

local ORANGE = Color3.fromRGB(255, 136, 0)

local function load(userId: number): number
	local key = tostring(userId)
	local value: any = 0
	pcall(function()
		value = STREAK_DS:GetAsync(key)
	end)
	if typeof(value) == "number" and value >= 0 then
		return math.floor(value)
	end
	return 0
end

local function save(userId: number, streak: number)
	local key = tostring(userId)
	pcall(function()
		STREAK_DS:SetAsync(key, math.floor(math.max(streak, 0)))
	end)
end

local function broadcastStreakLost(playerName: string, streak: number)
	local text = string.format("%s lost his %d win streak!", playerName, streak)
	local rich = string.format('<font color="rgb(%d,%d,%d)">%s</font>', ORANGE.R * 255, ORANGE.G * 255, ORANGE.B * 255, text)

	if TextChatService and TextChatService.TextChannels then
		local channel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
		if channel and channel.DisplaySystemMessage then
			channel:DisplaySystemMessage(rich)
			return
		end
	end
	-- Fallback: no-op if TextChatService isn't configured
end

local function applyToCharacter(character: Model, streak: number)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	local existing = character:FindFirstChild("StreakGui")
	if existing then
		existing:Destroy()
	end

	local gui = StreakGuiTemplate:Clone()
	gui.Name = "StreakGui"
	gui.Parent = character

	if gui:IsA("BillboardGui") then
		gui.Enabled = streak > 0
		gui.Adornee = head
	end

	local major = gui:FindFirstChild("MajorLabel", true)
	local minor = gui:FindFirstChild("MinorLabel", true)
	local streakLabel = gui:FindFirstChild("StreakLabel", true)

	if major and major:IsA("TextLabel") then
		major.Visible = streak >= 10
	end
	if minor and minor:IsA("TextLabel") then
		minor.Visible = streak > 0 and streak < 10
	end
	if streakLabel and streakLabel:IsA("TextLabel") then
		streakLabel.Text = tostring(streak)
		streakLabel.Visible = streak > 0
	end
end

local StreakService = {}

function StreakService.AttachGui(player: Player)
	local streak = load(player.UserId)
	local character = player.Character
	if not character then
		return
	end
	applyToCharacter(character, streak)
end

function StreakService.ReportMatchWin(player: Player)
	local current = load(player.UserId)
	local nextStreak = current + 1
	save(player.UserId, nextStreak)
	if player.Character then
		applyToCharacter(player.Character, nextStreak)
	end
end

function StreakService.ReportMatchLoss(player: Player)
	local current = load(player.UserId)
	if current >= 10 then
		broadcastStreakLost(player.Name, current)
	end
	if current ~= 0 then
		save(player.UserId, 0)
		if player.Character then
			applyToCharacter(player.Character, 0)
		end
	end
end

return StreakService

