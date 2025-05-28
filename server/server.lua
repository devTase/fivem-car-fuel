-- Configuration
local Config = {
    defaultConsumption = 4,  -- Default fuel consumption if not specified
    cacheTTL = 3600,         -- Cache time-to-live in seconds (1 hour)
    defaultFuelRange = {20, 80} -- Min/max range for random fuel values
}

-- Caching system
local VehicleCache = {
    consumption = {}, -- Model name -> consumption rate
    ownedVehicles = {}, -- Plate -> {fuel, consumption, timestamp}
    theftVehicles = {}, -- Plate -> {fuel, timestamp}
    timestamps = {} -- Track last access for cache cleanup
}

-- Helper functions
local function logError(message, data)
    if data then
        print("^1[ERROR] " .. message .. "^7", json.encode(data))
    else
        print("^1[ERROR] " .. message .. "^7")
    end
end

local function generateRandomFuel()
    return math.random(Config.defaultFuelRange[1], Config.defaultFuelRange[2])
end

-- Cache management functions
local function getCachedConsumption(model)
    if VehicleCache.consumption[model] and 
       (VehicleCache.timestamps[model] + Config.cacheTTL) > os.time() then
        VehicleCache.timestamps[model] = os.time() -- Update timestamp on access
        return VehicleCache.consumption[model]
    end
    return nil
end

local function setCachedConsumption(model, consumption)
    VehicleCache.consumption[model] = consumption
    VehicleCache.timestamps[model] = os.time()
end

local function getCachedOwnedVehicle(plate)
    if VehicleCache.ownedVehicles[plate] and 
       (VehicleCache.ownedVehicles[plate].timestamp + Config.cacheTTL) > os.time() then
        VehicleCache.ownedVehicles[plate].timestamp = os.time() -- Update timestamp
        return VehicleCache.ownedVehicles[plate]
    end
    return nil
end

local function setCachedOwnedVehicle(plate, data)
    VehicleCache.ownedVehicles[plate] = data
    VehicleCache.ownedVehicles[plate].timestamp = os.time()
end

local function getCachedTheftVehicle(plate)
    if VehicleCache.theftVehicles[plate] and 
       (VehicleCache.theftVehicles[plate].timestamp + Config.cacheTTL) > os.time() then
        VehicleCache.theftVehicles[plate].timestamp = os.time() -- Update timestamp
        return VehicleCache.theftVehicles[plate]
    end
    return nil
end

local function setCachedTheftVehicle(plate, data)
    VehicleCache.theftVehicles[plate] = data
    VehicleCache.theftVehicles[plate].timestamp = os.time()
end

-- Async wrapper for database operations
local function fetchOwnedVehicle(plate)
    return promise.new(function(resolve, reject)
        MySQL.Async.fetchAll('SELECT fuel, consumos FROM owned_vehicles WHERE plate = @plate', 
            {['@plate'] = plate}, 
            function(result)
                if result and result[1] then
                    resolve(result[1])
                else
                    resolve(nil)
                end
            end
        )
    end)
end

local function fetchTheftVehicle(plate)
    return promise.new(function(resolve, reject)
        MySQL.Async.fetchAll('SELECT fuel FROM theft_vehicles WHERE carPlate = @carPlate', 
            {['@carPlate'] = plate}, 
            function(result)
                if result and result[1] then
                    resolve(result[1].fuel)
                else
                    resolve(nil)
                end
            end
        )
    end)
end

local function fetchVehicleConsumption(model)
    return promise.new(function(resolve, reject)
        local cached = getCachedConsumption(model)
        if cached then
            resolve(cached)
            return
        end
        
        MySQL.Async.fetchAll('SELECT consumos FROM vehicles WHERE model = @model', 
            {['@model'] = model}, 
            function(result)
                if result and result[1] then
                    setCachedConsumption(model, result[1].consumos)
                    resolve(result[1].consumos)
                else
                    setCachedConsumption(model, Config.defaultConsumption)
                    resolve(nil)
                end
            end
        )
    end)
end

-- Main server callback for vehicle info
ESX.RegisterServerCallback('CarFuel:GetInfoSV', function(source, cb, carPlate, carModel, vehicle)
    if not carPlate or not carModel then
        logError("Invalid parameters in CarFuel:GetInfoSV", {plate = carPlate, model = carModel})
        cb(Config.defaultFuelRange[2], Config.defaultConsumption, false)
        return
    end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        logError("Player not found", {source = source})
        cb(Config.defaultFuelRange[2], Config.defaultConsumption, false)
        return
    end
    
    -- Check cache first for owned vehicle
    local cachedOwned = getCachedOwnedVehicle(carPlate)
    if cachedOwned then
        cb(cachedOwned.fuel, cachedOwned.consumption, true)
        return
    end
    
    -- Then check database asynchronously
    Citizen.CreateThread(function()
        local ownedVehicle = fetchOwnedVehicle(carPlate):wait()
        
        if ownedVehicle then
            -- It's an owned vehicle
            setCachedOwnedVehicle(carPlate, {
                fuel = ownedVehicle.fuel,
                consumption = ownedVehicle.consumos
            })
            cb(ownedVehicle.fuel, ownedVehicle.consumos, true)
            return
        end
        
        -- Not an owned vehicle, check theft vehicles
        local cachedTheft = getCachedTheftVehicle(carPlate)
        local theftFuel = nil
        local randomFuel = nil
        
        if cachedTheft then
            theftFuel = cachedTheft.fuel
        else
            theftFuel = fetchTheftVehicle(carPlate):wait()
            if not theftFuel then
                randomFuel = generateRandomFuel()
            end
        end
        
        -- Get consumption for this model
        local consumption = fetchVehicleConsumption(carModel):wait() or Config.defaultConsumption
        
        -- Prepare response
        local finalFuel = theftFuel or randomFuel
        
        -- Cache the results
        if theftFuel then
            setCachedTheftVehicle(carPlate, {fuel = theftFuel})
        end
        
        -- Save new theft vehicle if needed
        if randomFuel then
            saveTheftCarDetails(xPlayer.identifier, carPlate, randomFuel)
            TriggerClientEvent('CreateVehicle:newvehicleCL', source, vehicle)
        end
        
        -- Return results to client
        cb(finalFuel, consumption, false)
    end)
end)

-- Save fuel for owned vehicles
RegisterNetEvent('CarFuel:SaveOwnCarFuel', function(fuel, plate)
    local source = source
    if not fuel or not plate then
        logError("Invalid parameters in CarFuel:SaveOwnCarFuel", {source = source, fuel = fuel, plate = plate})
        return
    end
    
    -- Update cache
    local cached = getCachedOwnedVehicle(plate)
    if cached then
        cached.fuel = fuel
        setCachedOwnedVehicle(plate, cached)
    end
    
    -- Update database
    MySQL.Async.execute('UPDATE owned_vehicles SET fuel = @fuel WHERE plate = @plate', 
        {['@fuel'] = fuel, ['@plate'] = plate},
        function(rowsChanged)
            if rowsChanged == 0 then
                logError("Failed to update owned vehicle fuel", {plate = plate, fuel = fuel})
            end
        end
    )
end)

-- Save theft car details
function saveTheftCarDetails(identifier, carPlate, fuel)
    if not identifier or not carPlate or not fuel then
        logError("Invalid parameters in saveTheftCarDetails", {identifier = identifier, plate = carPlate, fuel = fuel})
        return
    end
    
    -- Update cache
    setCachedTheftVehicle(carPlate, {fuel = fuel})
    
    -- Update database
    MySQL.insert('INSERT INTO theft_vehicles(owner, carPlate, fuel) VALUES(?, ?, ?)', 
        {identifier, carPlate, fuel},
        function(id)
            if not id then
                logError("Failed to insert theft vehicle", {plate = carPlate, fuel = fuel})
            end
        end
    )
end

-- Save fuel for theft vehicles
RegisterNetEvent('CarFuel:SaveTheftCarFuel', function(fuel, plate)
    local source = source
    if not fuel or not plate then
        logError("Invalid parameters in CarFuel:SaveTheftCarFuel", {source = source, fuel = fuel, plate = plate})
        return
    end
    
    -- Update cache
    local cached = getCachedTheftVehicle(plate)
    if cached then
        cached.fuel = fuel
        setCachedTheftVehicle(plate, cached)
    end
    
    -- Update database
    MySQL.Async.execute('UPDATE theft_vehicles SET fuel = @fuel WHERE carPlate = @carPlate', 
        {['@fuel'] = fuel, ['@carPlate'] = plate},
        function(rowsChanged)
            if rowsChanged == 0 then
                logError("Failed to update theft vehicle fuel", {plate = plate, fuel = fuel})
            end
        end
    )
end)

-- Cleanup cache periodically
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000) -- Check every minute
        
        local currentTime = os.time()
        local cacheCleanupCount = 0
        
        -- Clean up consumption cache
        for model, timestamp in pairs(VehicleCache.timestamps) do
            if (timestamp + Config.cacheTTL) < currentTime then
                VehicleCache.consumption[model] = nil
                VehicleCache.timestamps[model] = nil
                cacheCleanupCount = cacheCleanupCount + 1
            end
        end
        
        -- Clean up owned vehicles cache
        for plate, data in pairs(VehicleCache.ownedVehicles) do
            if (data.timestamp + Config.cacheTTL) < currentTime then
                VehicleCache.ownedVehicles[plate] = nil
                cacheCleanupCount = cacheCleanupCount + 1
            end
        end
        
        -- Clean up theft vehicles cache
        for plate, data in pairs(VehicleCache.theftVehicles) do
            if (data.timestamp + Config.cacheTTL) < currentTime then
                VehicleCache.theftVehicles[plate] = nil
                cacheCleanupCount = cacheCleanupCount + 1
            end
        end
        
        if cacheCleanupCount > 0 then
            print("^3[CarFuel]^7 Cleaned up " .. cacheCleanupCount .. " cached entries")
        end
    end
end)

-- Resource stop cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    print("^3[CarFuel]^7 Resource stopping, clearing cache")
    
    -- Clear caches
    VehicleCache.consumption = {}
    VehicleCache.ownedVehicles = {}
    VehicleCache.theftVehicles = {}
    VehicleCache.timestamps = {}
end)
