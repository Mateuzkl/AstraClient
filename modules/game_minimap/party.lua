function Party.Update(partyData)
  if not moduleActive or not minimapWidget then return end
  local player = g_game.getLocalPlayer()
  if not player then return end

  minimapWidget:showParty()
end

function Party.Leave(PlayerName)
  if not moduleActive or not minimapWidget then return end
  for rem = 1, #(Party.Members or {}) do
    minimapWidget:removeOldParty(PlayerName)
  end

  for rem = 1, #(Party.Members or {}) do
    if Party.Members[rem].Name == PlayerName then
      table.remove(Party.Members, rem)
    end
  end
end

function Party.Reset()
  if not moduleActive or not minimapWidget then return end
  minimapWidget:resetParty()
end

function Party.UpdateFloor(floor)
  if not moduleActive or not minimapWidget then return end
  minimapWidget:FloorUpdate(floor)
end

function Party.ChangeView()
  if not moduleActive or not minimapWidget then return end
  if Party.ShowNames == false then
    Party.ShowNames = true

    minimapWidget:ViewUpdate("Show")
  else
    Party.ShowNames = false

    minimapWidget:ViewUpdate("Hide")
  end
end
