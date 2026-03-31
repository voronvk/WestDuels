local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local QuestService = require(script.Parent:WaitForChild("QuestService"))

Players.PlayerAdded:Connect(function(player)
	QuestService.InitPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	QuestService.RemovePlayer(player)
end)

-- bootstrap existing players (studio live reload)
for _, player in ipairs(Players:GetPlayers()) do
	QuestService.InitPlayer(player)
end

-- playtime ticking
RunService.Heartbeat:Connect(function(dt)
	QuestService.TickPlaytime(dt)
end)

