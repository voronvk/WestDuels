print("Hello world, from server!")

local Players = game:GetService("Players")

local function setupLeaderstats(player: Player)
	-- Roblox muestra automáticamente estos valores en la UI cuando se llaman "leaderstats"
	if player:FindFirstChild("leaderstats") then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	-- Valor inicial para que el Lobby muestre 100 monedas
	cash.Value = 100
	cash.Parent = leaderstats

	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = 0
	wins.Parent = leaderstats
end

Players.PlayerAdded:Connect(setupLeaderstats)

-- Por si el script se reinicia en vivo mientras hay jugadores conectados
for _, player in Players:GetPlayers() do
	setupLeaderstats(player)
end
