local Players = game:GetService("Players")

local StreakService = require(script.Parent:WaitForChild("StreakService"))

local function wirePlayer(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		if player.Parent then
			StreakService.AttachGui(player)
		end
	end)
end

Players.PlayerAdded:Connect(wirePlayer)

for _, player in ipairs(Players:GetPlayers()) do
	wirePlayer(player)
end

