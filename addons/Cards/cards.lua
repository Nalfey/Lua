--[[
Copyright © 2013-2015, Giuliano Riccio
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.
* Neither the name of findAll nor the
names of its contributors may be used to endorse or promote products
derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL Giuliano Riccio BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

_addon.name    = 'Cards'
_addon.author  = 'Nalfey'
_addon.version = '1.00'
_addon.commands = {'cards'}

require('chat')
require('lists')
require('logger')
require('sets')
require('tables')
require('strings')
require('pack')

file  = require('files')
slips = require('slips')
config = require('config')
texts = require('texts')
res = require('resources')

defaults = {}
defaults.Track = ''
defaults.Tracker = {}
defaults.KeyItemDisplay = true

settings = config.load(defaults)

tracker = texts.new(settings.Track, settings.Tracker, settings)

do
    config.register(settings, function(settings)
        tracker:text(settings.Track)
        tracker:visible(settings.Track ~= '' and windower.ffxi.get_info().logged_in)
    end)

    local bag_ids = res.bags:rekey('english'):key_map(string.lower):map(table.get-{'id'})

    local variable_cache = S{}
    tracker:register_event('reload', function()
        for variable in tracker:it() do
            local bag_name, search = variable:match('(.*):(.*)')

            local bag = bag_name == 'all' and 'all' or bag_ids[bag_name:lower()]
            if not bag and bag_name ~= 'all' then
                warning('Unknown bag: %s':format(bag_name))
            else
                if not S{'$freespace', '$usedspace', '$maxspace'}:contains(search:lower()) then
                    local items = S(res.items:name(windower.wc_match-{search})) + S(res.items:name_log(windower.wc_match-{search}))
                    if items:empty() then
                        warning('No items matching "%s" found.':format(search))
                    else
                        variable_cache:add({
                            name = variable,
                            bag = bag,
                            type = 'item',
                            ids = items:map(table.get-{'id'}),
                            search = search,
                        })
                    end
                else
                    variable_cache:add({
                        name = variable,
                        bag = bag,
                        type = 'info',
                        search = search,
                    })
                end
            end
        end
    end)

    do
        local update = T{}

        local search_bag = function(bag, ids)
            return bag:filter(function(item)
                return type(item) == 'table' and ids:contains(item.id)
            end):reduce(function(acc, item)
                return type(item) == 'table' and item.count + acc or acc
            end, 0)
        end

        local last_check = 0

        windower.register_event('prerender', function()
            if os.clock() - last_check < 0.25 then
                return
            end
            last_check = os.clock()

            local items = T{}
            for variable in variable_cache:it() do
                if variable.type == 'info' then
                    local info
                    if variable.bag == 'all' then
                        info = {
                            max = 0,
                            count = 0
                        }
                        for bag_info in T(windower.ffxi.get_bag_info()):it() do
                            info.max = info.max + bag_info.max
                            info.count = info.count + bag_info.count
                        end
                    else
                        info = windower.ffxi.get_bag_info(variable.bag)
                    end

                    update[variable.name] =
                        variable.search == '$freespace' and (info.max - info.count)
                        or variable.search == '$usedspace' and info.count
                        or variable.search == '$maxspace' and info.max
                        or nil
                elseif variable.type == 'item' then
                    if variable.bag == 'all' then
                        for id in bag_ids:it() do
                            if not items[id] then
                                items[id] = T(windower.ffxi.get_items(id))
                            end
                        end
                    else
                        if not items[variable.bag] then
                            items[variable.bag] = T(windower.ffxi.get_items(variable.bag))
                        end
                    end

                    update[variable.name] = variable.bag ~= 'all' and search_bag(items[variable.bag], variable.ids) or items:reduce(function(acc, bag)
                        return acc + search_bag(bag, variable.ids)
                    end, 0)
                end
            end

            if not update:empty() then
                tracker:update(update)
            end
        end)
    end
end
string.query_escape = function(str)
    return (str:gsub('[()%.%+?-]', '%%%1'))
end

zone_search            = windower.ffxi.get_info().logged_in
first_pass             = true
item_names             = T{}
key_item_names         = T{}
global_storages        = T{}
storages_path          = windower.file_exists(windower.addon_path..'..\\findAll\\data') and 
    windower.addon_path..'..\\findAll\\data\\' or 
    windower.addon_path..'data\\'
storages_order_tokens  = L{'temporary', 'inventory', 'wardrobe', 'wardrobe 2', 'wardrobe 3', 'wardrobe 4', 'wardrobe 5', 'wardrobe 6', 'wardrobe 7', 'wardrobe 8', 'safe', 'safe 2', 'storage', 'locker', 'satchel', 'sack', 'case'}
-- This is to maintain sorting order. I don't know why this was done, but omitting this will sort the bags arbitrarily, which (I guess) was not intended
storages_order         = S(res.bags:map(string.gsub-{' ', ''} .. string.lower .. table.get-{'english'})):sort(function(name1, name2)
    local index1 = storages_order_tokens:find(name1)
    local index2 = storages_order_tokens:find(name2)

    if not index1 and not index2 then
        return name1 < name2
    end

    if not index1 then
        return false
    end

    if not index2 then
        return true
    end

    return index1 < index2
end)
local storage_slips_order = slips.storages:map(function(id)
    return 'slip ' .. res.items[id].english:lower():match('^storage slip (.*)$')
end)
merged_storages_orders = storages_order + storage_slips_order + L{'key items'}

function search(query, export)    
    local success, err = pcall(update_global_storage)
    if not success then
        error('Failed to update global storage: ' .. err)
        return
    end

    if not update() then
        error('Failed to update current character storage')
        return
    end

    if query:length() == 0 then
        return
    end

    local character_set    = S{}
    local character_filter = S{}
    local terms            = ''

    for _, query_element in ipairs(query) do
        local char = query_element:match('^([:!]%a+)$')
        if char then
            if char:sub(1, 1) == '!' then
                character_filter:add(char:sub(2):lower():gsub("^%l", string.upper))
            else
                character_set:add(char:sub(2):lower():gsub("^%l", string.upper))
            end
        else
            terms = query_element
        end
    end

    if character_set:length() == 0 and terms == '' then
        return
    end

    local new_item_ids = S{}
    local new_key_item_ids = S{}

    for character_name, storages in pairs(global_storages) do
        for storage_name, storage in pairs(storages) do
            if storage_name == 'key items' then
                for id, quantity in pairs(storage) do
                    id = tostring(id)

                    if key_item_names[id] == nil then
                        new_key_item_ids:add(id)
                    end
                end
            elseif storage_name ~= 'gil' then
                for id, quantity in pairs(storage) do
                    id = tostring(id)

                    if item_names[id] == nil then
                        new_item_ids:add(id)
                    end
                end
            end
            coroutine.yield()
        end
    end

    for id,_ in pairs(new_item_ids) do
        local item = res.items[tonumber(id)]
	    if item then
            item_names[id] = {
                ['name'] = item.name,
                ['long_name'] = item.name_log
            }
        end
    end

    for id,_ in pairs(new_key_item_ids) do
        local key_item = res.key_items[tonumber(id)]
	    if key_item then
            key_item_names[id] = {
                ['name'] = key_item.name,
                ['long_name'] = key_item.name
            }
        end
    end
    

    local results_items     = S{}
    local results_key_items = S{}
    local terms_pattern     = ''

    if terms ~= '' then
        terms_pattern = terms:query_escape():gsub('%a', function(char) return string.format("[%s%s]", char:lower(), char:upper()) end)
    end

    for id, names in pairs(item_names) do
        if terms_pattern == '' or item_names[id].name:find(terms_pattern)
            or item_names[id].long_name:find(terms_pattern)
        then
            results_items:add(id)
        end
    end
    
    if settings.KeyItemDisplay then
          for id in pairs(key_item_names) do
               if terms_pattern == '' or key_item_names[id].name:match(terms_pattern) then
                    results_key_items:add(id)
               end
          end
     end

    log('Searching: '..query:concat(' '))

    local no_results   = true
    local sorted_names = global_storages:keyset():sort()
                                                 :reverse()

    if windower.ffxi.get_info().logged_in then
        sorted_names = sorted_names:append(sorted_names:remove(sorted_names:find(windower.ffxi.get_player().name)))
                               :reverse()
    end

    local export_file

    if export ~= nil then
        export_file = io.open(windower.addon_path..'data/'..export, 'w')

        if export_file == nil then
            error('The file "'..export..'" cannot be created.')
        else
            export_file:write('"char";"storage";"item";"quantity"\n')
        end
    end

    local total_quantity = 0
    
    for _, character_name in ipairs(sorted_names) do
        if (character_set:length() == 0 or character_set:contains(character_name)) and not character_filter:contains(character_name) then
            local storages = global_storages[character_name]

            for _, storage_name in ipairs(merged_storages_orders) do
                local results = L{}

                if storage_name~= 'gil' and storages[storage_name] ~= nil then
                    for id, quantity in pairs(storages[storage_name]) do
                        if storage_name == 'key items' and results_key_items:contains(id) then
                            if terms_pattern ~= '' then
                                total_quantity = total_quantity + quantity
                                results:append(
                                    (character_name..'/'..storage_name..':'):color(259)..' '..
                                    key_item_names[id].name:gsub('('..terms_pattern..')', ('%1'):color(258))..
                                    (quantity > 1 and ' '..('('..quantity..')'):color(259) or '')
                                )
                            else
                                results:append(
                                    (character_name..'/'..storage_name..':'):color(259)..' '..key_item_names[id].name..
                                    (quantity > 1 and ' '..('('..quantity..')'):color(259) or '')
                                )
                            end

                            if export_file ~= nil then
                                export_file:write('"'..character_name..'";"'..storage_name..'";"'..key_item_names[id].name..'";"'..quantity..'"\n')
                            end

                            no_results = false
                        elseif storage_name ~= 'key items' and results_items:contains(id) then
                            if terms_pattern ~= '' then
                                total_quantity = total_quantity + quantity
                                results:append(
                                    (character_name..'/'..storage_name..':'):color(259)..' '..
                                    item_names[id].name:gsub('('..terms_pattern..')', ('%1'):color(258))..
                                    (item_names[id].name:match(terms_pattern) and '' or ' ['..item_names[id].long_name:gsub('('..terms_pattern..')', ('%1'):color(258))..']')..
                                    (quantity > 1 and ' '..('('..quantity..')'):color(259) or '')
                                )
                            else
                                results:append(
                                    (character_name..'/'..storage_name..':'):color(259)..' '..item_names[id].name..
                                    (quantity > 1 and ' '..('('..quantity..')'):color(259) or '')
                                )
                            end

                            if export_file ~= nil then
                                export_file:write('"'..character_name..'";"'..storage_name..'";"'..item_names[id].name..'";"'..quantity..'"\n')
                            end

                            no_results = false
                        end
                    end

                    results:sort()

                    for i, result in ipairs(results) do
                        log(result)
                    end
                end
                coroutine.yield()
            end
        end
    end

    if total_quantity > 0 then
        log('Total: ' .. total_quantity)
    end

    if export_file ~= nil then
        export_file:close()
        log('The results have been saved to "'..export..'"')
    end

    if no_results then
        if terms ~= '' then
            if character_set:length() == 0 and character_filter:length() == 0 then
                log('You have no items that match \''..terms..'\'.')
            else
                log('You have no items that match \''..terms..'\' on the specified characters.')
            end
        else
            log('You have no items on the specified characters.')
        end
    end
end

function get_local_storage()
    local items = windower.ffxi.get_items()
    if not items then
        error('Failed to get items from FFXI')
        return false
    end

    local storages = {
        gil = type(items.gil) == 'number' and items.gil or 0
    }

    for _, storage_name in ipairs(storages_order) do
        storages[storage_name] = T{}

        for _, data in ipairs(items[storage_name]) do
            if type(data) == 'table' then
				if data.id ~= 0 then
					local id = tostring(data.id)
					storages[storage_name][id] = (storages[storage_name][id] or 0) + data.count
				end
			end
        end
    end

    local slip_storages = slips.get_player_items()

    for _, slip_id in ipairs(slips.storages) do
        local slip_name     = 'slip '..tostring(slips.get_slip_number_by_id(slip_id)):lpad('0', 2)
        storages[slip_name] = T{}

        for _, id in ipairs(slip_storages[slip_id]) do
            storages[slip_name][tostring(id)] = 1
        end
    end
    
    local key_items= windower.ffxi.get_key_items()
    
    storages['key items'] = T{}
    
    for _, id in ipairs(key_items) do
        storages['key items'][tostring(id)] = 1
    end

    return storages
end

function encase_key(key)
    if type(key) == 'number' then
        return '['..tostring(key)..']'
    elseif type(key) == 'string' then
        return '["'..key..'"]'
    else
        return tostring(key)
    end
end

function make_table(tab,tab_offset)
    -- Won't work for circular references or keys containing double quotes
    local offset = " ":rep(tab_offset)
    local ret = "{\n"
    for i,v in pairs(tab) do
        ret = ret..offset..encase_key(i)..' = '
        if type(v) == 'table' then
            ret = ret..make_table(v,tab_offset+2)..',\n'
        else
            ret = ret..tostring(v)..',\n'
        end
    end
    return ret..offset..'}'
end

-- Near the top with other global variables
local normalized_path = windower.addon_path:gsub('/', '\\'):gsub('\\+', '\\')
local parent_dir = normalized_path:gsub('Cards\\$', ''):gsub('cards\\$', '')
local findAll_exists = windower.dir_exists(parent_dir .. 'findAll')
local findAll_path = findAll_exists and (parent_dir .. 'findAll\\data\\') or nil
local using_findAll = findAll_exists

storages_path = using_findAll and 
    findAll_path or 
    windower.addon_path..'data\\'

-- Modify the update function
function update()
    if not windower.ffxi.get_info().logged_in then
        error('You have to be logged in to use this addon.')
        return false
    end

    if zone_search == false then
        notice('Cards has not detected a fully loaded inventory yet.')
        return false
    end

    local player_name = windower.ffxi.get_player().name
    local local_storage = get_local_storage()
    if not local_storage then
        return false
    end

    global_storages[player_name] = local_storage

    if using_findAll then
        local success, err = pcall(function()
            local file = io.open(storages_path .. player_name .. '.lua', 'w')
            if file then
                file:write('return '..make_table(local_storage,0)..'\n')
                file:close()
            else
                error('Could not open findAll storage file for writing')
            end
        end)
        
        if not success then
            error('Failed to write findAll storage file: ' .. err)
            return false
        end
    else
        if not windower.dir_exists(windower.addon_path..'data') then
            windower.create_dir(windower.addon_path..'data')
        end
        
        local success, err = pcall(function()
            local file = io.open(windower.addon_path..'data\\'..player_name..'.lua', 'w')
            if file then
                file:write('return '..make_table(local_storage,0)..'\n')
                file:close()
            else
                error('Could not open storage file for writing')
            end
        end)
        
        if not success then
            error('Failed to write storage file: ' .. err)
            return false
        end
    end

    collectgarbage()
    return true
end

function update_global_storage()
    local player_name = windower.ffxi.get_player().name
    
    global_storages = T{} 
    
    notice('Looking for storage files in: ' .. storages_path)
    for _, f in pairs(windower.get_dir(storages_path)) do
        if f:sub(-4) == '.lua' and f:sub(1,-5) ~= player_name then
            notice('Found storage file: ' .. f)
            local success, result = pcall(dofile, storages_path .. f)
            if success then
                global_storages[f:sub(1,-5)] = result
                notice('Successfully loaded storage for: ' .. f:sub(1,-5))
                -- Debug the loaded storage content
                for bag_name, items in pairs(result) do
                    if type(items) == 'table' then
                        notice('Loaded bag: ' .. bag_name .. ' with ' .. table.count(items) .. ' items')
                    end
                end
            else
                warning('Unable to retrieve updated item storage for %s: %s':format(f:sub(1,-5), result))
            end
        end
    end
end

handle_command = function(...)
    local params = L{...}
    if not params[1] then
        log('Usage: //cards JOB')
        return
    end
    local job = params[1]:upper()
    find_cards(job)
end

windower.register_event('unhandled command', function(command, ...)
    if command:lower() == 'cards' then
        local args = T{...}
        if not args[1] then
            log('Usage: //cards JOB')
            return
        end
        local job = args[1]:upper()
        find_cards(job)
    end
end)

windower.register_event('addon command', handle_command)

-- Add near the top with other global variables
job_equipment = {
    WAR = {
        {{"Pumm. Mask +1", "Pummeler's Mask +1"}, 48},
        {{"Pumm. Lorica +1", "Pummeler's Lorica +1"}, 60},
        {{"Pumm. Mufflers +1", "Pummeler's Mufflers +1"}, 42},
        {{"Pumm. Cuisses +1", "Pummeler's Cuisses +1"}, 54},
        {{"Pumm. Calligae +1", "Pummeler's Calligae +1"}, 36}
    },
    MNK = {
        {{"Anch. Crown +1", "Anchorite's Crown +1", "Anchor. Crown +1"}, 48},
        {{"Anch. Cyclas +1", "Anchorite's Cyclas +1"}, 60},
        {{"Anch. Gloves +1", "Anchorite's Gloves +1", "Anchor. Gloves +1" }, 42},
        {{"Anch. Hose +1", "Anchorite's Hose +1"}, 54},
        {{"Anch. Gaiters +1", "Anchorite's Gaiters +1"}, 36}
    },    
    WHM = {
        {{"Theo. Cap +1", "Theophany Cap +1"}, 48},
        {{"Theo. Bliaut +1", "Theophany Bliaut +1"}, 60},
        {{"Theo. Mitts +1", "Theophany Mitts +1"}, 42},
        {{"Theo. Pant. +1", "Theophany Pantaloons +1", "Th. Pant. +1"}, 54},
        {{"Theo. Duckbills +1", "Theophany Duckbills +1"}, 36}
    },
    RDM = {
        {{"Atro. Chapeau +1", "Atrophy Chapeau +1"}, 48},
        {{"Atro. Tabard +1", "Atrophy Tabard +1"}, 60},
        {{"Atro. Gloves +1", "Atrophy Gloves +1"}, 42},
        {{"Atro. Tights +1", "Atrophy Tights +1"}, 54},
        {{"Atro. Boots +1", "Atrophy Boots +1"}, 36}
    },
    BLM = {
        {{"Spae. Petasos +1", "Spaekona's Petasos +1"}, 48},
        {{"Spae. Coat +1", "Spaekona's Coat +1"}, 60},
        {{"Spae. Gloves +1", "Spaekona's Gloves +1"}, 42},
        {{"Spae. Tonban +1", "Spaekona's Tonban +1"}, 54},
        {{"Spae. Sabots +1", "Spaekona's Sabots +1"}, 36}
    },
    THF = {
        {{"Pill. Bonnet +1", "Pillager's Bonnet +1"}, 48},
        {{"Pill. Vest +1", "Pillager's Vest +1"}, 60},
        {{"Pill. Armlets +1", "Pillager's Armlets +1"}, 42},
        {{"Pill. Culottes +1", "Pillager's Culottes +1"}, 54},
        {{"Pill. Poulaines +1", "Pillager's Poulaines +1"}, 36}
    },
    PLD = {
        {{"Rev. Coronet +1", "Reverence Coronet +1"}, 48},
        {{"Rev. Surcoat +1", "Reverence Surcoat +1"}, 60},
        {{"Rev. Gauntlets +1", "Reverence Gauntlets +1"}, 42},
        {{"Rev. Breeches +1", "Reverence Breeches +1"}, 54},
        {{"Rev. Leggings +1", "Reverence Leggings +1"}, 36}
    },
    DRK = {
        {{"Igno. Burgeonet +1", "Ignominy Burgeonet +1", "Ig. Burgeonet +1"}, 48},
        {{"Igno. Cuirass +1", "Ignominy Cuirass +1"}, 60},
        {{"Igno. Gauntlets +1", "Ignominy Gauntlets +1",  "Ig. Gauntlets +1"}, 42},
        {{"Igno. Flan. +1", "Ignominy Flanchard +1", "Ig. Flanchard +1"}, 54},
        {{"Igno. Sollerets +1", "Ignominy Sollerets +1", "Ig. Sollerets +1"}, 36}
    },
    BST = {
        {{"Tot. Helm +1", "Totemic Helm +1"}, 48},
        {{"Tot. Jackcoat +1", "Totemic Jackcoat +1"}, 60},
        {{"Tot. Gloves +1", "Totemic Gloves +1"}, 42},
        {{"Tot. Trousers +1", "Totemic Trousers +1"}, 54},
        {{"Tot. Gaiters +1", "Totemic Gaiters +1"}, 36}
    },
    BRD = {
        {{"Brioso Roundlet +1", "Brioso Roundlet +1"}, 48},
        {{"Brioso Just. +1", "Brioso Justaucorps +1"}, 60},
        {{"Brioso Cuffs +1", "Brioso Cuffs +1"}, 42},
        {{"Brioso Cann. +1", "Brioso Cannions +1"}, 54},
        {{"Brioso Slippers +1", "Brioso Slippers +1"}, 36}
    },
    RNG = {
        {{"Orion Beret +1", "Orion Beret +1"}, 48},
        {{"Orion Jerkin +1", "Orion Jerkin +1"}, 60},
        {{"Orion Bracers +1", "Orion Bracers +1"}, 42},
        {{"Orion Braccae +1", "Orion Braccae +1"}, 54},
        {{"Orion Socks +1", "Orion Socks +1"}, 36}
    },
    SAM = {
        {{"Waki. Kabuto +1", "Wakido Kabuto +1"}, 48},
        {{"Waki. Domaru +1", "Wakido Domaru +1"}, 60},
        {{"Waki. Kote +1", "Wakido Kote +1"}, 42},
        {{"Waki. Haidate +1", "Wakido Haidate +1"}, 54},
        {{"Waki. Sune-Ate +1", "Wakido Sune-Ate +1", "Wakido Sune. +1" }, 36}
    },
    NIN = {
        {{"Hachi. Hatsu. +1", "Hachiya Hatsuburi +1", "Hachiya Hatsu. +1"}, 48},
        {{"Hachi. Chain. +1", "Hachiya Chainmail +1", "Hachiya Chain. +1"}, 60},
        {{"Hachi. Tekko +1", "Hachiya Tekko +1"}, 42},
        {{"Hachi. Hakama +1", "Hachiya Hakama +1"}, 54},
        {{"Hachi. Kyahan +1", "Hachiya Kyahan +1"}, 36}
    },
    DRG = {
        {{"Vishap Armet +1", "Vishap Armet +1"}, 48},
        {{"Vishap Mail +1", "Vishap Mail +1"}, 60},
        {{"Vishap F. G. +1", "Vishap Finger Gauntlets +1", "Vis. Fng. Gaunt. +1"}, 42},
        {{"Vishap Brais +1", "Vishap Brais +1"}, 54},
        {{"Vishap Greaves +1", "Vishap Greaves +1"}, 36}
    },
    SMN = {
        {{"Con. Horn +1", "Convoker's Horn +1"}, 48},
        {{"Con. Doublet +1", "Convoker's Doublet +1"}, 60},
        {{"Con. Bracers +1", "Convoker's Bracers +1", "Convo. Bracers +1"}, 42},
        {{"Con. Spats +1", "Convoker's Spats +1", "Convo. Spats +1"}, 54},
        {{"Con. Pigaches +1", "Convoker's Pigaches +1", "Convo. Pigaches +1"}, 36}
    },
    BLU = {
        {{"Assim. Keffiyeh +1", "Assimilator's Keffiyeh +1"}, 48},
        {{"Assim. Jubbah +1", "Assimilator's Jubbah +1"}, 60},
        {{"Assim. Bazu. +1", "Assimilator's Bazubands +1"}, 42},
        {{"Assim. Shalwar +1", "Assimilator's Shalwar +1"}, 54},
        {{"Assim. Charuqs +1", "Assimilator's Charuqs +1"}, 36}
    },
    COR = {
        {{"Laksa. Tricorne +1", "Laksamana's Tricorne +1"}, 48},
        {{"Laksa. Frac +1", "Laksamana's Frac +1"}, 60},
        {{"Laksa. Gants +1", "Laksamana's Gants +1"}, 42},
        {{"Laksa. Trews +1", "Laksamana's Trews +1"}, 54},
        {{"Laksa. Bottes +1", "Laksamana's Bottes +1"}, 36}
    },
    PUP = {
        {{"Foire Taj +1", "Foire Taj +1"}, 48},
        {{"Foire Tobe +1", "Foire Tobe +1"}, 60},
        {{"Foire Dastanas +1", "Foire Dastanas +1"}, 42},
        {{"Foire Churidars +1", "Foire Churidars +1"}, 54},
        {{"Foire Babouches +1", "Foire Babouches +1", "Foire Bab. +1"}, 36}
    },
    DNC = {
        {{"Maxixi Tiara +1", "Maxixi Tiara +1"}, 48},
        {{"Maxixi Casaque +1", "Maxixi Casaque +1"}, 60},
        {{"Maxixi Bangles +1", "Maxixi Bangles +1"}, 42},
        {{"Maxixi Tights +1", "Maxixi Tights +1"}, 54},
        {{"Maxixi Toe Shoes +1", "Maxixi Toe Shoes +1"}, 36}
    },
    SCH = {
        {{"Acad. Mortar. +1", "Academic's Mortarboard +1"}, 48},
        {{"Acad. Gown +1", "Academic's Gown +1"}, 60},
        {{"Acad. Bracers +1", "Academic's Bracers +1"}, 42},
        {{"Acad. Pants +1", "Academic's Pants +1"}, 54},
        {{"Acad. Loafers +1", "Academic's Loafers +1"}, 36}
    },
    GEO = {
        {{"Geo. Galero +1", "Geomancy Galero +1"}, 48},
        {{"Geo. Tunic +1", "Geomancy Tunic +1"}, 60},
        {{"Geo. Mitaines +1", "Geomancy Mitaines +1"}, 42},
        {{"Geo. Pants +1", "Geomancy Pants +1"}, 54},
        {{"Geo. Sandals +1", "Geomancy Sandals +1"}, 36}
    },
    RUN = {
        {{"Rune. Bandeau +1", "Runeist's Bandeau +1"}, 48},
        {{"Rune. Coat +1", "Runeist's Coat +1"}, 60},
        {{"Rune. Mitons +1", "Runeist's Mitons +1"}, 42},
        {{"Rune. Trousers +1", "Runeist's Trousers +1"}, 54},
        {{"Rune. Boots +1", "Runeist's Boots +1"}, 36}
    }
}

-- Add this new function
function find_cards(job)
    if not job_equipment[job] then
        log('No equipment data found for job: ' .. job)
        return
    end

    -- Ensure we're logged in and storage is up to date
    if not windower.ffxi.get_info().logged_in then
        error('You have to be logged in to use this command.')
        return
    end

    if not update() then
        error('Failed to update storage information.')
        return
    end

    local total_cards = 0
    local card_name = 'P. ' .. job .. ' Card'
    local player_name = windower.ffxi.get_player().name
    local existing_cards = 0
    
    log('Checking ' .. job .. ' equipment...')
    
    for index, equip_data in ipairs(job_equipment[job]) do
        local equip_names = equip_data[1]  -- Array of possible names
        local cards_needed = equip_data[2]
        local base_name = equip_names[1]:gsub(' %+1$', '')  -- Use first name as display name
        local found_plus3 = false
        local found_plus2 = false
        local found_plus1 = false
        local found_nq = false
        
        -- Check only current player's storage
        local storages = global_storages[player_name]
        if storages then
            for storage_name, items in pairs(storages) do
                if storage_name ~= 'gil' and storage_name ~= 'key items' then
                    for item_id, quantity in pairs(items) do
                        local item = res.items[tonumber(item_id)]
                        if item and item.name then
                            -- Check for existing cards
                            if item.name == card_name then
                                existing_cards = existing_cards + quantity
                            end
                            
                            -- Check all possible names
                            for _, name in ipairs(equip_names) do
                                if name then
                                    local nq_name = name:gsub(' %+1$', '')  -- Remove +1 to get NQ name
                                    local plus3_name = name:gsub(' %+1$', ' +3')
                                    local plus2_name = name:gsub(' %+1$', ' +2')
                                    
                                    if item.name == plus3_name then
                                        found_plus3 = true
                                        log(base_name:color(255) .. ': ' .. 'Already +3':color(158))
                                        break
                                    elseif item.name == plus2_name then
                                        found_plus2 = true
                                    elseif item.name == name then
                                        found_plus1 = true
                                    elseif item.name == nq_name then
                                        found_nq = true
                                    end
                                end
                            end
                        end
                        if found_plus3 then break end
                    end
                end
                if found_plus3 then break end
            end
        end
        
        if not found_plus3 then
            if found_plus2 then
                -- Adjust card requirements based on slot for +2 gear
                local plus2_cards
                if index == 1 then -- Head
                    plus2_cards = 40
                elseif index == 2 then -- Body
                    plus2_cards = 50
                elseif index == 3 then -- Hands
                    plus2_cards = 35
                elseif index == 4 then -- Legs
                    plus2_cards = 45
                elseif index == 5 then -- Feet
                    plus2_cards = 30
                end
                total_cards = total_cards + plus2_cards
                log(base_name:color(255) .. ': Needs ' .. tostring(plus2_cards):color(158) .. ' cards ' .. '(currently +2)':color(158))
            elseif found_plus1 then
                total_cards = total_cards + cards_needed
                log(base_name:color(255) .. ': Needs ' .. tostring(cards_needed):color(158) .. ' cards ' .. '(currently +1)':color(158))
            elseif found_nq then
                total_cards = total_cards + cards_needed
                log(base_name:color(255) .. ': Needs ' .. tostring(cards_needed):color(158) .. ' cards ' .. '(currently NQ)':color(158))
            else
                log(base_name:color(255) .. ': ' .. 'Not found':color(158))
            end
        end
    end
    
    -- Move card counting outside the gear check loop
    local storages = global_storages[player_name]
    if storages then
        for storage_name, items in pairs(storages) do
            if storage_name ~= 'gil' and storage_name ~= 'key items' then
                for item_id, quantity in pairs(items) do
                    local item = res.items[tonumber(item_id)]
                    if item and item.name == card_name then
                        existing_cards = existing_cards + quantity
                    end
                end
            end
        end
    end
    
    if total_cards > 0 then
        log('Total ' .. card_name .. 's needed: ' .. tostring(total_cards):color(158))
        log('You currently have: ' .. tostring(existing_cards):color(158) .. ' cards')
        local remaining_cards = total_cards - existing_cards
        if remaining_cards > 0 then
            log('Additional cards needed: ' .. tostring(remaining_cards):color(158))
        else
            log('You have enough cards!':color(158))
        end
    else
        -- Even if no upgrades needed, still show existing cards
        log('No upgrades needed')
        log('You currently have: ' .. tostring(existing_cards):color(158) .. ' cards')
    end
end

-- Add this debug logging to check_job_cards function
function check_job_cards(job)
    if not job_equipment[job] then
        log('No equipment data found for job: ' .. job)
        return
    end

    -- Ensure we're logged in
    if not windower.ffxi.get_info().logged_in then
        error('You have to be logged in to use this command.')
        return
    end

    -- Debug storage info
    notice('Current storage path: ' .. storages_path)
    notice('Using findAll: ' .. tostring(using_findAll))
    
    -- Update global storage info
    local success, err = pcall(update_global_storage)
    if not success then
        error('Failed to update global storage: ' .. err)
        return
    end

    local player_name = windower.ffxi.get_player().name
    notice('Checking storage for player: ' .. player_name)
    
    -- Debug global_storages content
    for char_name, storage in pairs(global_storages) do
        notice('Found storage for character: ' .. char_name)
        for bag_name, items in pairs(storage) do
            if type(items) == 'table' then
                notice('Found bag: ' .. bag_name .. ' with ' .. table.count(items) .. ' items')
            end
        end
    end

    -- Rest of the existing check_job_cards function...
end
