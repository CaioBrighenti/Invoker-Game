print ('[InvokerGame] invokergame.lua' )

USE_LOBBY=false
THINK_TIME = 0.1

STARTING_GOLD = 500--650
MAX_LEVEL = 50

-- Fill this table up with the required XP per level if you want to change it
XP_PER_LEVEL_TABLE = {}
for i=1,MAX_LEVEL do
  XP_PER_LEVEL_TABLE[i] = i * 100
end

GameMode = nil

if InvokerGameGameMode == nil then
  print ( '[InvokerGame] creating InvokerGame game mode' )
  InvokerGameGameMode = {}
  InvokerGameGameMode.szEntityClassName = "InvokerGame"
  InvokerGameGameMode.szNativeClassName = "dota_base_game_mode"
  InvokerGameGameMode.__index = InvokerGameGameMode
end

function InvokerGameGameMode:new( o )
  print ( '[InvokerGame] InvokerGameGameMode:new' )
  o = o or {}
  setmetatable( o, InvokerGameGameMode )
  return o
end

function InvokerGameGameMode:InitGameMode()
  print('[InvokerGame] Starting to load InvokerGame gamemode...')

  -- Setup rules
  GameRules:SetHeroRespawnEnabled( false )
  GameRules:SetUseUniversalShopMode( true )
  GameRules:SetSameHeroSelectionEnabled( false )
  GameRules:SetHeroSelectionTime( 30.0 )
  GameRules:SetPreGameTime( 30.0)
  GameRules:SetPostGameTime( 60.0 )
  GameRules:SetTreeRegrowTime( 60.0 )
  GameRules:SetUseCustomHeroXPValues ( true )
  GameRules:SetGoldPerTick(0)
  print('[InvokerGame] Rules set')

  InitLogFile( "log/InvokerGame.txt","")

  -- Hooks
  ListenToGameEvent('entity_killed', Dynamic_Wrap(InvokerGameGameMode, 'OnEntityKilled'), self)
  ListenToGameEvent('player_connect_full', Dynamic_Wrap(InvokerGameGameMode, 'AutoAssignPlayer'), self)
  ListenToGameEvent('player_disconnect', Dynamic_Wrap(InvokerGameGameMode, 'CleanupPlayer'), self)
  ListenToGameEvent('dota_item_purchased', Dynamic_Wrap(InvokerGameGameMode, 'ShopReplacement'), self)
  ListenToGameEvent('player_say', Dynamic_Wrap(InvokerGameGameMode, 'PlayerSay'), self)
  ListenToGameEvent('player_connect', Dynamic_Wrap(InvokerGameGameMode, 'PlayerConnect'), self)
  --ListenToGameEvent('player_info', Dynamic_Wrap(InvokerGameGameMode, 'PlayerInfo'), self)
  ListenToGameEvent('dota_player_used_ability', Dynamic_Wrap(InvokerGameGameMode, 'AbilityUsed'), self)
  ListenToGameEvent('npc_spawned', Dynamic_Wrap(InvokerGameGameMode, 'NPCSpawned'), self)

  Convars:RegisterCommand( "command_example", Dynamic_Wrap(InvokerGameGameMode, 'ExampleConsoleCommand'), "A console command example", 0 )
  
  -- Fill server with fake clients
  Convars:RegisterCommand('fake', function()
    -- Check if the server ran it
    if not Convars:GetCommandClient() or DEBUG then
      -- Create fake Players
      SendToServerConsole('dota_create_fake_clients')
        
      self:CreateTimer('assign_fakes', {
        endTime = Time(),
        callback = function(InvokerGame, args)
          for i=0, 9 do
            -- Check if this player is a fake one
            if PlayerResource:IsFakeClient(i) then
              -- Grab player instance
              local ply = PlayerResource:GetPlayer(i)
              -- Make sure we actually found a player instance
              if ply then
                CreateHeroForPlayer('npc_dota_hero_axe', ply)
              end
            end
          end
        end})
    end
  end, 'Connects and assigns fake Players.', 0)

  -- Change random seed
  local timeTxt = string.gsub(string.gsub(GetSystemTime(), ':', ''), '0','')
  math.randomseed(tonumber(timeTxt))

  -- Timers
  self.timers = {}

  -- userID map
  self.vUserNames = {}
  self.vUserIds = {}
  self.vSteamIds = {}
  self.vBots = {}
  self.vBroadcasters = {}

  self.vPlayers = {}
  self.vRadiant = {}
  self.vDire = {}

  -- Active Hero Map
  self.vPlayerHeroData = {}
  print('[InvokerGame] values set')

  print('[InvokerGame] Precaching stuff...')
  PrecacheUnitByName('npc_precache_everything')
  print('[InvokerGame] Done precaching!') 

  print('[InvokerGame] Done loading InvokerGame gamemode!\n\n')
end

function InvokerGameGameMode:CaptureGameMode()
  if GameMode == nil then
    -- Set GameMode parameters
    GameMode = GameRules:GetGameModeEntity()		
    -- Disables recommended items...though I don't think it works
    GameMode:SetRecommendedItemsDisabled( true )
    -- Override the normal camera distance.  Usual is 1134
    GameMode:SetCameraDistanceOverride( 1134.0 )
    -- Set Buyback options
    GameMode:SetCustomBuybackCostEnabled( true )
    GameMode:SetCustomBuybackCooldownEnabled( true )
    GameMode:SetBuybackEnabled( false )
    -- Override the top bar values to show your own settings instead of total deaths
    GameMode:SetTopBarTeamValuesOverride ( true )
    -- Use custom hero level maximum and your own XP per level
    GameMode:SetUseCustomHeroLevels ( false )
    --GameMode:SetCustomHeroMaxLevel ( MAX_LEVEL )
    --GameMode:SetCustomXPRequiredToReachNextLevel( XP_PER_LEVEL_TABLE )
    -- Chage the minimap icon size
    GameRules:SetHeroMinimapIconSize( 300 )

    print( '[InvokerGame] Beginning Think' ) 
    GameMode:SetContextThink("InvokerGameThink", Dynamic_Wrap( InvokerGameGameMode, 'Think' ), 0.1 )
  end 
end

function InvokerGameGameMode:NPCSpawned(keys)
  local spawnedUnit = EntIndexToHScript( keys.entindex )
  if string.find(spawnedUnit:GetUnitName(), "invoker") then
    if not InvokerGameGameMode:HasItem(spawnedUnit, "item_ultimate_scepter") then
      InvokerGameGameMode:GiveItem(spawnedUnit, "item_ultimate_scepter")
      InvokerGameGameMode:SetLevel(spawnedUnit,17)
    end
  end
end

function InvokerGameGameMode:AbilityUsed(keys)
  print('[InvokerGame] AbilityUsed')
  --PrintTable(keys)
end

-- Cleanup a player when they leave
function InvokerGameGameMode:CleanupPlayer(keys)
  print('[InvokerGame] Player Disconnected ' .. tostring(keys.userid))
end

function InvokerGameGameMode:CloseServer()
  -- Just exit
  SendToServerConsole('exit')
end

function InvokerGameGameMode:PlayerConnect(keys)
  print('[InvokerGame] PlayerConnect')
  PrintTable(keys)
  
  -- Fill in the usernames for this userID
  self.vUserNames[keys.userid] = keys.name
  if keys.bot == 1 then
    -- This user is a Bot, so add it to the bots table
    self.vBots[keys.userid] = 1
  end
end

local hook = nil
local attach = 0
local controlPoints = {}
local particleEffect = ""

function InvokerGameGameMode:PlayerSay(keys)
  print ('[InvokerGame] PlayerSay')
  PrintTable(keys)
  
  -- Get the player entity for the user speaking
  local ply = self.vUserIds[keys.userid]
  if ply == nil then
    return
  end
  
  -- Get the player ID for the user speaking
  local plyID = ply:GetPlayerID()
  if not PlayerResource:IsValidPlayer(plyID) then
    return
  end
  
  -- Should have a valid, in-game player saying something at this point
  -- The text the person said
  local text = keys.text
  
  -- Match the text against something
  local find = string.find(text, "-restart")
  if find then
    -- Act on the match
    InvokerGameGameMode:Restart()
  end
  
end

function InvokerGameGameMode:AutoAssignPlayer(keys)
  print ('[InvokerGame] AutoAssignPlayer')
  PrintTable(keys)
  InvokerGameGameMode:CaptureGameMode()
  
  local entIndex = keys.index+1
  -- The Player entity of the joining user
  local ply = EntIndexToHScript(entIndex)
  
  -- The Player ID of the joining player
  local playerID = ply:GetPlayerID()
  
  -- Update the user ID table with this user
  self.vUserIds[keys.userid] = ply
  -- Update the Steam ID table
  self.vSteamIds[PlayerResource:GetSteamAccountID(playerID)] = ply
  
  -- If the player is a broadcaster flag it in the Broadcasters table
  if PlayerResource:IsBroadcaster(playerID) then
    self.vBroadcasters[keys.userid] = 1
    return
  end
  
  -- If this player is a bot (spectator) flag it and continue on
  if self.vBots[keys.userid] ~= nil then
    return
  end

  
  playerID = ply:GetPlayerID()
  -- Figure out if this player is just reconnecting after a disconnect
  if self.vPlayers[playerID] ~= nil then
    self.vUserIds[keys.userid] = ply
    return
  end
  
  -- Always assing Invoker to a connecting player
  if playerID == -1 then
    if #self.vRadiant > #self.vDire then
      ply:SetTeam(DOTA_TEAM_BADGUYS)
      ply:__KeyValueFromInt('teamnumber', DOTA_TEAM_BADGUYS)
      table.insert (self.vDire, ply)
      CreateHeroForPlayer('npc_dota_hero_invoker', ply)
    else
      ply:SetTeam(DOTA_TEAM_GOODGUYS)
      ply:__KeyValueFromInt('teamnumber', DOTA_TEAM_GOODGUYS)
      table.insert (self.vRadiant, ply)
      CreateHeroForPlayer('npc_dota_hero_invoker', ply)
    end
    playerID = ply:GetPlayerID()
  end
end

function InvokerGameGameMode:LoopOverPlayers(callback)
  for k, v in pairs(self.vPlayers) do
    -- Validate the player
    if IsValidEntity(v.hero) then
      -- Run the callback
      if callback(v, v.hero:GetPlayerID()) then
        break
      end
    end
  end
end

function InvokerGameGameMode:ShopReplacement( keys )
  print ( '[InvokerGame] ShopReplacement' )
  PrintTable(keys)

  -- The playerID of the hero who is buying something
  local plyID = keys.PlayerID
  if not plyID then return end

  -- The name of the item purchased
  local itemName = keys.itemname 
  
  -- The cost of the item purchased
  local itemcost = keys.itemcost
  
end

function InvokerGameGameMode:getItemByName( hero, name )
  -- Find item by slot
  for i=0,11 do
    local item = hero:GetItemInSlot( i )
    if item ~= nil then
      local lname = item:GetAbilityName()
      if lname == name then
        return item
      end
    end
  end

  return nil
end

function InvokerGameGameMode:Think()
  -- If the game's over, it's over.
  if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
    return
  end

  -- Track game time, since the dt passed in to think is actually wall-clock time not simulation time.
  local now = GameRules:GetGameTime()
  --print("now: " .. now)
  if InvokerGameGameMode.t0 == nil then
    InvokerGameGameMode.t0 = now
  end
  local dt = now - InvokerGameGameMode.t0
  InvokerGameGameMode.t0 = now

  --InvokerGameGameMode:thinkState( dt )

  -- Process timers
  for k,v in pairs(InvokerGameGameMode.timers) do
    local bUseGameTime = false
    if v.useGameTime and v.useGameTime == true then
      bUseGameTime = true;
    end
    -- Check if the timer has finished
    if (bUseGameTime and GameRules:GetGameTime() > v.endTime) or (not bUseGameTime and Time() > v.endTime) then
      -- Remove from timers list
      InvokerGameGameMode.timers[k] = nil

      -- Run the callback
      local status, nextCall = pcall(v.callback, InvokerGameGameMode, v)

      -- Make sure it worked
      if status then
        -- Check if it needs to loop
        if nextCall then
          -- Change it's end time
          v.endTime = nextCall
          InvokerGameGameMode.timers[k] = v
        end

      else
        -- Nope, handle the error
        InvokerGameGameMode:HandleEventError('Timer', k, nextCall)
      end
    end
  end

  return THINK_TIME
end

function InvokerGameGameMode:HandleEventError(name, event, err)
  -- This gets fired when an event throws an error

  -- Log to console
  print(err)

  -- Ensure we have data
  name = tostring(name or 'unknown')
  event = tostring(event or 'unknown')
  err = tostring(err or 'unknown')

  -- Tell everyone there was an error
  Say(nil, name .. ' threw an error on event '..event, false)
  Say(nil, err, false)

  -- Prevent loop arounds
  if not self.errorHandled then
    -- Store that we handled an error
    self.errorHandled = true
  end
end

function InvokerGameGameMode:CreateTimer(name, args)
  --[[
  args: {
  endTime = Time you want this timer to end: Time() + 30 (for 30 seconds from now),
  useGameTime = use Game Time instead of Time()
  callback = function(frota, args) to run when this timer expires,
  text = text to display to clients,
  send = set this to true if you want clients to get this,
  persist = bool: Should we keep this timer even if the match ends?
  }

  If you want your timer to loop, simply return the time of the next callback inside of your callback, for example:

  callback = function()
  return Time() + 30 -- Will fire again in 30 seconds
  end
  ]]

  if not args.endTime or not args.callback then
    print("Invalid timer created: "..name)
    return
  end

  -- Store the timer
  self.timers[name] = args
end

function InvokerGameGameMode:RemoveTimer(name)
  -- Remove this timer
  self.timers[name] = nil
end

function InvokerGameGameMode:RemoveTimers(killAll)
  local timers = {}

  -- If we shouldn't kill all timers
  if not killAll then
    -- Loop over all timers
    for k,v in pairs(self.timers) do
      -- Check if it is persistant
      if v.persist then
        -- Add it to our new timer list
        timers[k] = v
      end
    end
  end

  -- Store the new batch of timers
  self.timers = timers
end

function InvokerGameGameMode:ExampleConsoleCommand()
  print( '******* Example Console Command ***************' )
  local cmdPlayer = Convars:GetCommandClient()
  if cmdPlayer then
    local playerID = cmdPlayer:GetPlayerID()
    if playerID ~= nil and playerID ~= -1 then
      -- Do something here for the player who called this command
    end
  end

  print( '*********************************************' )
end

function InvokerGameGameMode:OnEntityKilled( keys )
  print( '[InvokerGame] OnEntityKilled Called' )
  PrintTable( keys )
  
  -- The Unit that was Killed
  local killedUnit = EntIndexToHScript( keys.entindex_killed )
  -- The Killing entity
  local killerEntity = nil

  if keys.entindex_attacker ~= nil then
    killerEntity = EntIndexToHScript( keys.entindex_attacker )
  end

  -- Put code here to handle when an entity gets killed
end

-- A helper function for dealing damage from a source unit to a target unit.  Damage dealt is pure damage
function dealDamage(source, target, damage)
  local unit = nil
  if damage == 0 then
    return
  end
  
  if source ~= nil then
    unit = CreateUnitByName("npc_dummy_unit", target:GetAbsOrigin(), false, source, source, source:GetTeamNumber())
  else
    unit = CreateUnitByName("npc_dummy_unit", target:GetAbsOrigin(), false, nil, nil, DOTA_TEAM_NOTEAM)
  end
  unit:AddNewModifier(unit, nil, "modifier_invulnerable", {})
  unit:AddNewModifier(unit, nil, "modifier_phased", {})
  local dummy = unit:FindAbilityByName("reflex_dummy_unit")
  dummy:SetLevel(1)
  
  local abilIndex = math.floor((damage-1) / 20) + 1
  local abilLevel = math.floor(((damage-1) % 20)) + 1
  if abilIndex > 100 then
    abilIndex = 100
    abilLevel = 20
  end
  
  local abilityName = "modifier_damage_applier" .. abilIndex
  unit:AddAbility(abilityName)
  ability = unit:FindAbilityByName( abilityName )
  ability:SetLevel(abilLevel)
  
  local diff = nil
  
  local hp = target:GetHealth()
  
  diff = target:GetAbsOrigin() - unit:GetAbsOrigin()
  diff.z = 0
  unit:SetForwardVector(diff:Normalized())
  unit:CastAbilityOnTarget(target, ability, 0 )
  
  InvokerGameGameMode:CreateTimer(DoUniqueString("damage"), {
    endTime = GameRules:GetGameTime() + 0.3,
    useGameTime = true,
    callback = function(InvokerGame, args)
      unit:Destroy()
      if target:GetHealth() == hp and hp ~= 0 and damage ~= 0 then
        print ("[InvokerGame] WARNING: dealDamage did no damage: " .. hp)
        dealDamage(source, target, damage)
      end
    end
  })
end