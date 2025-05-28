-- State variables with better naming
local currentFuel = 100
local currentConsumption = 7
local isPlayerOwner = false
local lastPosition = nil
local distanceTraveled = 0
local needFuelCalculation = true
local needFuelSaving = false
local currentVehicle = nil
local currentPlate = nil
local updateInterval = 1000 -- ms, adjust based on server performance needs
local fuelUpdateInterval = 200 -- ms, for smoother fuel updates

-- Resource management
local activeTimers = {}

-- Helper function to safely get vehicle data
local function safeGetVehicleData()
    local playerPed = PlayerPedId()
    if not playerPed then return nil end
    
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if not vehicle or vehicle == 0 then return nil end
    
    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate or plate == "" then return nil end
    
    return {
        ped = playerPed,
        vehicle = vehicle,
        plate = plate,
        isEngineRunning = GetIsVehicleEngineRunning(vehicle) == 1,
        coords = GetEntityCoords(playerPed)
    }
end

-- Calculate and update fuel consumption based on distance
local function updateFuelConsumption()
    local data = safeGetVehicleData()
    if not data or not data.isEngineRunning then 
        if currentVehicle and needFuelSaving and currentPlate then
            -- Save fuel state when exiting vehicle
            if isPlayerOwner then
                TriggerServerEvent('CarFuel:SaveOwnCarFuel', currentFuel, currentPlate)
            else
                TriggerServerEvent('CarFuel:SaveTheftCarFuel', currentFuel, currentPlate)
            end
            needFuelSaving = false
        end
        
        -- Reset state for next vehicle entry
        needFuelCalculation = true
        currentVehicle = nil
        currentPlate = nil
        return 
    end
    
    -- Update vehicle references
    currentVehicle = data.vehicle
    currentPlate = data.plate
    
    -- Calculate fuel on first entry to vehicle
    if needFuelCalculation then
        local props = ESX.Game.GetVehicleProperties(data.vehicle)
        if not props or not props.model then return end
        
        local carModel = GetDisplayNameFromVehicleModel(props.model):lower()
        
        -- Use promise-like pattern instead of blocking wait
        ESX.TriggerServerCallback('CarFuel:GetInfoSV', function(fuel, consumption, isOwner)
            currentFuel = fuel
            currentConsumption = consumption
            isPlayerOwner = isOwner
            lastPosition = GetEntityCoords(data.ped)
            needFuelCalculation = false
        end, data.plate, carModel, data.vehicle)
        
        return -- Wait for callback to complete
    end
    
    -- Update position and calculate distance
    local currentPosition = data.coords
    if lastPosition then
        local distance = #(currentPosition - lastPosition)
        distanceTraveled = distanceTraveled + distance
        
        -- Update fuel based on distance traveled
        local fuelConsumption = (distanceTraveled/100) * (currentConsumption/10)
        currentFuel = math.max(0, currentFuel - fuelConsumption)
        
        -- Apply fuel to vehicle
        SetVehicleFuelLevel(data.vehicle, currentFuel)
        ESX.Game.SetVehicleProperties(data.vehicle, { fuelLevel = currentFuel })
        
        -- Reset distance for next calculation
        distanceTraveled = 0
        needFuelSaving = true
    end
    
    -- Update last position for next cycle
    lastPosition = currentPosition
end

-- Display fuel and consumption info
local function updateDisplay()
    local data = safeGetVehicleData()
    if not data or not data.isEngineRunning then return end
    
    -- Only show display when in a vehicle with engine on
    showMenuWithFuel(currentFuel)
    showMenuWithConsumos(currentConsumption)
end

-- Main timer threads with different intervals for different tasks
Citizen.CreateThread(function()
    -- Main processing loop
    local timerId = "fuel_consumption"
    activeTimers[timerId] = true
    
    while activeTimers[timerId] do
        updateFuelConsumption()
        Citizen.Wait(updateInterval)
    end
end)

Citizen.CreateThread(function()
    -- UI update loop (more frequent for smoother display)
    local timerId = "fuel_display"
    activeTimers[timerId] = true
    
    while activeTimers[timerId] do
        updateDisplay()
        Citizen.Wait(fuelUpdateInterval)
    end
end)

-- Cleanup when resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    -- Stop all timers
    for k in pairs(activeTimers) do
        activeTimers[k] = false
    end
    
    -- Save fuel state if in vehicle
    if currentVehicle and currentPlate and needFuelSaving then
        if isPlayerOwner then
            TriggerServerEvent('CarFuel:SaveOwnCarFuel', currentFuel, currentPlate)
        else
            TriggerServerEvent('CarFuel:SaveTheftCarFuel', currentFuel, currentPlate)
        end
    end
end)

-- Improved display functions with safety checks
function showMenuWithFuel(fuelAmount)
    if not fuelAmount then return end
    
    -- Ensure fuel is within valid range
    local fuel = math.max(0, math.min(100, fuelAmount))
    
    SetTextScale(0.6, 0.6)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    SetTextCentre(false)
    AddTextComponentString('Fuel: ' .. string.format("%.0f", fuel) .. "%")
    DrawText(0.825, 0.825)    
end

function showMenuWithConsumos(consumos)
    if not consumos then return end
    
    -- Ensure consumption is a valid number
    local consumption = math.max(0, consumos)
    
    SetTextScale(0.6, 0.6)
    SetTextFont(4)
    SetTextColour(255, 255, 255, 255)
    SetTextEntry("STRING")
    SetTextCentre(false)
    AddTextComponentString('Consumos: ' .. string.format("%.0f", consumption) .. 'lt/100km')
    DrawText(0.825, 0.850)    
end
