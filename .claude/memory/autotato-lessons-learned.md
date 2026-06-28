---
title: AutoTato 开发教训
description: >
  AutoTato mod 开发过程中踩过的坑，属于 autotato 领域知识。
  覆盖货币读取 API 误用（get_player_gold vs get_player_currency、
  hp_shop 兼容性）、preload 常量替代 class_name 引用
  （Workshop ZIP Parse Error 修复）、以及其他开发中的错误用法
  与正确用法的对比和根因分析。
game_version: 1.1.15.4
---

# AutoTato 开发教训

> 本文件记录 AutoTato mod 开发过程中踩过的坑和教训总结。
> 每条教训格式：错误做法 → 为什么错 → 正确做法 → 根因分析。

---

## 1. 货币读取：`get_player_gold()` vs `get_player_currency()`

### 背景
在商店决策中需要判断"玩家是否买得起某个物品"。

### 错误做法
```gdscript
var currency: int = RunData.get_player_gold(player_index)
```

### 为什么错
`get_player_gold()` **永远返回金币**。恶魔角色（Demon）有 `hp_shop` 效果，用 HP 而非金币作为商店货币。如果一个恶魔角色有 0 金币但 50 HP，`get_player_gold()` 返回 0，预算墙会拒绝所有购买。

### 正确做法
```gdscript
var currency: int = RunData.get_player_currency(player_index)
```

`get_player_currency()` 会先检查 `effects[hp_shop_hash]`：
- 有 `hp_shop` → 返回 `get_stat(stat_max_hp)`（经过 gain 修正的最大 HP）
- 无 `hp_shop` → 返回 `get_player_gold()`（普通金币）

### 根因
**"金币"和"货币"是不同层次的概念**。我们把这两个概念混淆了。vanilla 已经提供了正确的抽象层 `get_player_currency()`，但我们没有意识到它的存在，或者没有理解它和我们直接读 `gold` 有什么区别。

### 教训
**先查是否有更高层的抽象**。想读"买东西要花的钱"→ 搜索 `currency` 相关方法，而不是直奔 `gold`。

---

## 2. 价格读取：自己算 vs 读 `ShopItem.value`

### 背景
在商店决策中需要知道物品的最终价格，用于预算墙判断（`currency - price >= min_gold_balance`）。

### 错误做法
尝试自己从 `item_data.value` 出发，调 `ItemService.get_value()` 或自己实现价格计算。

### 为什么错
vanilla 的 `shop_item.set_shop_item()` 已经完成了**全部**价格计算：
1. `ItemService.get_value(wave, item_data.value, ...)` — 波次通胀 + 武器/物品价格倍率 + 无尽因子
2. 如果有 `hp_shop`：`ceil(value / 20.0)` — HP 商店除以 20 转换

自己重新算不仅重复劳动，还容易遗漏因子（如无尽模式 inflation、特定物品价格修正等）。

### 正确做法
直接从 `ShopItem.value` 读取已计算好的最终价格：
```gdscript
var price: int = int(node.get("value"))
```

这个值与 vanilla UI 显示的价格完全一致。

### 根因
**试图"重新发明轮子"，而不是信任 vanilla 已经做好的工作**。当 vanilla UI 节点上已经有了正确的值，直接读它就是最安全的方式。

### 教训
**优先读 UI 节点的值而不是自己算**。vanilla 的 UI 节点值是经过完整业务逻辑处理后的最终结果，自己算一定会缺失某些边角 case。

---

## 3. 每 slot 重新查询货币

### 背景
在 `_decide_shop_round()` 中，需要遍历商店的 4 个 slot 逐一做购买决策。

### 潜在陷阱
如果在循环前读一次货币，用同一个值判断所有 slot 的购买，那么购买一个物品后的副作用（如蛋糕 Cake 的 +max_hp）不会反映到后续 slot 的预算判断中。

### 正确做法
```gdscript
for slot_index in player_slots.size():
    # 每 slot 重新查询货币 (购买副作用已通过即时执行反映)
    var currency: int = _read_player_currency(player_index)
    var price: int = executor._at_get_item_price(item_id, player_index)
    var dr = decide_shop_item(item_data, currency, price, player_index, force)
    # 即时执行购买
    executor._at_execute_one(entry, player_index)
```

### 根因
**购买操作有副作用**（改变 stat、货币余额等），必须在每步决策前重新读状态。

### 教训
**在循环中每步操作后可能改变全局状态的场景，必须每迭代重新读状态**。不能缓存"看似不变"的值。

---

## 4. 通用教训总结

1. **"看起来没问题但不正确"是最大的陷阱**：`get_player_gold` 返回 0 在语法上没问题，值类型也对，但业务含义完全错了
2. **反复问"这个值的含义是什么"**：不是"这个 API 返回什么类型"，而是"它代表什么业务概念"
3. **vanilla 已经有了的轮子不要再造**：如果 vanilla UI 显示了正确的值、vanilla 提供了抽象方法，直接用
4. **理解 API 参数的"业务含义"**：`player_index` 不只是"第几个玩家"，在 currency 语境下它代表"哪个人的钱包"
