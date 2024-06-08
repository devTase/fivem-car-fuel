DBSetup.ensureTablesExist()

local xPlayer = nil
local defaultConsumos = 4
local exactConsumos = nil
local carFuel = nil
local isRunning = false
local randomFuel = 0

ESX.RegisterServerCallback('CarFuel:GetInfoSV', function(source, cb, carPlate, carModel, vehicle)
    
    randomFuel = nil
    carFuel = nil
    xPlayer = ESX.GetPlayerFromId(source)

    MySQL.Async.fetchAll('SELECT fuel, consumos FROM owned_vehicles WHERE plate = @plate', { ['@plate'] = carPlate },
        function(result)
            if result and result[1] ~= nil then
                cb(result[1].fuel, result[1].consumos, true)
            else
                getTheftCarFuel(carPlate)
                while isRunning do
                    Wait(0)
                end

                getCarConsumptionsFromGlobalList(carModel)
                while isRunning do
                    Wait(0)
                end

                if carFuel ~= nil and exactConsumos ~= nil then
                    cb(carFuel, exactConsumos, false)
                elseif carFuel ~= nil and exactConsumos == nil then
                    cb(carFuel, defaultConsumos, false)
                    TriggerClientEvent('CreateVehicle:newvehicleCL', source, vehicle)
                elseif carFuel == nil and exactConsumos ~= nil then
                    cb(randomFuel, exactConsumos)
                    saveTheftCarDetails(carPlate, carFuel, false)
                elseif carFuel == nil and exactConsumos == nil then
                    cb(randomFuel, defaultConsumos)
                    saveTheftCarDetails(carPlate, carFuel, false)
                    TriggerClientEvent('CreateVehicle:newvehicleCL', source, vehicle)
                end
            end
        end)
end)

RegisterNetEvent('CarFuel:SaveOwnCarFuel', function(fuel, plate)
    MySQL.Async.fetchAll('UPDATE owned_vehicles SET fuel = @fuel WHERE plate = @plate',
        { ['@fuel'] = fuel, ['@plate'] = plate })
end)

function getTheftCarFuel(carPlate)
    isRunning = true
    MySQL.Async.fetchAll('SELECT fuel FROM theft_vehicles WHERE carPlate = @carPlate', { ['@carPlate'] = carPlate },
        function(result)
            if result and result[1] ~= nil then
                carFuel = result[1].fuel
            else
                randomFuel = math.random(1, 100)
            end
            isRunning = false
        end)
end

function saveTheftCarDetails(carPlate, fuel)
    MySQL.insert('INSERT INTO theft_vehicles(owner, carPlate, fuel) VALUES(?, ?, ?)',
        { xPlayer.identifier, carPlate, fuel })
end

RegisterNetEvent('CarFuel:SaveTheftCarFuel', function(fuel, plate)
    MySQL.Async.fetchAll('UPDATE theft_vehicles SET fuel = @fuel WHERE carPlate = @carPlate',
        { ['@fuel'] = fuel, ['@carPlate'] = plate })
end)

function getCarConsumptionsFromGlobalList(carModel)
    isRunning = true
    MySQL.Async.fetchAll('SELECT consumos FROM vehicles WHERE model = @model', { ['@model'] = carModel },
        function(result)
            if result and result[1] ~= nil then
                exactConsumos = result[1].consumos
            else
                exactConsumos = nil
            end
            isRunning = false
        end)
end
