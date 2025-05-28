DBSetup = {}

function DBSetup.ensureTablesExist()
    local createTheftVehiclesTable = [[
        CREATE TABLE IF NOT EXISTS `theft_vehicles` (
            `id` INT AUTO_INCREMENT,
            `owner` VARCHAR(255) NOT NULL,
            `carPlate` VARCHAR(255) NOT NULL UNIQUE,
            `fuel` INT NOT NULL,
            PRIMARY KEY (`id`)
        );
    ]]


    MySQL.Async.execute(createTheftVehiclesTable, {}, function(affectedRows)
        if affectedRows > 0 then
            print('Tabela criada ou já existente: theft_vehicles')
        end
    end)
end

return DBSetup

