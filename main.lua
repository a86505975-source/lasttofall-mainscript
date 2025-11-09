-- The Game is inpired by Spleef, This is a ServerScript inside SSS

-- Grab the services we need from Roblox
local Players = game:GetService("Players") -- Handles all player-related stuff
local Debris = game:GetService("Debris") -- Auto-cleans up parts after a delay
math.randomseed(tick()) -- Seed the random generator so we get different results each time

-- This table holds all the settings for the game 
local CONFIG = {
	GRID_SIZE = 10, -- We're making a 10x10 grid of tiles
	TILE_SIZE = 12, -- Each tile is 12 studs wide
	BASE_ROUND_TIME = 60, -- Rounds last 60 seconds max
	BASE_REMOVE_INTERVAL = 2, -- Start by removing tiles every 2 seconds
	MIN_REMOVE_INTERVAL = 0.4, -- Speed up to every 0.4 seconds by the end
	WAIT_BETWEEN_ROUNDS = 6, -- Give everyone a breather between rounds
	LOBBY_WAIT = 10, -- Countdown timer before the round starts
	FALL_Y = -20, -- If you fall below this height, you're out
	SPECTATOR_POS = Vector3.new(0, 80, 0), -- Dead players go up here to watch
	SPAWN_HEIGHT = 12, -- How high off the ground the platform spawns
	TILE_MATERIAL = Enum.Material.SmoothPlastic, -- Makes tiles look clean
	STATS_SHOW_TIME = 6, -- How long to show the end-of-round summary
	WARN_HEIGHT = -15, -- Show a warning when players drop below this
	SCORE_MULTIPLIER_FULL_SURVIVE = 2 -- Bonus multiplier if you survive the whole round
}

-- This keeps track of what's happening in the game right now
local state = {
	roundActive = false, --  Checks if round currently running
	roundNumber = 0, -- Which round
	tiles = {}, -- List of all the tile parts we've created
	theme = {Color3.new(1,1,1), Color3.new(1,1,1)} -- Two colors picked for this round
}

-- Create a folder to hold all our tiles - makes cleanup way easier
local mapFolder = Instance.new("Folder", workspace)
mapFolder.Name = "LTF_MapTiles" -- Give it a clear name

-- Helper function to keep a number between min and max
local function clamp(v, a, b)
	if v < a then return a end -- Uses minimum if too small
	if v > b then return b end -- Uses maximum if too big
	return v -- If its in middle just use it
end

-- Generate a random color using HSV 
local function colorFromHSVRandom()
	-- Random hue, but keep saturation and value in a good range for visibility
	return Color3.fromHSV(math.random(), 0.75 + math.random() * 0.25, 0.8 + math.random() * 0.2)
end

-- Pick two different colors for the round - one for normal tiles, one for warnings
local function chooseTheme()
	return {colorFromHSVRandom(), colorFromHSVRandom()}
end

-- Delete everything in a folder quickly
local function safeClearFolder(folder)
	for _, v in pairs(folder:GetChildren()) do
		v:Destroy() -- Destroy Delets it
	end
end

-- Build the entire platform grid from scratch
local function createGrid()
	safeClearFolder(mapFolder) -- Clear out old tiles first
	state.tiles = {} -- Reset our tile tracking list
	local half = CONFIG.GRID_SIZE / 2 -- Calculate offset to center the grid at (0,0,0)

	-- Loop through each position in the grid
	for x = 1, CONFIG.GRID_SIZE do
		for z = 1, CONFIG.GRID_SIZE do
			-- Create a new part for this tile
			local p = Instance.new("Part")
			p.Size = Vector3.new(CONFIG.TILE_SIZE, 2, CONFIG.TILE_SIZE) -- Make it flat
			p.Anchored = true -- Fixes it since anchored dosent fall
			p.Material = CONFIG.TILE_MATERIAL -- Apply our chosen material
			-- Calculate position to center the grid
			local posX = (x - half - 0.5) * CONFIG.TILE_SIZE
			local posZ = (z - half - 0.5) * CONFIG.TILE_SIZE
			p.Position = Vector3.new(posX, CONFIG.SPAWN_HEIGHT, posZ)
			p.Name = "Tile" -- Simple name
			p.Color = state.theme[1] -- Use the first theme color
			p.Parent = mapFolder -- Add it to our folder
			table.insert(state.tiles, p) -- Remember this tile so we can drop it later
		end
	end
end

-- Make sure each player has their stats set up
local function ensureLeaderstats(player)
	if player:FindFirstChild("leaderstats") then return end -- Skips if already got it, we dont need it
	-- Create the leaderstats folder that shows up on the player list
	local ls = Instance.new("Folder", player)
	ls.Name = "leaderstats"
	-- Add the three stats we're tracking
	Instance.new("IntValue", ls).Name = "Wins"
	Instance.new("IntValue", ls).Name = "RoundsSurvived"
	Instance.new("IntValue", ls).Name = "Score"
end

-- Create the UI that shows round info to players
local function createPlayerGui(player)
	player:WaitForChild("PlayerGui") -- Make sure PlayerGui is loaded
	local existing = player.PlayerGui:FindFirstChild("LTF_Gui")
	if existing then existing:Destroy() end -- Remove old GUI if it exists

	-- Make the main GUI container
	local gui = Instance.new("ScreenGui", player.PlayerGui)
	gui.Name = "LTF_Gui"
	gui.ResetOnSpawn = false -- Keep it even if the player respawns

	-- Create the status text at the top
	local status = Instance.new("TextLabel", gui)
	status.Name = "StatusLabel"
	status.Size = UDim2.new(0,360,0,42) -- Set size in pixels
	status.Position = UDim2.new(0.5,-180,0,8) -- Center it horizontally
	status.BackgroundTransparency = 0.4 -- Slightly see-through
	status.BackgroundColor3 = Color3.new(0,0,0) -- Black background
	status.TextColor3 = Color3.new(1,1,1) -- White text
	status.TextScaled = true -- Auto-size text to fit

	-- Clone the status label for the timer (saves code!)
	local timer = status:Clone()
	timer.Name = "TimerLabel"
	timer.Position = UDim2.new(0.5,-110,0,60) -- Place it below status
	timer.Size = UDim2.new(0,220,0,40)
	timer.Parent = gui

	-- Make a warning label for when players are falling
	local warn = status:Clone()
	warn.Name = "WarnLabel"
	warn.Position = UDim2.new(0.5,-150,0,110) -- Below the timer
	warn.Size = UDim2.new(0,300,0,34)
	warn.TextColor3 = Color3.new(1,0.2,0.2) -- Red text for danger!
	warn.Visible = false -- Hidden until needed
	warn.Parent = gui
end

-- Update the GUI for all players at once
local function updateStatusAll(text, timeLeft)
	for _, p in pairs(Players:GetPlayers()) do -- Loop through everyone
		local gui = p.PlayerGui and p.PlayerGui:FindFirstChild("LTF_Gui")
		if gui then
			local s = gui:FindFirstChild("StatusLabel")
			local t = gui:FindFirstChild("TimerLabel")
			if s then s.Text = text end -- Update status message
			if t and timeLeft ~= nil then 
				t.Text = "Time: " .. math.floor(timeLeft) -- Show remaining time
			end
		end
	end
end

-- Put a player on a random tile
local function teleportToRandomTile(player)
	local tiles = mapFolder:GetChildren() -- Get all current tiles
	if #tiles == 0 then return end -- No tiles? Can't teleport
	local t = tiles[math.random(1,#tiles)] -- Pick a random one
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if hrp then 
		-- Teleport slightly above the tile so they don't get stuck
		hrp.CFrame = CFrame.new(t.Position + Vector3.new(0,4,0)) 
	end
end

-- Send a player up to the spectator area
local function teleportToSpectator(player)
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		player.Character.HumanoidRootPart.CFrame = CFrame.new(CONFIG.SPECTATOR_POS)
	end
end

-- Figure out who's still alive in the round
local function getAlivePlayers()
	local alive = {}
	for _, p in pairs(Players:GetPlayers()) do
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		-- Check if they have health AND haven't fallen too far
		if hum and hrp and hum.Health > 0 and hrp.Position.Y > CONFIG.FALL_Y then
			table.insert(alive, p) -- They're still in it!
		end
	end
	return alive
end

-- Show a warning if a player is getting close to falling out
local function warnIfNearFall(player)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local gui = player.PlayerGui and player.PlayerGui:FindFirstChild("LTF_Gui")
	if not (hrp and gui) then return end -- Make sure both exist
	local warn = gui:FindFirstChild("WarnLabel")
	if hrp.Position.Y < CONFIG.WARN_HEIGHT then
		-- They're getting low - show the danger message!
		warn.Text, warn.Visible = "DANGER: Falling!", true
	else
		warn.Visible = false -- They're safe, hide it
	end
end

-- Make a tile flash red then drop
local function warnAndDropTile(tile)
	if not tile or not tile.Parent then return end -- Make sure tile still exists
	local original = tile.Color -- Remember the original color
	tile.Color = Color3.new(1,0,0) -- Flash it red as a warning
	task.wait(0.35) -- Give players time to react
	if not tile.Parent then return end -- Check again in case it was destroyed
	tile.Color = original -- Change it back briefly
	tile.Anchored = false -- Let physics take over!
	-- Add a downward force with some randomness
	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5,1e5,1e5) -- Strong enough to move it
	bv.Velocity = Vector3.new(math.random(-10,10), -50, math.random(-10,10))
	bv.Parent = tile
	Debris:AddItem(tile, 4) -- Delete it after 4 seconds to keep things clean
end

-- Choose a random tile and drop it
local function pickAndDropRandom()
	local tiles = mapFolder:GetChildren() -- Get current tiles
	if #tiles == 0 then return end -- None left? Nothing to do
	-- Run the drop in a separate thread so it doesn't block the game loop
	spawn(function() 
		warnAndDropTile(tiles[math.random(1,#tiles)]) 
	end)
end

-- Show stats to a player after the round ends
local function showRoundStatsGUI(player, text, duration)
	local gui = player.PlayerGui and player.PlayerGui:FindFirstChild("LTF_Gui")
	if not gui then return end -- No GUI? Can't show stats
	-- Create a new label for the stats
	local s = Instance.new("TextLabel", gui)
	s.Size = UDim2.new(0,420,0,110)
	s.Position = UDim2.new(0.5,-210,0,140) -- Center it
	s.BackgroundTransparency = 0.4
	s.BackgroundColor3 = Color3.new(0,0,0)
	s.TextColor3 = Color3.new(1,1,1)
	s.TextScaled = false
	s.Text = text -- Display the stats message
	Debris:AddItem(s, duration or CONFIG.STATS_SHOW_TIME) -- Auto-remove after time
end

-- Heal everyone to full at the start of a round
local function resetPlayersForRound()
	for _, p in pairs(Players:GetPlayers()) do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum then 
			hum.Health = hum.MaxHealth -- Full heal!
		end
	end
end

-- Calculate how fast tiles should drop based on how far into the round we are
local function computeRemoveInterval(elapsed, total)
	local frac = clamp(elapsed / total, 0, 1) -- Get percentage complete
	-- Start at BASE_REMOVE_INTERVAL, speed up by 65% over the round
	return clamp(CONFIG.BASE_REMOVE_INTERVAL * (1 - frac * 0.65),
		CONFIG.MIN_REMOVE_INTERVAL, CONFIG.BASE_REMOVE_INTERVAL)
end

-- Give bonus points to players who survived the full round
local function awardFullSurviveBonuses(players, base)
	for _, p in pairs(players) do
		local ls = p:FindFirstChild("leaderstats")
		if ls then
			local s, r = ls:FindFirstChild("Score"), ls:FindFirstChild("RoundsSurvived")
			if s then 
				-- Double points for surviving the whole time!
				s.Value += base * CONFIG.SCORE_MULTIPLIER_FULL_SURVIVE 
			end
			if r then 
				r.Value += 1 -- Increment rounds survived
			end
		end
	end
end

-- Give the winner their prize
local function awardRoundWinner(winner)
	local ls = winner and winner:FindFirstChild("leaderstats")
	if not ls then return end -- No stats? Can't award
	local w, s = ls:FindFirstChild("Wins"), ls:FindFirstChild("Score")
	if w then w.Value += 1 end -- Add a win
	if s then s.Value += 50 end -- Bonus points for winning
end

-- Create a text summary of how the round went
local function collectRoundStats(alive, winner)
	local lines = {"Round " .. state.roundNumber .. " Summary:",
		"Tiles remaining: " .. #mapFolder:GetChildren()} -- How many tiles left?
	if winner then
		-- Someone won by being last standing
		table.insert(lines, "Winner: " .. winner.Name)
	elseif #alive > 0 then
		-- Multiple people survived
		local names = {}
		for _, p in pairs(alive) do table.insert(names, p.Name) end
		table.insert(lines, "Survivors: " .. table.concat(names, ", "))
	else
		-- Everyone fell!
		table.insert(lines, "No survivors")
	end
	return table.concat(lines, "\n") -- Join with newlines
end

-- Set up a player when they join or respawn
local function initPlayer(p)
	ensureLeaderstats(p) -- Make sure they have stats
	createPlayerGui(p) -- Give them the UI
end

-- Hook up player joining
Players.PlayerAdded:Connect(function(p)
	initPlayer(p) -- Set them up
	-- Also handle when they respawn
	p.CharacterAdded:Connect(function()
		task.wait(0.6) -- Brief delay for character to fully load
		if state.roundActive then 
			teleportToRandomTile(p) -- Round is active, put them on a tile
		else 
			teleportToSpectator(p) -- Round is over, send them to spectator
		end
	end)
end)

-- Set up any players already in the game
for _, p in pairs(Players:GetPlayers()) do initPlayer(p) end

-- THE BIG ONE - Main game loop that runs forever
local function mainLoop()
	while true do -- Loop forever
		if state.roundActive then
			task.wait(1) -- Round is running, just wait a bit
		else
			-- Time to start a new round!
			state.roundNumber += 1 -- Increment round counter
			state.theme = chooseTheme() -- Pick new colors
			createGrid() -- Build a fresh platform
			-- Send everyone to spectator during setup
			for _, p in pairs(Players:GetPlayers()) do teleportToSpectator(p) end

			-- Countdown before the round starts
			for i = CONFIG.LOBBY_WAIT,1,-1 do
				updateStatusAll("Round " .. state.roundNumber .. " starts in " .. i .. "s", nil)
				task.wait(1) -- Wait one second per count
			end

			resetPlayersForRound() -- Heal everyone
			-- Teleport everyone onto the platform
			for _, p in pairs(Players:GetPlayers()) do teleportToRandomTile(p) end
			state.roundActive = true -- Mark round as active
			local total, elapsed, nextDrop = CONFIG.BASE_ROUND_TIME, 0, 0
			local last = tick() -- Track time
			local winner = nil -- No winner yet

			-- Main round loop
			while elapsed < total do
				local now = tick()
				local dt = now - last -- Delta time since last frame
				last = now
				elapsed += dt -- Add to elapsed time
				nextDrop -= dt -- Count down to next drop
				-- Calculate current removal speed based on progress
				local interval = computeRemoveInterval(elapsed, total)

				if nextDrop <= 0 then
					pickAndDropRandom() -- Drop a tile!
					nextDrop = interval -- Reset the timer
				end

				-- Check everyone's height and show warnings
				for _, p in pairs(Players:GetPlayers()) do warnIfNearFall(p) end
				local alive = getAlivePlayers() -- Who's still in?
				if #alive == 0 then break end -- Everyone died, round over
				-- If only one person left (and there's more than 1 player), they win!
				if #alive == 1 and #Players:GetPlayers() > 1 then
					winner = alive[1]
					awardRoundWinner(winner) -- Give them their prize
					break -- End the round
				end
				-- Update UI with time remaining
				updateStatusAll("Survive!", total - elapsed)
				task.wait(0.25) -- Check every quarter second
			end

			-- Round is over, see who made it
			local survivors = getAlivePlayers()
			-- If multiple people survived the full time, give them bonuses
			if not winner and #survivors > 0 and elapsed >= total then
				awardFullSurviveBonuses(survivors, 25)
			end
			-- Build the summary text
			local text = collectRoundStats(survivors, winner)
			-- Show stats to everyone
			for _, p in pairs(Players:GetPlayers()) do
				showRoundStatsGUI(p, text, CONFIG.STATS_SHOW_TIME)
			end
			updateStatusAll("Round over", 0) -- Update status
			state.roundActive = false -- Mark round as inactive
			-- Clean up any remaining tiles
			for _, t in pairs(mapFolder:GetChildren()) do 
				if t:IsA("BasePart") then t:Destroy() end 
			end
			task.wait(CONFIG.WAIT_BETWEEN_ROUNDS) -- Pause before next round
		end
	end
end

-- Start the game loop in a separate thread so the script doesn't block
spawn(mainLoop)
