local Players = game:GetService("Players")

local BestTimeService = require(script.Parent:WaitForChild("BestTimeService"))

local function wirePlayer(player: Player)
	player.CharacterAdded:Connect(function()
		-- small delay to ensure Head exists
		task.wait(0.2)
		if player.Parent then
			BestTimeService.AttachGui(player)
		end
	end)
end

Players.PlayerAdded:Connect(wirePlayer)

for _, player in ipairs(Players:GetPlayers()) do
	wirePlayer(player)
end

