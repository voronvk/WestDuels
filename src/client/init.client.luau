local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VOLUME = 0.4

local TRACK_IDS = {
	137807685655328,
	110919391228823,
	1845756489,
	131197912298676,
}

local folder = SoundService:FindFirstChild("BackgroundMusic")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "BackgroundMusic"
	folder.Parent = SoundService
end

local sounds: { Sound } = {}
for i, id in ipairs(TRACK_IDS) do
	local s = Instance.new("Sound")
	s.Name = string.format("Track%d", i)
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = VOLUME
	s.Looped = false
	s.Parent = folder
	table.insert(sounds, s)
end

local function stopAll()
	for _, s in ipairs(sounds) do
		s:Stop()
	end
end

task.spawn(function()
	local index = 1
	while true do
		local s = sounds[index]
		stopAll()
		s.TimePosition = 0
		s:Play()

		-- wait until ends; if not loaded, poll IsPlaying
		while s.IsPlaying do
			task.wait(0.5)
		end

		index += 1
		if index > #sounds then
			index = 1
		end
	end
end)

-- Robux purchase sound (any confirmed devproduct receipt)
task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local remotes = shared:WaitForChild("Remotes")
	local ev = remotes:WaitForChild("RobuxPurchase") :: RemoteEvent
	local robuxSound = (ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Robux")) :: Sound

	ev.OnClientEvent:Connect(function()
		local s = robuxSound:Clone()
		s.Parent = SoundService
		s:Play()
		s.Ended:Connect(function()
			s:Destroy()
		end)
	end)
end)
