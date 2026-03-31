local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")

local BESTTIME_DS = DataStoreService:GetDataStore("WestDuels_BestTime_v1")

local TimeGuiTemplate = ServerStorage:WaitForChild("TimeGui")

local function colorForTime(seconds: number): Color3
	if seconds < 0 then
		return Color3.fromRGB(98, 98, 98)
	end
	if seconds < 0.1 then
		return Color3.fromRGB(255, 0, 255)
	elseif seconds < 0.2 then
		return Color3.fromRGB(34, 255, 0)
	elseif seconds > 0.4 then
		return Color3.fromRGB(255, 0, 0)
	elseif seconds > 0.25 then
		return Color3.fromRGB(255, 136, 0)
	else
		return Color3.fromRGB(34, 255, 0)
	end
end

local function formatTime(seconds: number?): string
	if not seconds then
		return "(none)"
	end
	return string.format("(%.3fs)", seconds)
end

local function applyToCharacter(character: Model, bestTime: number?)
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	-- Replace existing TimeGui if any
	local existing = character:FindFirstChild("TimeGui")
	if existing then
		existing:Destroy()
	end

	local gui = TimeGuiTemplate:Clone()
	gui.Name = "TimeGui"
	gui.Parent = character

	if gui:IsA("BillboardGui") then
		gui.Adornee = head
	end

	local label = gui:FindFirstChild("TimeLabel", true)
	if label and label:IsA("TextLabel") then
		if bestTime then
			label.Text = formatTime(bestTime)
			label.TextColor3 = colorForTime(bestTime)
		else
			label.Text = "(none)"
			label.TextColor3 = Color3.fromRGB(98, 98, 98)
		end
	end
end

local BestTimeService = {}

function BestTimeService.LoadBestTime(userId: number): number?
	local key = tostring(userId)
	local value: any = nil
	pcall(function()
		value = BESTTIME_DS:GetAsync(key)
	end)
	if typeof(value) == "number" and value > 0 then
		return value
	end
	return nil
end

function BestTimeService.SaveBestTime(userId: number, bestTime: number)
	local key = tostring(userId)
	pcall(function()
		BESTTIME_DS:SetAsync(key, bestTime)
	end)
end

function BestTimeService.AttachGui(player: Player)
	local bestTime = BestTimeService.LoadBestTime(player.UserId)
	local character = player.Character
	if not character then
		return
	end
	applyToCharacter(character, bestTime)
end

function BestTimeService.ReportTime(player: Player, reactionTime: number)
	if reactionTime <= 0 then
		return
	end
	local currentBest = BestTimeService.LoadBestTime(player.UserId)
	if currentBest and reactionTime >= currentBest then
		return
	end

	BestTimeService.SaveBestTime(player.UserId, reactionTime)
	local character = player.Character
	if character then
		applyToCharacter(character, reactionTime)
	end
end

return BestTimeService

