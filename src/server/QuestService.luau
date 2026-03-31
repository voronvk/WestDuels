local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QUESTS_DS = DataStoreService:GetDataStore("WestDuels_Quests_v1")

local QUEST_REROLL_PRODUCT_ID = 3567311604

local function getOrCreateRemote(name: string): RemoteEvent
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	if not shared then
		shared = Instance.new("Folder")
		shared.Name = "Shared"
		shared.Parent = ReplicatedStorage
	end
	local remotes = shared:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = shared
	end
	local ev = remotes:FindFirstChild(name)
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	local newEv = Instance.new("RemoteEvent")
	newEv.Name = name
	newEv.Parent = remotes
	return newEv
end

local evQuestSync = getOrCreateRemote("QuestSync")

export type QuestType = "play_minutes" | "win_rounds" | "win_games" | "earn_coins"

export type Quest = {
	id: string,
	qtype: QuestType,
	target: number,
	progress: number,
	reward: number, -- coins
	claimed: boolean,
}

type PlayerState = {
	dateKey: string,
	quests: { Quest },
	lastCash: number,
	playSeconds: number,
	lastPlayMinutes: number,
	lastSaveAt: number,
}

local states: { [Player]: PlayerState } = {}

local function utcDateKey(): string
	-- YYYY-MM-DD in UTC
	local t = os.date("!*t")
	return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

local function randInt(a: number, b: number): number
	return math.random(a, b)
end

local function rewardFromDifficulty(d: number): number
	-- d in [0,1]; rewards 1k..10k exact
	local k = 1 + math.floor(d * 9 + 0.00001)
	k = math.clamp(k, 1, 10)
	return k * 1000
end

local function makeQuest(qtype: QuestType): Quest
	if qtype == "play_minutes" then
		local target = randInt(10, 40)
		local d = (target - 10) / (40 - 10)
		return {
			id = "play_minutes",
			qtype = qtype,
			target = target,
			progress = 0,
			reward = rewardFromDifficulty(d),
			claimed = false,
		}
	elseif qtype == "win_rounds" then
		local target = randInt(15, 35)
		local d = (target - 15) / (35 - 15)
		return {
			id = "win_rounds",
			qtype = qtype,
			target = target,
			progress = 0,
			reward = rewardFromDifficulty(d),
			claimed = false,
		}
	elseif qtype == "win_games" then
		local target = randInt(5, 15)
		local d = (target - 5) / (15 - 5)
		return {
			id = "win_games",
			qtype = qtype,
			target = target,
			progress = 0,
			reward = rewardFromDifficulty(d),
			claimed = false,
		}
	else
		local target = randInt(250, 500)
		local d = (target - 250) / (500 - 250)
		return {
			id = "earn_coins",
			qtype = qtype,
			target = target,
			progress = 0,
			reward = rewardFromDifficulty(d),
			claimed = false,
		}
	end
end

local QUEST_POOL: { QuestType } = { "play_minutes", "win_rounds", "win_games", "earn_coins" }

local function generateQuests(): { Quest }
	-- 3 random (allow duplicates? prefer unique)
	local pool = table.clone(QUEST_POOL)
	local quests: { Quest } = {}
	for _ = 1, 3 do
		local idx = randInt(1, #pool)
		local qt = pool[idx]
		table.remove(pool, idx)
		table.insert(quests, makeQuest(qt))
	end
	return quests
end

local function titleForQuest(q: Quest): string
	if q.qtype == "play_minutes" then
		return string.format("Play for %d minutes", q.target)
	elseif q.qtype == "win_rounds" then
		return string.format("Win %d rounds", q.target)
	elseif q.qtype == "win_games" then
		return string.format("Win %d games", q.target)
	else
		return string.format("Earn %d coins", q.target)
	end
end

local function sync(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local payload = {}
	for i, q in ipairs(st.quests) do
		payload[i] = {
			qtype = q.qtype,
			title = titleForQuest(q),
			target = q.target,
			progress = q.progress,
			reward = q.reward,
			claimed = q.claimed,
		}
	end
	evQuestSync:FireClient(player, payload)
end

local function saveAsync(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local key = tostring(player.UserId)
	local data = {
		dateKey = st.dateKey,
		quests = st.quests,
	}
	pcall(function()
		QUESTS_DS:SetAsync(key, data)
	end)
end

local function grantIfComplete(player: Player, q: Quest)
	if q.claimed then
		return
	end
	if q.progress < q.target then
		return
	end
	q.claimed = true

	-- grant coins
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local cash = leaderstats:FindFirstChild("Cash")
		if cash and cash:IsA("IntValue") then
			cash.Value += q.reward
		end
	end
end

local function clampProgress(q: Quest)
	q.progress = math.clamp(q.progress, 0, q.target)
end

local QuestService = {}

function QuestService.GetRerollProductId(): number
	return QUEST_REROLL_PRODUCT_ID
end

function QuestService.InitPlayer(player: Player)
	local key = tostring(player.UserId)
	local today = utcDateKey()

	local loaded: any = nil
	pcall(function()
		loaded = QUESTS_DS:GetAsync(key)
	end)

	local quests: { Quest } = {}
	local dateKey = today
	if typeof(loaded) == "table" and typeof(loaded.quests) == "table" and typeof(loaded.dateKey) == "string" then
		dateKey = loaded.dateKey
		quests = loaded.quests
	end

	if dateKey ~= today or #quests ~= 3 then
		dateKey = today
		quests = generateQuests()
	end

	local cashValue = 0
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local cash = leaderstats:FindFirstChild("Cash")
		if cash and cash:IsA("IntValue") then
			cashValue = cash.Value
		end
	end

	states[player] = {
		dateKey = dateKey,
		quests = quests,
		lastCash = cashValue,
		playSeconds = 0,
		lastPlayMinutes = 0,
		lastSaveAt = os.clock(),
	}

	-- ensure invariants
	for _, q in ipairs(quests) do
		clampProgress(q)
		if q.progress >= q.target then
			q.claimed = true
		end
	end

	sync(player)
	saveAsync(player)
end

function QuestService.Reroll(player: Player)
	local st = states[player]
	if not st then
		return
	end
	st.dateKey = utcDateKey()
	st.quests = generateQuests()
	sync(player)
	saveAsync(player)
end

function QuestService.OnRoundWin(player: Player)
	local st = states[player]
	if not st then
		return
	end
	for _, q in ipairs(st.quests) do
		if q.qtype == "win_rounds" and not q.claimed then
			q.progress += 1
			clampProgress(q)
			grantIfComplete(player, q)
		end
	end
	sync(player)
	saveAsync(player)
end

function QuestService.OnGameWin(player: Player)
	local st = states[player]
	if not st then
		return
	end
	for _, q in ipairs(st.quests) do
		if q.qtype == "win_games" and not q.claimed then
			q.progress += 1
			clampProgress(q)
			grantIfComplete(player, q)
		end
	end
	sync(player)
	saveAsync(player)
end

function QuestService.OnCoinsEarned(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local st = states[player]
	if not st then
		return
	end
	for _, q in ipairs(st.quests) do
		if q.qtype == "earn_coins" and not q.claimed then
			q.progress += amount
			clampProgress(q)
			grantIfComplete(player, q)
		end
	end
	sync(player)
	saveAsync(player)
end

function QuestService.TickPlaytime(dt: number)
	for player, st in pairs(states) do
		if player.Parent then
			st.playSeconds += dt
			local minutes = math.floor(st.playSeconds / 60)
			local changed = false
			for _, q in ipairs(st.quests) do
				if q.qtype == "play_minutes" and not q.claimed then
					if minutes > q.progress then
						q.progress = math.min(minutes, q.target)
						grantIfComplete(player, q)
						changed = true
					end
				end
			end
			if minutes ~= st.lastPlayMinutes then
				st.lastPlayMinutes = minutes
				changed = true
			end

			local now = os.clock()
			if changed or (now - st.lastSaveAt) >= 30 then
				st.lastSaveAt = now
				sync(player)
				saveAsync(player)
			end
		end
	end
	-- sync throttled outside; keep simple: sync once per tick for those with changes? omitted.
end

function QuestService.SavePlayer(player: Player)
	saveAsync(player)
end

function QuestService.RemovePlayer(player: Player)
	saveAsync(player)
	states[player] = nil
end

function QuestService.HandleQuestRerollReceipt(player: Player): boolean
	if not states[player] then
		QuestService.InitPlayer(player)
	end
	QuestService.Reroll(player)
	return true
end

return QuestService

