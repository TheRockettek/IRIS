local itemStackOverrides = {
    -- Tools
    ["minecraft:wooden_sword"] = 1,
    ["minecraft:wooden_pickaxe"] = 1,
    ["minecraft:wooden_axe"] = 1,
    ["minecraft:wooden_shovel"] = 1,
    ["minecraft:wooden_hoe"] = 1,

    ["minecraft:leather_helmet"] = 1,
    ["minecraft:leather_chestplate"] = 1,
    ["minecraft:leather_leggings"] = 1,
    ["minecraft:leather_boots"] = 1,

    ["minecraft:chainmail_helmet"] = 1,
    ["minecraft:chainmail_chestplate"] = 1,
    ["minecraft:chainmail_leggings"] = 1,
    ["minecraft:chainmail_boots"] = 1,

    ["minecraft:stone_sword"] = 1,
    ["minecraft:stone_pickaxe"] = 1,
    ["minecraft:stone_axe"] = 1,
    ["minecraft:stone_shovel"] = 1,
    ["minecraft:stone_hoe"] = 1,

    ["minecraft:stone_helmet"] = 1,
    ["minecraft:stone_chestplate"] = 1,
    ["minecraft:stone_leggings"] = 1,
    ["minecraft:stone_boots"] = 1,

    ["minecraft:iron_sword"] = 1,
    ["minecraft:iron_pickaxe"] = 1,
    ["minecraft:iron_axe"] = 1,
    ["minecraft:iron_shovel"] = 1,
    ["minecraft:iron_hoe"] = 1,

    ["minecraft:iron_helmet"] = 1,
    ["minecraft:iron_chestplate"] = 1,
    ["minecraft:iron_leggings"] = 1,
    ["minecraft:iron_boots"] = 1,

    ["minecraft:golden_sword"] = 1,
    ["minecraft:golden_pickaxe"] = 1,
    ["minecraft:golden_axe"] = 1,
    ["minecraft:golden_shovel"] = 1,
    ["minecraft:golden_hoe"] = 1,

    ["minecraft:golden_helmet"] = 1,
    ["minecraft:golden_chestplate"] = 1,
    ["minecraft:golden_leggings"] = 1,
    ["minecraft:golden_boots"] = 1,

    ["minecraft:diamond_sword"] = 1,
    ["minecraft:diamond_pickaxe"] = 1,
    ["minecraft:diamond_axe"] = 1,
    ["minecraft:diamond_shovel"] = 1,
    ["minecraft:diamond_hoe"] = 1,

    ["minecraft:diamond_helmet"] = 1,
    ["minecraft:diamond_chestplate"] = 1,
    ["minecraft:diamond_leggings"] = 1,
    ["minecraft:diamond_boots"] = 1,

    ["minecraft:netherite_sword"] = 1,
    ["minecraft:netherite_pickaxe"] = 1,
    ["minecraft:netherite_axe"] = 1,
    ["minecraft:netherite_shovel"] = 1,
    ["minecraft:netherite_hoe"] = 1,

    ["minecraft:netherite_helmet"] = 1,
    ["minecraft:netherite_chestplate"] = 1,
    ["minecraft:netherite_leggings"] = 1,
    ["minecraft:netherite_boots"] = 1,

    -- Bits
    ["minecraft:saddle"] = 1,
    ["minecraft:minecart"] = 1,
    ["minecraft:chest_minecart"] = 1,
    ["minecraft:furnace_minecart"] = 1,
    ["minecraft:tnt_minecart"] = 1,
    ["minecraft:hopper_minecart"] = 1,
    ["minecraft:elytra"] = 1,
    ["minecraft:goat_horn"] = 1,
    ["minecraft:flint_and_steel"] = 1,

    -- Plethora
    ["plethora:neutral_interface"] = 1,
    ["plethora:neural_connector"] = 1,
    ["plethora:overlay_glasses"] = 1,
    ["plethora:module_introspection"] = 1,
    ["plethora:module_keyboard"] = 1,
    ["plethora:module_laser"] = 1,
    ["plethora:module_scanner"] = 1,
    ["plethora:module_sensor"] = 1,
    ["plethora:module_kinetic"] = 1,
}

-- TODO: Move to dynamic table

local function GetItemMaxStack(name)
    return itemStackOverrides[name] or 64
end

return {
    GetItemMaxStack = GetItemMaxStack
}