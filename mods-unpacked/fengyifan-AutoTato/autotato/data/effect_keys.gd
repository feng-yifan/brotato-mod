extends Reference
class_name AT_EffectKeys

# ============================================================================
# AutoTato - Effect Keys 中央字典
# ----------------------------------------------------------------------------
# 目的: 为决策器提供权威的 vanilla effect key 元数据, 用于判断每个 key 是
#       stat 修饰、bucket 桶名(数组类聚合)、还是 boolean / replace 类标量.
#
# 对应 vanilla 文件:
#   - singletons/keys.gd            (所有 effect key 字符串及其 hash 定义)
#   - singletons/player_run_data.gd (init_effects() 提供 effects 字典初始值)
#   - singletons/run_data.gd        (primary_stats_list 给出 stat_* 列表)
#
# 设计取舍:
#   - stat_damage 与 stat_percent_damage 故意分开: vanilla 中 stat_damage 是
#     flat (+N 伤害, 来自武器/道具直接加成), 而 stat_percent_damage 是百分比
#     乘区. 二者在 ItemService 加成路径上走不同分支, 不能混为一谈.
#   - bucket 判定标准: 在 init_effects() 中初始值为 `[]` 的 key, 即采用
#     APPEND_KEY / APPEND_KEY_VALUE 模式追加结构体; 初始值为纯数字的视为
#     标量 (replace 或 累加), 不是 bucket.
# ============================================================================

const UNIT_FLAT := "flat"
const UNIT_PERCENT := "percent"
const UNIT_BOOLEAN := "boolean"

# 全部主要 stat_* 修饰键 (按 keys.gd 中定义顺序排列).
# 单位规则: 来自 ItemParent/Item 资源中 stat_* 字段约定:
#   max_hp / hp_regen / armor / range / harvesting 等 — flat 加值
#   damage / lifesteal / attack_speed / crit / engineering / dodge /
#     speed / luck / curse / percent_damage / elemental_damage / melee /
#     ranged — 多为百分比, 但 stat_damage 例外, 是 flat (区别于 stat_percent_damage).
const STAT_TAGS := {
	"stat_max_hp": {"unit": UNIT_FLAT, "positive_is_good": true},
	"stat_hp_regeneration": {"unit": UNIT_FLAT, "positive_is_good": true},
	"stat_lifesteal": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_damage": {"unit": UNIT_FLAT, "positive_is_good": true},
	"stat_melee_damage": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_ranged_damage": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_elemental_damage": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_percent_damage": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_attack_speed": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_crit_chance": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_engineering": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_range": {"unit": UNIT_FLAT, "positive_is_good": true},
	"stat_armor": {"unit": UNIT_FLAT, "positive_is_good": true},
	"stat_dodge": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_speed": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_luck": {"unit": UNIT_PERCENT, "positive_is_good": true},
	"stat_harvesting": {"unit": UNIT_FLAT, "positive_is_good": true},
	"stat_curse": {"unit": UNIT_PERCENT, "positive_is_good": false},
}

# 非 stat_ 的 effect/misc key 元数据.
# is_bucket=true 表示该 key 在 init_effects() 中初始值是 `[]`, 用 APPEND_KEY /
# APPEND_KEY_VALUE 累加; false 表示标量 (boolean / replace / 累加数字).
# 注释里列出代表性物品 / 角色, 便于决策器调试时溯源.
const MISC_TAGS := {
	# ---- gain_stat_* 系列 (累加数字, 给 wave_end 兑现的额外 stat) ----
	"gain_stat_max_hp": {"is_bucket": false},
	"gain_stat_armor": {"is_bucket": false},
	"gain_stat_crit_chance": {"is_bucket": false},
	"gain_stat_luck": {"is_bucket": false},
	"gain_stat_attack_speed": {"is_bucket": false},
	"gain_stat_elemental_damage": {"is_bucket": false},
	"gain_stat_hp_regeneration": {"is_bucket": false},
	"gain_stat_lifesteal": {"is_bucket": false},
	"gain_stat_melee_damage": {"is_bucket": false},
	"gain_stat_percent_damage": {"is_bucket": false},
	"gain_stat_dodge": {"is_bucket": false},
	"gain_stat_engineering": {"is_bucket": false},
	"gain_stat_range": {"is_bucket": false},
	"gain_stat_ranged_damage": {"is_bucket": false},
	"gain_stat_speed": {"is_bucket": false},
	"gain_stat_harvesting": {"is_bucket": false},
	"gain_stat_curse": {"is_bucket": false},

	# ---- 武器槽限制 (Generalist / Multitasker 等) ----
	"no_melee_weapons": {"is_bucket": false},      # boolean
	"no_ranged_weapons": {"is_bucket": false},     # boolean
	"no_duplicate_weapons": {"is_bucket": false},  # boolean
	"max_melee_weapons": {"is_bucket": false},     # Generalist, init=999 (replace)
	"max_ranged_weapons": {"is_bucket": false},    # Generalist, init=999 (replace)

	# ---- 商店 / 经济 (Anvil, Generalist, Multitasker) ----
	"items_price": {"is_bucket": false},           # Generalist, 百分比 replace
	"weapons_price": {"is_bucket": false},         # Multitasker
	"specific_items_price": {"is_bucket": true},
	"min_weapon_tier": {"is_bucket": false},       # init=0
	"max_weapon_tier": {"is_bucket": false},       # init=99
	"minimum_weapons_in_shop": {"is_bucket": false},
	"guaranteed_shop_items": {"is_bucket": true},
	"remove_shop_items": {"is_bucket": true},
	"hp_shop": {"is_bucket": false},
	"reroll_price": {"is_bucket": false},
	"free_rerolls": {"is_bucket": false},
	"increase_tier_on_reroll": {"is_bucket": true},
	"gain_stats_on_reroll": {"is_bucket": true},

	# ---- 浪 / 起始资源 ----
	"hp_start_wave": {"is_bucket": false},         # init=100 (replace, 百分比)
	"hp_start_next_wave": {"is_bucket": false},    # init=100 (replace, 百分比)
	"gain_pct_gold_start_wave": {"is_bucket": false},

	# ---- 角色行为开关 ----
	"pacifist": {"is_bucket": false},              # 不能造成伤害, boolean
	"cryptid": {"is_bucket": false},
	"torture": {"is_bucket": false},
	"one_shot_trees": {"is_bucket": false},
	"can_attack_while_moving": {"is_bucket": false}, # init=1, boolean
	"group_structures": {"is_bucket": false},
	"can_burn_enemies": {"is_bucket": false},      # init=1, boolean
	"no_heal": {"is_bucket": false},
	"disable_item_locking": {"is_bucket": false},
	"used_item_locking": {"is_bucket": false},
	"lock_current_weapons": {"is_bucket": false},

	# ---- 树木 / 收获 ----
	"trees": {"is_bucket": false},
	"trees_start_wave": {"is_bucket": false},
	"tree_turrets": {"is_bucket": false},

	# ---- 金币掉落 / 拾取触发 ----
	"neutral_gold_drops": {"is_bucket": false},    # 百分比, 中立物
	"enemy_gold_drops": {"is_bucket": false},      # 百分比, 敌人
	"instant_gold_attracting": {"is_bucket": false},
	"recycling_gains": {"is_bucket": false},       # Robot, 回收百分比
	"reload_when_pickup_gold": {"is_bucket": false},
	"dmg_when_pickup_gold": {"is_bucket": true},   # Mage 类
	"convert_bonus_gold": {"is_bucket": true},

	# ---- 受击 / 闪避 / 死亡触发 ----
	"dmg_when_death": {"is_bucket": true},
	"dmg_when_heal": {"is_bucket": true},
	"dmg_on_dodge": {"is_bucket": true},
	"heal_on_dodge": {"is_bucket": true},
	"explode_on_hit": {"is_bucket": true},
	"explode_when_below_hp": {"is_bucket": true},
	"explode_on_death": {"is_bucket": true},
	"explode_on_consumable": {"is_bucket": true},
	"explode_on_consumable_burning": {"is_bucket": true},
	"explode_on_overkill": {"is_bucket": true},
	"projectiles_on_death": {"is_bucket": true},

	# ---- 起始装备 (Lich / Cryptid 等) ----
	"starting_item": {"is_bucket": true},
	"cursed_starting_item": {"is_bucket": true},
	"starting_weapon": {"is_bucket": true},
	"cursed_starting_weapon": {"is_bucket": true},

	# ---- 武器加成桶 ----
	"weapon_class_bonus": {"is_bucket": true},     # Focus / Spider 类
	"weapon_type_bonus": {"is_bucket": true},
	"unique_weapon_effects": {"is_bucket": true},
	"additional_weapon_effects": {"is_bucket": true},
	"tier_iv_weapon_effects": {"is_bucket": true},
	"tier_i_weapon_effects": {"is_bucket": true},
	"weapon_scaling_stats": {"is_bucket": true},
	"minimum_weapon_cooldowns": {"is_bucket": true},
	"maximum_weapon_cooldowns": {"is_bucket": true},
	"upgrade_random_weapon": {"is_bucket": true},  # Anvil
	"destroy_weapons": {"is_bucket": false},
	"weapon_slot_upgrades": {"is_bucket": false},
	"all_weapons_count_for_sets": {"is_bucket": false},

	# ---- 暂时性 / 条件性 stat 累计 ----
	"temp_stats_while_not_moving": {"is_bucket": true},
	"temp_stats_while_moving": {"is_bucket": true},
	"temp_stats_on_hit": {"is_bucket": true},
	"temp_stats_on_dodge": {"is_bucket": true},
	"temp_stats_on_structure_crit": {"is_bucket": true},
	"temp_stats_per_interval": {"is_bucket": true},
	"decaying_stats_on_hit": {"is_bucket": true},
	"decaying_stats_on_consumable": {"is_bucket": true},
	"stats_end_of_wave": {"is_bucket": true},
	"convert_stats_end_of_wave": {"is_bucket": true},
	"convert_stats_half_wave": {"is_bucket": true},
	"stats_on_level_up": {"is_bucket": true},
	"stats_next_wave": {"is_bucket": true},
	"stats_below_half_health": {"is_bucket": true},
	"stats_on_fruit": {"is_bucket": true},
	"consumable_stats_while_max": {"is_bucket": true},
	"temp_consumable_stats_while_max": {"is_bucket": true},
	"gain_stat_for_every_step_after_equip": {"is_bucket": true},
	"gain_stat_for_equipped_item_with_stat": {"is_bucket": true},
	"gain_stat_for_duplicate_items": {"is_bucket": true},
	"gain_stat_for_killed_enemies_while_burning": {"is_bucket": true},
	"gain_stat_when_attack_killed_enemies": {"is_bucket": true},
	"gain_random_primary_stats_on_go_to_next_wave": {"is_bucket": true},
	"hp_regen_bonus": {"is_bucket": true},

	# ---- 击杀 / 暴击触发 ----
	"gold_on_crit_kill": {"is_bucket": true},
	"heal_on_crit_kill": {"is_bucket": false},
	"heal_on_kill": {"is_bucket": false},
	"gold_on_cursed_enemy_kill": {"is_bucket": false},
	"bonus_non_elemental_damage_against_burning_targets": {"is_bucket": false},
	"bonus_weapon_class_damage_against_cursed_enemies": {"is_bucket": true},
	"bonus_damage_against_targets_above_hp": {"is_bucket": true},
	"bonus_damage_against_targets_below_hp": {"is_bucket": true},

	# ---- 燃烧 / 元素相关 ----
	"burning_enemy_speed": {"is_bucket": false},
	"burning_enemy_hp_percent_damage": {"is_bucket": true},
	"slow_on_hit": {"is_bucket": true},
	"charm_on_hit": {"is_bucket": true},
	"enemy_percent_damage_taken": {"is_bucket": true},
	"pierce_on_crit": {"is_bucket": false},
	"bounce_on_crit": {"is_bucket": false},
	"knockback_aura": {"is_bucket": false},
	"negative_knockback": {"is_bucket": false},

	# ---- 弹道 / 命中 ----
	"accuracy": {"is_bucket": false},
	"projectiles": {"is_bucket": false},
	"modify_every_x_projectile": {"is_bucket": true},

	# ---- 结构 / 工程 (Engineer / Robot) ----
	"structures": {"is_bucket": true},
	"structures_can_crit": {"is_bucket": false},
	"structures_cooldown_reduction": {"is_bucket": true},
	"max_turret_count": {"is_bucket": false},      # init=LARGE_NUMBER, replace

	# ---- 饿魂 / 鲸鱼 / 钓鱼 ----
	"upgraded_baits": {"is_bucket": false},
	"loot_alien_speed": {"is_bucket": false},
	"loot_alien_chance": {"is_bucket": false},
	"crate_chance": {"is_bucket": false},
	"extra_item_in_crate": {"is_bucket": true},
	"extra_loot_aliens": {"is_bucket": false},
	"extra_loot_aliens_next_wave": {"is_bucket": false},
	"extra_loot_aliens_at_wave": {"is_bucket": false}, # 注意 init={}, 视作非 bucket
	"extra_enemies_next_wave": {"is_bucket": true},
	"extra_enemies_at_wave": {"is_bucket": false},     # init={}, 字典桶, 不走数组追加
	"extra_elite_next_wave_chance": {"is_bucket": false},

	# ---- 道具 / 物品行为 ----
	"item_steals": {"is_bucket": false},
	"item_steals_spawns_enemy": {"is_bucket": true},
	"item_steals_spawns_random_elite": {"is_bucket": false},
	"item_hourglass": {"is_bucket": false},
	"duplicate_item": {"is_bucket": true},
	"poisoned_fruit": {"is_bucket": false},
	"enemy_fruit_drops": {"is_bucket": false},
	"materials_per_living_enemy": {"is_bucket": false},
	"scale_materials_with_distance": {"is_bucket": true},
	"increase_material_value": {"is_bucket": false},
	"curse_locked_items": {"is_bucket": false},

	# ---- 升级 / XP ----
	"level_upgrades_modifications": {"is_bucket": false},
	"next_level_xp_needed": {"is_bucket": false},
	"consumable_heal_over_time": {"is_bucket": false},

	# ---- 危险 / 事件难度 (Danger5 等修改器) ----
	"danger_enemy_health": {"is_bucket": false},
	"danger_enemy_damage": {"is_bucket": false},
	"danger_enemy_speed": {"is_bucket": false},
	"bullet_hell_event": {"is_bucket": false},
	"fog_of_war_event": {"is_bucket": false},
	"double_boss": {"is_bucket": false},           # Danger5
	"special_enemies_last_wave": {"is_bucket": false},
	"stronger_elites_on_kill": {"is_bucket": false},
	"stronger_loot_aliens_on_kill": {"is_bucket": false},

	# ---- 加成型独立伤害 ----
	"gain_explosion_damage": {"is_bucket": false},
	"gain_piercing_damage": {"is_bucket": false},
	"gain_bounce_damage": {"is_bucket": false},
	"gain_damage_against_bosses": {"is_bucket": false},

	# ---- 联动 / 杂项 ----
	"wandering_bots": {"is_bucket": false},
	"stat_links": {"is_bucket": true},
	"giant_crit_damage": {"is_bucket": true},
	"landmines_on_death_chance": {"is_bucket": true},
	"alien_eyes": {"is_bucket": true},
	"burn_chance": {"is_bucket": false},           # 初始 BurningData 对象, 非 bucket

	# ---- 二级 stat 字段 (pets / jellyshield 等) ----
	"pets": {"is_bucket": true},
	"double_lifesteal_bonus": {"is_bucket": false},
	"jellyshield_count": {"is_bucket": false},
	"beast_master_effect": {"is_bucket": false},
	"boosted_wanted_item_tag": {"is_bucket": false},
	"has_lootworm": {"is_bucket": false},
	"fog_visibility": {"is_bucket": false},
}


# 是否属于已知的 stat_* 修饰 key.
static func is_known_stat(key: String) -> bool:
	return STAT_TAGS.has(key)


# 是否属于已知的非 stat 类 effect/misc key.
static func is_known_misc(key: String) -> bool:
	return MISC_TAGS.has(key)


# 是否是 bucket 桶名 (即在 player_run_data.init_effects 中初始值为数组,
# 走 APPEND_KEY / APPEND_KEY_VALUE 累加路径的 key).
static func is_bucket(key: String) -> bool:
	if not MISC_TAGS.has(key):
		return false
	return bool(MISC_TAGS[key].get("is_bucket", false))


# 返回 key 的单位 (flat / percent / boolean). 未知 key 返回空字符串.
static func get_unit(key: String) -> String:
	if STAT_TAGS.has(key):
		return String(STAT_TAGS[key].get("unit", ""))
	return ""


# 判断该 stat 正向变化是否对玩家有利. 仅 stat_* 有意义;
# 未知或非 stat key 默认返回 true (即"正即好").
static func is_positive_good(key: String) -> bool:
	if STAT_TAGS.has(key):
		return bool(STAT_TAGS[key].get("positive_is_good", true))
	return true


# 返回所有已知的 stat_* key 列表 (按 STAT_TAGS 字典定义顺序).
static func get_all_stat_keys() -> Array:
	return STAT_TAGS.keys()
