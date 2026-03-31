local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestService = require(script.Parent:WaitForChild("QuestService"))
local BestTimeService = require(script.Parent:WaitForChild("BestTimeService"))
local StreakService = require(script.Parent:WaitForChild("StreakService"))

local GAMES_FOLDER_NAME = "Games"
local GAME_MODEL_NAME = "Game"
local STARTPART_NAME = "StartPart"
local SPAWN_WAIT_NAME = "SpawnPart"
local SPAWN_PLAY_NAME = "Spawn1"

local GAME_TAKEN_ATTR = "taken"
local STARTPART_PLAYER_ATTR = "Player"

local COUNTDOWN_SECONDS = 3

local PLAYER_INQUEUE_ATTR = "InQueue"
local PLAYER_INMATCH_ATTR = "InMatch"
local PLAYER_MATCHID_ATTR = "MatchId"
local PLAYER_BOTTOM_UNLOCKED_ATTR = "BottomUnlocked"

local MATCH_DELAY_MIN = 3
local MATCH_DELAY_MAX = 7
local MATCH_HITS_TO_LOSE = 3
local ROUND_BREAK_SECONDS = 3
local DEVPRODUCT_DOUBLE_ID = 3567279931

type FreezeState = {
	walkSpeed: number?,
	jumpPower: number?,
	autoRotate: boolean?,
	platformStand: boolean?,
}

type GameRuntime = {
	gameInstance: Instance,
	startParts: { BasePart },
	startPartToPlayer: { [BasePart]: Player? },
	playerToStartPart: { [Player]: BasePart? },
	playerFreezeState: { [Player]: FreezeState },
	countdownToken: number,
}

local runtimes: { [Instance]: GameRuntime } = {}

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

type MatchRuntime = {
	id: string,
	rt: GameRuntime,
	players: { Player },
	cameraPartByPlayer: any,
	hits: { [Player]: number },
	roundNumber: number,
	timesByPlayer: { [Player]: { number } },
	roundToken: number,
	canShoot: boolean,
	cueAt: number?,
	winner: Player?,
	ended: boolean,
}

local matchesById: { [string]: MatchRuntime } = {}
local matchIdByPlayer: { [Player]: string } = {}

local evMatchStart = getOrCreateRemote("MatchStart")
local evMatchCueShoot = getOrCreateRemote("MatchCueShoot")
local evMatchClick = getOrCreateRemote("MatchClick")
local evMatchRoundResult = getOrCreateRemote("MatchRoundResult")
local evMatchEnd = getOrCreateRemote("MatchEnd")
local evClaimReward = getOrCreateRemote("ClaimReward")
local evRobuxPurchase = getOrCreateRemote("RobuxPurchase")

type PendingReward = {
	matchId: string,
	amount: number,
	claimed: boolean,
}

local pendingRewardByPlayer: { [Player]: PendingReward } = {}
local pendingDoubleRequestMatchIdByPlayer: { [Player]: string } = {}

local function findDescendant(root: Instance, names: { string }): Instance?
	local current: Instance = root
	for _, name in ipairs(names) do
		local child = current:FindFirstChild(name)
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function setGameLabel(gameInstance: Instance, text: string)
	local label = findDescendant(gameInstance, { "GameGui", "List", "TextLabel" })
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function getQueueCount(rt: GameRuntime): number
	local count = 0
	for _, sp in ipairs(rt.startParts) do
		if sp:GetAttribute(STARTPART_PLAYER_ATTR) == true then
			count += 1
		end
	end
	return count
end

local function isPlayerValid(player: Player): boolean
	if not player.Parent then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function pivotCharacterToPart(player: Player, part: BasePart)
	local character = player.Character
	if not character then
		return
	end
	-- small offset to reduce floor clipping
	local cf = part.CFrame + Vector3.new(0, 3, 0)
	character:PivotTo(cf)
end

local function getLeavePart(): BasePart?
	local gamesFolder = workspace:FindFirstChild(GAMES_FOLDER_NAME)
	local leavePart = gamesFolder and gamesFolder:FindFirstChild("LeavePart")
	if leavePart and leavePart:IsA("BasePart") then
		return leavePart
	end
	return nil
end

local function giveCash(player: Player, amount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end
	local cash = leaderstats:FindFirstChild("Cash")
	if cash and cash:IsA("IntValue") then
		cash.Value += amount
		QuestService.OnCoinsEarned(player, amount)
	end
end

local function getOpponent(match: MatchRuntime, player: Player): Player?
	for _, p in ipairs(match.players) do
		if p ~= player then
			return p
		end
	end
	return nil
end

local freezePlayer
local unfreezePlayer

local function endMatch(match: MatchRuntime, winner: Player, loser: Player)
	if match.ended then
		return
	end
	match.ended = true
	match.canShoot = false
	match.roundToken += 1

	local matchId = match.id
	-- Rewards are claimed via UI at end of match
	local winnerReward = 50
	local loserReward = 25
	pendingRewardByPlayer[winner] = { matchId = matchId, amount = winnerReward, claimed = false }
	pendingRewardByPlayer[loser] = { matchId = matchId, amount = loserReward, claimed = false }

	local winnerTimes = match.timesByPlayer[winner] or {}
	local loserTimes = match.timesByPlayer[loser] or {}
	-- Send to each player with User1=self ordering
	evMatchEnd:FireClient(winner, matchId, winner.UserId, loser.UserId, winnerTimes, loserTimes, winnerReward)
	evMatchEnd:FireClient(loser, matchId, winner.UserId, loser.UserId, loserTimes, winnerTimes, loserReward)

	-- Hide lobby bottom until they claim
	winner:SetAttribute(PLAYER_BOTTOM_UNLOCKED_ATTR, false)
	loser:SetAttribute(PLAYER_BOTTOM_UNLOCKED_ATTR, false)

	-- Quest progress
	QuestService.OnGameWin(winner)
	StreakService.ReportMatchWin(winner)
	StreakService.ReportMatchLoss(loser)

	winner:SetAttribute(PLAYER_INMATCH_ATTR, false)
	loser:SetAttribute(PLAYER_INMATCH_ATTR, false)
	winner:SetAttribute(PLAYER_MATCHID_ATTR, nil)
	loser:SetAttribute(PLAYER_MATCHID_ATTR, nil)
	matchIdByPlayer[winner] = nil
	matchIdByPlayer[loser] = nil

	-- Unfreeze both players now that match is ending
	unfreezePlayer(match.rt, winner)
	unfreezePlayer(match.rt, loser)

	-- Return both players to LeavePart and kill the loser.
	local leavePart = getLeavePart()
	if leavePart then
		if isPlayerValid(winner) then
			pivotCharacterToPart(winner, leavePart)
		end
		if isPlayerValid(loser) then
			pivotCharacterToPart(loser, leavePart)
		end
	end

	if loser.Character then
		local hum = loser.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = 0
		end
	end

	-- Free the game again
	match.rt.gameInstance:SetAttribute(GAME_TAKEN_ATTR, false)
	setGameLabel(match.rt.gameInstance, "Queue 0/2")

	matchesById[matchId] = nil
end

local function startRound(match: MatchRuntime)
	if match.ended then
		return
	end
	match.roundToken += 1
	local token = match.roundToken
	match.roundNumber += 1
	match.winner = nil
	match.canShoot = false
	match.cueAt = nil

	-- dramatic phase on clients
	for _, p in ipairs(match.players) do
		if p.Parent then
			evMatchStart:FireClient(p, match.id, match.cameraPartByPlayer[p])
		end
	end

	task.spawn(function()
		local delaySec = math.random(MATCH_DELAY_MIN * 1000, MATCH_DELAY_MAX * 1000) / 1000
		task.wait(delaySec)
		if match.ended or token ~= match.roundToken then
			return
		end

		match.canShoot = true
		match.cueAt = os.clock()
		for _, p in ipairs(match.players) do
			if p.Parent then
				evMatchCueShoot:FireClient(p, match.id)
			end
		end
	end)
end

local function createMatch(rt: GameRuntime, playersInGame: { Player }, cameraPartByPlayer: any)
	local id = tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999))
	local match: MatchRuntime = {
		id = id,
		rt = rt,
		players = playersInGame,
		cameraPartByPlayer = cameraPartByPlayer,
		hits = {},
		roundNumber = 0,
		timesByPlayer = {},
		roundToken = 0,
		canShoot = false,
		cueAt = nil,
		winner = nil,
		ended = false,
	}
	for _, p in ipairs(playersInGame) do
		match.hits[p] = 0
		match.timesByPlayer[p] = {}
		matchIdByPlayer[p] = id
		p:SetAttribute(PLAYER_INMATCH_ATTR, true)
		p:SetAttribute(PLAYER_MATCHID_ATTR, id)
		-- Keep both players locked/still during the match
		freezePlayer(rt, p)
	end
	matchesById[id] = match

	-- Block leaving while in match
	rt.gameInstance:SetAttribute(GAME_TAKEN_ATTR, true)

	startRound(match)
end

freezePlayer = function(rt, player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or not hrp:IsA("BasePart") then
		return
	end

	if not rt.playerFreezeState[player] then
		rt.playerFreezeState[player] = {
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			autoRotate = humanoid.AutoRotate,
			platformStand = humanoid.PlatformStand,
		}
	end

	-- Stop any currently playing animations so the character stays fully still.
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	hrp.Anchored = true
end

unfreezePlayer = function(rt, player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or not hrp:IsA("BasePart") then
		return
	end

	hrp.Anchored = false

	local st = rt.playerFreezeState[player]
	if st then
		if st.walkSpeed then
			humanoid.WalkSpeed = st.walkSpeed
		end
		if st.jumpPower then
			humanoid.JumpPower = st.jumpPower
		end
		if st.autoRotate ~= nil then
			humanoid.AutoRotate = st.autoRotate
		end
		if st.platformStand ~= nil then
			humanoid.PlatformStand = st.platformStand
		end
	end
	-- Ensure they come back to a normal state.
	humanoid:ChangeState(Enum.HumanoidStateType.Running)
	rt.playerFreezeState[player] = nil
end

local function releasePlayerFromStart(rt: GameRuntime, player: Player)
	local sp = rt.playerToStartPart[player]
	if not sp then
		return
	end

	rt.playerToStartPart[player] = nil
	rt.startPartToPlayer[sp] = nil
	sp:SetAttribute(STARTPART_PLAYER_ATTR, false)
	player:SetAttribute(PLAYER_INQUEUE_ATTR, false)

	-- Don't move the remaining queued player; just unfreeze the leaving one if still present.
	if player.Parent then
		local gamesFolder = workspace:FindFirstChild(GAMES_FOLDER_NAME)
		local leavePart = gamesFolder and gamesFolder:FindFirstChild("LeavePart")
		if leavePart and leavePart:IsA("BasePart") and isPlayerValid(player) then
			pivotCharacterToPart(player, leavePart)
		end
		unfreezePlayer(rt, player)
	end
end

local function refreshQueueLabel(rt: GameRuntime)
	local q = getQueueCount(rt)
	setGameLabel(rt.gameInstance, string.format("Queue %d/2", q))
end

local function cancelCountdown(rt: GameRuntime)
	rt.countdownToken += 1
	rt.gameInstance:SetAttribute(GAME_TAKEN_ATTR, false)
	refreshQueueLabel(rt)
end

local function startCountdownIfReady(rt: GameRuntime)
	if getQueueCount(rt) < 2 then
		return
	end

	-- Lock game when both occupied
	rt.gameInstance:SetAttribute(GAME_TAKEN_ATTR, true)

	rt.countdownToken += 1
	local token = rt.countdownToken

	task.spawn(function()
		for t = COUNTDOWN_SECONDS, 1, -1 do
			if token ~= rt.countdownToken then
				return
			end

			-- If someone left, cancel
			if getQueueCount(rt) < 2 then
				if token == rt.countdownToken then
					cancelCountdown(rt)
				end
				return
			end

			setGameLabel(rt.gameInstance, string.format("Starting in %ds...", t))
			task.wait(1)
		end

		if token ~= rt.countdownToken then
			return
		end
		if getQueueCount(rt) < 2 then
			cancelCountdown(rt)
			return
		end

		-- Teleport each queued player to its Spawn1 and unfreeze them.
		-- Once the game starts, clear the queue state and begin the match loop.
		local playersInGame: { Player } = {}
		local cameraPartByPlayer = {}
		for _, sp in ipairs(rt.startParts) do
			local player = rt.startPartToPlayer[sp]
			if player and isPlayerValid(player) then
				local spawn1 = sp:FindFirstChild(SPAWN_PLAY_NAME)
				if spawn1 and spawn1:IsA("BasePart") then
					pivotCharacterToPart(player, spawn1)
				end
				unfreezePlayer(rt, player)
				table.insert(playersInGame, player)

				local camPart = sp:FindFirstChild("Camera")
				if camPart and camPart:IsA("BasePart") then
					cameraPartByPlayer[player] = camPart
				end
			end
			if player then
				rt.playerToStartPart[player] = nil
				player:SetAttribute(PLAYER_INQUEUE_ATTR, false)
			end
			rt.startPartToPlayer[sp] = nil
			sp:SetAttribute(STARTPART_PLAYER_ATTR, false)
		end

		setGameLabel(rt.gameInstance, "Game in Progress")
		if #playersInGame == 2 then
			createMatch(rt, playersInGame, cameraPartByPlayer)
		else
			-- Safety: shouldn't happen, but unlock if it does.
			rt.gameInstance:SetAttribute(GAME_TAKEN_ATTR, false)
			refreshQueueLabel(rt)
		end
	end)
end

local function onStartPartTouched(rt: GameRuntime, startPart: BasePart, hit: BasePart)
	if startPart:GetAttribute(STARTPART_PLAYER_ATTR) == true then
		return
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	-- Player already queued in this game (or elsewhere in this runtime)
	if rt.playerToStartPart[player] then
		return
	end

	-- Occupy slot
	startPart:SetAttribute(STARTPART_PLAYER_ATTR, true)
	rt.startPartToPlayer[startPart] = player
	rt.playerToStartPart[player] = startPart
	player:SetAttribute(PLAYER_INQUEUE_ATTR, true)

	local waitSpawn = startPart:FindFirstChild(SPAWN_WAIT_NAME)
	if waitSpawn and waitSpawn:IsA("BasePart") then
		pivotCharacterToPart(player, waitSpawn)
	end
	freezePlayer(rt, player)

	refreshQueueLabel(rt)
	startCountdownIfReady(rt)
end

local function wireStartPart(rt: GameRuntime, startPart: BasePart)
	if startPart:GetAttribute(STARTPART_PLAYER_ATTR) == nil then
		startPart:SetAttribute(STARTPART_PLAYER_ATTR, false)
	end

	startPart.Touched:Connect(function(hit)
		onStartPartTouched(rt, startPart, hit)
	end)
end

local function initGame(gameInstance: Instance)
	if runtimes[gameInstance] then
		return
	end

	local rt: GameRuntime = {
		gameInstance = gameInstance,
		startParts = {},
		startPartToPlayer = {},
		playerToStartPart = {},
		playerFreezeState = {},
		countdownToken = 0,
	}
	runtimes[gameInstance] = rt

	if gameInstance:GetAttribute(GAME_TAKEN_ATTR) == nil then
		gameInstance:SetAttribute(GAME_TAKEN_ATTR, false)
	else
		gameInstance:SetAttribute(GAME_TAKEN_ATTR, false)
	end

	for _, child in ipairs(gameInstance:GetChildren()) do
		if child:IsA("BasePart") and child.Name == STARTPART_NAME then
			table.insert(rt.startParts, child)
			wireStartPart(rt, child)
		end
	end

	-- Ensure initial label and attrs
	for _, sp in ipairs(rt.startParts) do
		sp:SetAttribute(STARTPART_PLAYER_ATTR, false)
	end
	setGameLabel(gameInstance, "Queue 0/2")

	-- If structure changes at runtime
	gameInstance.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") and child.Name == STARTPART_NAME then
			table.insert(rt.startParts, child)
			wireStartPart(rt, child)
			refreshQueueLabel(rt)
		end
	end)
end

local function removePlayerFromAllQueues(player: Player)
	for _, rt in pairs(runtimes) do
		if rt.playerToStartPart[player] then
			releasePlayerFromStart(rt, player)
			if getQueueCount(rt) < 2 and rt.gameInstance:GetAttribute(GAME_TAKEN_ATTR) == true then
				cancelCountdown(rt)
			else
				refreshQueueLabel(rt)
			end
		end
	end
end

local function leaveQueue(player: Player)
	if player:GetAttribute(PLAYER_INMATCH_ATTR) == true then
		return
	end
	removePlayerFromAllQueues(player)
end

local leaveQueueRemote = getOrCreateRemote("LeaveQueue")
leaveQueueRemote.OnServerEvent:Connect(function(player: Player)
	leaveQueue(player)
end)

local function tryJoinQueue(player: Player): boolean
	if player:GetAttribute(PLAYER_INMATCH_ATTR) == true then
		return false
	end
	-- already queued somewhere
	for _, rt in pairs(runtimes) do
		if rt.playerToStartPart[player] then
			return false
		end
	end

	local gamesFolder = workspace:FindFirstChild(GAMES_FOLDER_NAME)
	if not gamesFolder then
		return false
	end

	local candidatePreferOne: { GameRuntime } = {}
	local candidateEmpty: { GameRuntime } = {}

	for _, gameInstance in ipairs(gamesFolder:GetChildren()) do
		if gameInstance.Name == GAME_MODEL_NAME then
			local rt = runtimes[gameInstance]
			if rt then
				local taken = gameInstance:GetAttribute(GAME_TAKEN_ATTR) == true
				if not taken then
					local q = getQueueCount(rt)
					if q == 1 then
						table.insert(candidatePreferOne, rt)
					elseif q == 0 then
						table.insert(candidateEmpty, rt)
					end
				end
			end
		end
	end

	local function pickRandom(list)
		if #list == 0 then
			return nil
		end
		return list[math.random(1, #list)]
	end

	local rt = pickRandom(candidatePreferOne) or pickRandom(candidateEmpty)
	if not rt then
		return false
	end

	-- find free start part
	local chosenStart: BasePart? = nil
	for _, sp in ipairs(rt.startParts) do
		if sp:GetAttribute(STARTPART_PLAYER_ATTR) ~= true then
			chosenStart = sp
			break
		end
	end
	if not chosenStart then
		return false
	end

	-- Enqueue as if touched
	chosenStart:SetAttribute(STARTPART_PLAYER_ATTR, true)
	rt.startPartToPlayer[chosenStart] = player
	rt.playerToStartPart[player] = chosenStart
	player:SetAttribute(PLAYER_INQUEUE_ATTR, true)

	local waitSpawn = chosenStart:FindFirstChild(SPAWN_WAIT_NAME)
	if waitSpawn and waitSpawn:IsA("BasePart") then
		pivotCharacterToPart(player, waitSpawn)
	end
	freezePlayer(rt, player)

	refreshQueueLabel(rt)
	startCountdownIfReady(rt)
	return true
end

local joinQueueRemote = getOrCreateRemote("JoinQueue")
joinQueueRemote.OnServerEvent:Connect(function(player: Player)
	if not isPlayerValid(player) then
		return
	end
	tryJoinQueue(player)
end)

evMatchClick.OnServerEvent:Connect(function(player: Player, matchId: string, clientTime: number?)
	local id = matchIdByPlayer[player]
	if not id or id ~= matchId then
		return
	end
	local match = matchesById[id]
	if not match or match.ended then
		return
	end
	if not match.canShoot or not match.cueAt then
		return
	end
	if match.winner then
		return
	end

	local opponent = getOpponent(match, player)
	if not opponent then
		return
	end

	match.winner = player
	match.canShoot = false

	-- Use client-measured reaction time so it matches the perceived "SHOOT!" moment.
	-- (Server-measured time includes network latency and feels off.)
	local reactionTime = tonumber(clientTime) or 0
	if reactionTime < 0 then
		reactionTime = 0
	elseif reactionTime > 5 then
		reactionTime = 5
	end
	evMatchRoundResult:FireClient(player, match.id, player.UserId, opponent.UserId, reactionTime)
	evMatchRoundResult:FireClient(opponent, match.id, player.UserId, opponent.UserId, reactionTime)

	-- Quest progress (round winner)
	QuestService.OnRoundWin(player)
	BestTimeService.ReportTime(player, reactionTime)

	-- Record round times (store -1 for no-shot)
	local roundIndex = math.clamp(match.roundNumber, 1, 3)
	match.timesByPlayer[player][roundIndex] = reactionTime
	match.timesByPlayer[opponent][roundIndex] = -1

	-- Loser gets hit
	match.hits[opponent] = (match.hits[opponent] or 0) + 1

	if match.hits[opponent] >= MATCH_HITS_TO_LOSE then
		endMatch(match, player, opponent)
		return
	end

	task.delay(ROUND_BREAK_SECONDS, function()
		if match.ended then
			return
		end
		startRound(match)
	end)
end)

evClaimReward.OnServerEvent:Connect(function(player: Player, matchId: string, mode: string)
	local pending = pendingRewardByPlayer[player]
	if not pending or pending.claimed then
		return
	end
	if pending.matchId ~= matchId then
		return
	end
	if player:GetAttribute(PLAYER_INMATCH_ATTR) == true then
		-- must be post-match
		return
	end

	if mode == "normal" then
		pending.claimed = true
		giveCash(player, pending.amount)
		player:SetAttribute(PLAYER_BOTTOM_UNLOCKED_ATTR, true)
		return
	end

	if mode == "double" then
		-- Client will prompt the purchase; receipt will grant x2
		pendingDoubleRequestMatchIdByPlayer[player] = matchId
		return
	end
end)

MarketplaceService.ProcessReceipt = function(receiptInfo)
	-- Coins bundles devproducts
	do
		local coinAmountByProductId = {
			[3567401315] = 150, -- CoinBundle
			[3567401728] = 500, -- MegaCoinBundle
			[3567401813] = 2750, -- SuperCoinBundle
			[3567401947] = 8000, -- UltraCoin
			[3567402052] = 30000, -- LegendaryCoin
		}
		local amount = coinAmountByProductId[receiptInfo.ProductId]
		if amount then
			local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
			if not player then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			giveCash(player, amount)
			evRobuxPurchase:FireClient(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	-- Double reward product
	if receiptInfo.ProductId == DEVPRODUCT_DOUBLE_ID then
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local pending = pendingRewardByPlayer[player]
		if not pending or pending.claimed then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		local requestedMatchId = pendingDoubleRequestMatchIdByPlayer[player]
		if not requestedMatchId or requestedMatchId ~= pending.matchId then
			-- No active request; don't grant
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		pending.claimed = true
		pendingDoubleRequestMatchIdByPlayer[player] = nil
		giveCash(player, pending.amount * 2)
		player:SetAttribute(PLAYER_BOTTOM_UNLOCKED_ATTR, true)
		evRobuxPurchase:FireClient(player)

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- Quest reroll product
	if receiptInfo.ProductId == QuestService.GetRerollProductId() then
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		QuestService.HandleQuestRerollReceipt(player)
		evRobuxPurchase:FireClient(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

Players.PlayerRemoving:Connect(function(player)
	removePlayerFromAllQueues(player)
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- if they reset while queued, release the slot
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				removePlayerFromAllQueues(player)
			end)
		end
	end)
end)

-- bootstrap existing players (studio live reload)
for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				removePlayerFromAllQueues(player)
			end)
		end
	end)
end

-- bootstrap games
local gamesFolder = workspace:WaitForChild(GAMES_FOLDER_NAME, 30)
if gamesFolder then
	for _, child in ipairs(gamesFolder:GetChildren()) do
		if child.Name == GAME_MODEL_NAME then
			initGame(child)
		end
	end
	gamesFolder.ChildAdded:Connect(function(child)
		if child.Name == GAME_MODEL_NAME then
			initGame(child)
		end
	end)
end

