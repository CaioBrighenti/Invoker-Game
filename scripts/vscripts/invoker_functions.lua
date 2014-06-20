print ( '[[INVOKER_FUNCTIONS]] loaded' )
function InvokerGameGameMode:Restart()
	--Restart challenges
end

function InvokerGameGameMode:GiveItem(hero, item)
	if hero:HasRoomForItem(item, true, true) then
		hero:AddItem(CreateItem(item, hero, nil))
	end
end

function InvokerGameGameMode:HasItem(hero, item)
	return hero:HasItemInInventory(item)
end

function InvokerGameGameMode:SetLevel(hero, level)
	--Only works when setting a higher level. Find solution for making the level lower.
	for i=0, level - (hero:GetLevel() + 1) do
		hero:HeroLevelUp(false)
	end
end