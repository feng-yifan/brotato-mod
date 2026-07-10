# AutoTato 商店决策链路

> 本文档用 Mermaid 图表直观展示 `fengyifan-AutoTato` 商店决策的完整调用链路,
> 涵盖商店物品决策线与升级决策线,以及 turbo / 非 turbo 两种执行模式。
> 适合作为开发者的架构教学与查阅材料。

---

## 一、分层架构总览

| 层 | 文件 | 职责 |
|---|---|---|
| **入口层** | `mod_main.gd` / `extensions/base_shop.gd` / `extensions/upgrades_ui.gd` | mod 安装、Script Extension 挂钩、UI 触发入口、UI 动作执行（购买/锁定/reroll/进波） |
| **编排层** | `shop/shop_automation.gd` / `shop/upgrade_automation.gd` | 流程编排:决策 + 执行 + reroll 循环 + 停止条件判断 |
| **决策层** | `shop/item_decider.gd` / `shop/threshold_gate.gd` / `shop/decision_result.gd` | 单物品纯决策意图(purchase/lock/manual/skip),不执行 UI |
| **执行结果层** | `shop/execute_result.gd` | 执行事实常量(purchased/locked/manual/skipped) |
| **数据层** | `shop/shop_data_reader.gd` / `shop/upgrade_data_reader.gd` | 集中读取 vanilla 运行时数据(金币/价格/物品节点/阈值/限购) |
| **配置层** | `config/config.gd` | 配置仓库,统一负责默认值回退,外部拿到的永远是最终可用值 |

```mermaid
graph TD
    subgraph 入口层
        mod_main[mod_main.gd<br/>install_script_extensions 挂钩]
        base_shop[extensions/base_shop.gd<br/>触发入口 + UI 执行器]
        upgrades_ui[extensions/upgrades_ui.gd<br/>升级界面触发]
    end

    subgraph 编排层
        shop_auto[shop/shop_automation.gd<br/>商店决策+reroll 循环]
        upgrade_auto[shop/upgrade_automation.gd<br/>升级决策+reroll 循环]
    end

    subgraph 决策层
        item_decider[shop/item_decider.gd<br/>物品纯意图决策]
        threshold_gate[shop/threshold_gate.gd<br/>阈值 gate]
        decision_result[shop/decision_result.gd<br/>DECISION_* 意图工厂]
    end

    subgraph 执行结果层
        execute_result[shop/execute_result.gd<br/>RESULT_* 事实常量]
    end

    subgraph 数据层
        shop_data[shop/shop_data_reader.gd<br/>商店运行时数据]
        upgrade_data[shop/upgrade_data_reader.gd<br/>升级运行时数据]
    end

    subgraph 配置层
        config[config/config.gd<br/>配置仓库 + 默认值回退]
    end

    mod_main --> base_shop
    mod_main --> upgrades_ui
    base_shop --> shop_auto
    upgrades_ui --> upgrade_auto
    shop_auto --> item_decider
    shop_auto --> shop_data
    item_decider --> threshold_gate
    item_decider --> decision_result
    item_decider -.->|带默认值回退| config
    threshold_gate -.->|带默认值回退| config
    base_shop --> execute_result
    upgrade_auto --> upgrade_data
    upgrade_auto -.->|带默认值回退| config

    classDef entryLayer fill:#e1f5ff,stroke:#0288d1
    classDef orchLayer fill:#fff4e1,stroke:#f57c00
    classDef decisionLayer fill:#f3e5f5,stroke:#7b1fa2
    classDef resultLayer fill:#e8f5e9,stroke:#388e3c
    classDef dataLayer fill:#fce4ec,stroke:#c2185b
    classDef configLayer fill:#f5f5f5,stroke:#616161

    class mod_main,base_shop,upgrades_ui entryLayer
    class shop_auto,upgrade_auto orchLayer
    class item_decider,threshold_gate,decision_result decisionLayer
    class execute_result resultLayer
    class shop_data,upgrade_data dataLayer
    class config configLayer
```

`★ 核心数据流`:配置层调用统一用虚线,表示"带默认值回退"--外部永远拿到最终可用值,不做 `if null` 判断。

---

## 二、商店决策主流程(turbo / 非 turbo 分叉)

入口层 `base_shop.gd` 的关键方法:

- **`_ready()`**:接管 vanilla 商店场景 ready,添加 AutoTato 决策按钮,`call_deferred` 自动触发一轮决策,开启临界区轮询。
- **`at_start_shop_decision_automatically(player_index)`**:自动入口,进入商店/reroll 后调用,受 `is_shop_automation_enabled()` 开关控制。
- **`at_start_shop_decision_manually(player_index)`**:手动入口,点击决策按钮或按 F 时调用,即使自动化关闭也强制执行一轮。
- **`_at_run_shop_decision(cfg, player_index)`**:执行单次决策 session,**turbo 与非 turbo 的分叉点**。

```mermaid
flowchart TD
    ready["base_shop._ready()<br/>接管 vanilla ready + 添加按钮"]
    trigger["_at_trigger_auto_shop_decision_all_players<br/>call_deferred 自动触发"]
    auto["at_start_shop_decision_automatically<br/>自动入口(开关控制)"]
    manual["at_start_shop_decision_manually<br/>手动入口(强制执行)"]
    run["_at_run_shop_decision(cfg, player_index)<br/>进入临界区 + 读取 delay/turbo"]
    guard{"重入守卫<br/>_at_is_processing?"}

    turbo{{"turbo 或 delay <= 0"}}
    sync["_ShopAutomation.run_shop_decision_sync<br/>同步一口气跑完"]
    chain["_at_chain_start<br/>启动 Timer 链逐步驱动"]

    finalize["_at_finalize_shop_decision<br/>退出临界区 + 切 Y/F + 可能进波"]

    ready --> trigger
    trigger --> auto
    auto --> run
    manual --> run
    run --> guard
    guard -- 是 --> done1([直接返回])
    guard -- 否 --> turbo
    turbo -- 是 --> sync --> finalize
    turbo -- 否(delay>0) --> chain --> finalize

    classDef entryMethod fill:#e1f5ff,stroke:#0288d1
    classDef orchMethod fill:#fff4e1,stroke:#f57c00
    classDef decision fill:#fff9c4,stroke:#f9a825

    class ready,trigger,auto,manual,run,finalize entryMethod
    class sync,chain orchMethod
    class guard,turbo decision
```

---

## 三、turbo 同步路径

编排层 `shop_automation.gd` 的 turbo 急速路径,用 `while+for` 嵌套循环一口气跑完,无延迟。

- **`run_shop_decision_sync(ui_adapter, player_index) -> Dictionary`**:turbo 同步入口,返回 summary 字典。
- **`_run_one_round(ui_adapter, player_index) -> Dictionary`**:运行一轮,`for entry` 逐个调 `process_one_entry`。
- **`_has_manual(rd)` / `_all_unpurchased_insufficient(rd)`**:停止条件判断。
- **`_can_reroll(ui_adapter, player_index, reroll_spent) -> Dictionary`**:客观能否 reroll。

```mermaid
flowchart TD
    start([run_shop_decision_sync])
    round["_run_one_round<br/>读 entries + for entry 调 process_one_entry"]
    accum["累计本轮统计进 session"]

    chk_manual{"_has_manual(rd)?"}
    chk_stop{"全买不起 OR<br/>_can_reroll 不可?"}
    do_reroll["at_reroll_shop(player_index, true)<br/>执行 reroll, reroll_spent += price"]
    chk_auto{"自动化开关<br/>仍开启?"}

    summary[["build_summary<br/>返回 {purchases, locks, ...}"]]

    start --> round --> accum
    accum --> chk_manual
    chk_manual -- 是,出现 manual --> summary
    chk_manual -- 否 --> chk_stop
    chk_stop -- 是 --> set_auto["按 auto_start_wave<br/>设 should_auto_start"] --> summary
    chk_stop -- 否,可刷新 --> do_reroll --> chk_auto
    chk_auto -- 否,只跑一轮 --> summary
    chk_auto -- 是 --> round

    classDef orchMethod fill:#fff4e1,stroke:#f57c00
    classDef decision fill:#fff9c4,stroke:#f9a825
    classDef terminal fill:#e8f5e9,stroke:#388e3c

    class round,accum,do_reroll,set_auto orchMethod
    class chk_manual,chk_stop,chk_auto decision
    class summary terminal
```

---

## 四、非 turbo Timer 链状态机

非 turbo 模式把同步 `while+for` 循环展开为 Timer 链状态机。链状态全在 base_shop 的 `_at_chain_*` 字段里,Timer 默认 `PAUSE_MODE_STOP`,ESC 暂停即冻结。

**链状态字段**:`_at_chain_active` / `_at_chain_player_index` / `_at_chain_cfg` / `_at_chain_timer` / `_at_chain_entries` / `_at_chain_entry_idx` / `_at_chain_rd` / `_at_chain_totals`。

```mermaid
stateDiagram-v2
    [*] --> _at_chain_start : 启动链
    _at_chain_start --> _at_chain_begin_round : 初始化链状态

    state "轮次处理" as Round {
        _at_chain_begin_round --> _at_chain_process_current_entry : rounds+1, 重读 entries
        _at_chain_process_current_entry --> _at_chain_advance : purchase/lock 返回 true
        _at_chain_advance --> _at_chain_step : Timer 延迟回调
        _at_chain_step --> _at_chain_process_current_entry : 处理下一个 entry
        _at_chain_process_current_entry --> _at_chain_end_round : entry 耗尽
    }

    _at_chain_end_round --> decide : decide_round_outcome 判断

    decide --> _at_chain_finish : stop_manual
    decide --> _at_chain_finish : stop_no_reroll
    decide --> _at_chain_do_reroll : reroll

    _at_chain_do_reroll --> _at_chain_advance_after_reroll : execute_reroll, reroll_spent+=price
    _at_chain_advance_after_reroll --> _at_chain_post_reroll_decide : Timer 延迟回调

    _at_chain_post_reroll_decide --> _at_chain_begin_round : 自动化开(进下一轮)
    _at_chain_post_reroll_decide --> _at_chain_finish : 自动化关(只推进一轮)

    _at_chain_finish --> [*] : 构造 summary + 清理链状态

    note right of _at_chain_process_current_entry
        while 同步连续处理 entry
        manual/skip 返回 false 不延迟, 同帧继续
        purchase/lock 返回 true 才起 Timer 让 UI 渲染
    end note

    note right of _at_chain_finish
        调 _at_finalize_shop_decision
        turbo 同步路径与链结束路径共用
    end note
```

**turbo 与非 turbo 的关键差异**:
- turbo:`run_shop_decision_sync()` 同步 `while+for` 跑完,无延迟,直接返回 summary。
- 非 turbo:Timer 链逐步驱动,每步间 `decision_step_delay` 延迟让 UI 渲染可见;链状态在 `_at_chain_*` 字段,无协程 yield 卡死风险,ESC 暂停自然冻结。

---

## 五、单 entry 决策 + 执行(两路径共用原子)

这是 turbo 与非 turbo 共用的核心原子方法。意图(DECISION_*)与事实(RESULT_*)词形刻意不同,防止混用。

- **`process_one_entry(ui_adapter, player_index, entry, rd) -> bool`**:单 entry 决策+执行+记账,返回是否需要 UI 健顿。
- **`decide_shop_entry(entry, player_index) -> Dictionary`**:纯意图决策,返回 `{intent}`。
- **`at_execute_action(intent, shop_item, player_index) -> String`**:把意图翻译为执行事实。

```mermaid
flowchart TD
    entry([entry = shop_item, item_data, item_id])
    guard["_Data.is_shop_item_active<br/>守卫, 失效返回 false"]
    decide["_ItemDecider.decide_shop_entry<br/>返回 decision, 取 intent"]

    intent{{"intent ∈<br/>purchase / lock / manual / skip"}}

    exec["ui_adapter.at_execute_action<br/>把意图翻译为执行事实"]

    subgraph 执行器[base_shop 执行器]
        purchase["_at_purchase_item<br/>emit buy_button_pressed"]
        lock["_at_lock_item<br/>change_lock_status(true)"]
        manual_act["无 UI 动作"]
        skip_act["无 UI 动作"]
    end

    result{{"executed ∈ RESULT_*<br/>purchased / locked / manual / skipped"}}

    fact["重读 currency/price<br/>自算 is_affordable"]
    record["rd.actions.append + 记账<br/>purchases/locks/manuals/skips += 1"]

    done([返回: purchase/lock=true, manual/skip=false])

    entry --> guard
    guard -- 失效 --> done
    guard -- 有效 --> decide --> intent
    intent -- purchase --> purchase
    intent -- lock --> lock
    intent -- manual --> manual_act
    intent -- skip --> skip_act
    purchase --> result
    lock --> result
    manual_act --> result
    skip_act --> result
    result --> fact --> record --> done

    classDef intentNode fill:#f3e5f5,stroke:#7b1fa2
    classDef resultNode fill:#e8f5e9,stroke:#388e3c
    classDef orchMethod fill:#fff4e1,stroke:#f57c00
    classDef execMethod fill:#e1f5ff,stroke:#0288d1

    class intent intentNode
    class result resultNode
    class decide,fact,record orchMethod
    class purchase,lock,manual_act,skip_act execMethod
```

`★ 关键设计`:`is_affordable`(客观可执行性)不属于决策层,由 `process_one_entry` 在循环里重读自算,与决策正交--它反映前序 purchase 扣减后的最新余额,供 reroll 停止条件使用。

---

## 六、决策层两阶段判断

`decide_shop_entry` 的两阶段结构。阶段 1 是类型特定规则,阶段 2 是商店通用规则(仅对 get 生效)。

```mermaid
flowchart TD
    start([decide_shop_entry])
    classify{物品类型?}

    subgraph 阶段1[阶段 1: 类型特定规则]
        weapon["_resolve_weapon_action<br/>min_tier 门槛 -> 武器规则 -> 类别规则"]
        item["_resolve_item_action<br/>翻译 shop_action: manual/reject/get/<br/>lock_until_cursed/cursed_only"]
        special["manual 且已被手动锁定<br/>-> 转 skip"]
    end

    stage1_out{阶段 1 结果<br/>是 get 吗?}

    subgraph 阶段2[阶段 2: 商店通用规则, 仅 get]
        limit["_Data.is_at_limit<br/>限购检查"]
        threshold["_ThresholdGate.should_reject_item<br/>阈值 gate"]
        budget["_hits_budget_wall<br/>min_gold_balance / item_price_threshold"]
    end

    purchase([purchase 意图])
    other([skip / manual / lock 意图])

    start --> classify
    classify -- 武器 --> weapon
    classify -- 物品 --> item
    weapon --> special
    item --> special
    special --> stage1_out
    stage1_out -- 否, 已是 skip/manual/lock --> other
    stage1_out -- 是 get --> limit
    limit -- 超限购 --> other
    limit -- 未超 --> threshold
    threshold -- 触达阈值 --> other
    threshold -- 未触达 --> budget
    budget -- 撞预算墙 --> other
    budget -- 通过 --> purchase

    classDef stage1Method fill:#f3e5f5,stroke:#7b1fa2
    classDef stage2Method fill:#fce4ec,stroke:#c2185b
    classDef decision fill:#fff9c4,stroke:#f9a825
    classDef terminal fill:#e8f5e9,stroke:#388e3c

    class weapon,item,special stage1Method
    class limit,threshold,budget stage2Method
    class classify,stage1_out decision
    class purchase,other terminal
```

**阶段 1 配置层调用**(带默认值回退):

```mermaid
flowchart LR
    subgraph 武器规则回退链
        w1["cfg.get_weapon_rule(weapon_id)<br/>未配置 -> follow_set_rule"]
        w2["cfg.get_weapon_category_rule(set_id)<br/>未配置 -> manual"]
        w1 -- follow_set_rule --> w2
    end
    subgraph 物品规则回退链
        i1["cfg.get_item_rule(item_id)<br/>未配置 -> DEFAULT_ITEM_RULE<br/>{shop_action: manual, chest_action: manual}"]
    end
    cfg_min["cfg.get_weapon_min_tier<br/>默认 0"]

    classDef configCall fill:#f5f5f5,stroke:#616161
    class w1,w2,i1,cfg_min configCall
```

**阶段 2 阈值 gate**(`threshold_gate.should_reject_item`):

```mermaid
flowchart TD
    collect["_collect_related_stats<br/>只认 stat_* 直接修改 effect"]
    empty{有相关 stat?}
    allornone{所有 stat 都触达阈值?}
    check["逐个 cfg.get_threshold(stat_key)<br/>_is_threshold_reached:<br/>upper: current>=limit<br/>lower: current<limit<br/>unlimited: false"]
    reject([reject=true, 全或无])
    pass([reject=false])

    collect --> empty
    empty -- 无 --> pass
    empty -- 有 --> allornone
    allornone -- 查每个阈值 --> check
    check -- 任一未达 --> pass
    check -- 全达 --> reject

    classDef decision fill:#fff9c4,stroke:#f9a825
    classDef terminal fill:#e8f5e9,stroke:#388e3c
    classDef method fill:#fce4ec,stroke:#c2185b
    class collect,check method
    class empty,allornone decision
    class reject,pass terminal
```

---

## 七、reroll 判断与执行

一轮结束后判断停止 / reroll / 进波。自动循环 reroll 与手动 reroll 走不同路径。

- **`decide_round_outcome(...) -> Dictionary`**:返回 `{action: stop_manual | stop_no_reroll | reroll, ...}`。
- **`at_reroll_shop(player_index, _internal=true)`**:自动循环内部调用,走 `.super` 绕过覆写拦截。
- **`_on_RerollButton_pressed(player_index)`(覆写)**:拦截手动 reroll,链进行中拦截一切 pressed 防跨帧插队。

```mermaid
flowchart TD
    endround([_at_chain_end_round / turbo 停止判断])
    decide["decide_round_outcome"]
    outcome{{"outcome.action"}}

    stop_manual["stop_manual<br/>出现 manual, 不进波"]
    stop_noreroll["stop_no_reroll<br/>全买不起或不可 reroll<br/>按 auto_start 决定进波"]
    reroll["reroll"]

    canreroll["_can_reroll 判断条件:<br/>1. gold >= price<br/>2. price <= reroll_budget(0=不限)<br/>3. 锁定项 < NB_SHOP_ITEMS(未全锁死)"]

    finish([_at_chain_finish / build_summary])

    endround --> decide --> outcome
    outcome -- stop_manual --> finish
    outcome -- stop_no_reroll --> finish
    outcome -- reroll --> canreroll

    subgraph 双路径执行[双路径 reroll 执行]
        auto_path["自动循环(at_reroll_shop _internal=true)<br/>-> ._on_RerollButton_pressed(super)<br/>绕过覆写拦截"]
        manual_path["手动 F/鼠标(_on_RerollButton_pressed 覆写)<br/>链进行中拦截一切 pressed<br/>防跨帧插队换掉链中商品"]
    end

    canreroll -- 自动循环 --> auto_path
    canreroll -- 手动触发 --> manual_path

    classDef orchMethod fill:#fff4e1,stroke:#f57c00
    classDef execMethod fill:#e1f5ff,stroke:#0288d1
    classDef decision fill:#fff9c4,stroke:#f9a825
    classDef terminal fill:#e8f5e9,stroke:#388e3c

    class decide,canreroll orchMethod
    class auto_path,manual_path execMethod
    class outcome decision
    class finish terminal
```

---

## 八、升级决策线(独立线)

升级线是 4 选 1,结构与商店线对齐但决策逻辑内联在 `upgrade_automation.gd`,不依赖 `item_decider.gd`。

- **`run_upgrade_decision(ui_adapter, player_index, force) -> Dictionary`**:升级决策唯一入口,reroll 循环 + fallback。
- **`_decide_one(options, cfg, player_index, round_num) -> int`**:对 4 个候选做一次决策,5 步过滤+排序。

```mermaid
flowchart TD
    entry([run_upgrade_decision])
    chk_enabled{"force=false 且<br/>自动化关闭?"}
    loop{"while true"}
    cand["at_get_upgrade_candidates<br/>读候选, 空则 break"]

    decide["_decide_one 5 步决策<br/>返回 idx 或 NO_PICK=-1"]

    subgraph 五步[5 步过滤+排序]
        sA["[A] tier 过滤<br/>tier >= min_tier(-1 不限)"]
        sB["[B] forbid 过滤<br/>任一 stat 在 forbid_stats 中"]
        sC["[C] 阈值过滤<br/>复用 _Gate.should_reject_item"]
        sD["[D] 品质排序<br/>quality_first: tier 降序"]
        sE["[E] 优先级排序<br/>stat_priority 在 top tier 内排序"]
        sA --> sB --> sC --> sD --> sE
    end

    picked{idx != NO_PICK?}
    choose["at_choose_upgrade<br/>选中, chosen=true"]
    canreroll{"_can_reroll 可刷新?"}
    doreroll["at_reroll_upgrade<br/>reroll_spent += price"]
    wait["非 turbo: at_wait_before_next_decision<br/>延迟等待"]
    switch{"刷新后自动化<br/>仍开启?"}
    fallback["at_fallback_upgrade<br/>ignore_forbid_on_stuck 选品质最优"]

    summary[["返回 {chosen, rounds,<br/>reroll_spent, fallback_used}"]]

    entry --> chk_enabled
    chk_enabled -- 是 --> summary
    chk_enabled -- 否 --> loop
    loop --> cand
    cand -- 空 --> fbcheck{未选中且非开关关闭?}
    cand -- 有 --> decide
    decide --> 五步
    五步 --> picked
    picked -- 是 --> choose --> summary
    picked -- 否 --> canreroll
    canreroll -- 否 --> fbcheck
    canreroll -- 是 --> doreroll --> wait --> switch
    switch -- 关, stopped_by_switch --> summary
    switch -- 开 --> loop
    fbcheck -- 是 --> fallback --> summary
    fbcheck -- 否 --> summary

    classDef orchMethod fill:#fff4e1,stroke:#f57c00
    classDef stepMethod fill:#f3e5f5,stroke:#7b1fa2
    classDef execMethod fill:#e1f5ff,stroke:#0288d1
    classDef decision fill:#fff9c4,stroke:#f9a825
    classDef terminal fill:#e8f5e9,stroke:#388e3c

    class cand,decide,choose,doreroll,wait,fallback orchMethod
    class sA,sB,sC,sD,sE stepMethod
    class chk_enabled,loop,picked,canreroll,switch,fbcheck decision
    class summary terminal
```

**turbo / 非 turbo 差异(升级线)**:turbo 循环内无延迟连续跑;非 turbo 每轮 reroll 后 `at_wait_before_next_decision()` 调度 `decision_step_delay` 延迟。升级线没有像商店线那样用 Timer 链状态机,而是同步循环 + 延迟等待。

---

## 九、配置层回退速查

遵循 `CLAUDE.md` 第 4 节原则:**配置默认值由 config 层返回,外部不做回退判断**。

| 方法 | 返回 | 未配置时默认值 | 用途 |
|---|---|---|---|
| `is_shop_automation_enabled()` | `bool` | `true` | 商店自动化开关 |
| `is_upgrade_automation_enabled()` | `bool` | `false` | 升级自动化开关 |
| `is_turbo_mode()` | `bool` | `false` | turbo 同步路径开关 |
| `get_general()` | `Dictionary` | 各字段独立回退 | `min_gold_balance`(0)、`item_price_threshold`(0)、`reroll_budget`(0=不限)、`auto_start_wave`(false)、`shop_respect_thresholds`(true)、`turbo_mode`(false)、`decision_step_delay`(0.3) |
| `get_item_rule(item_id)` | `Dictionary` | `DEFAULT_ITEM_RULE = {shop_action: "manual", chest_action: "manual"}` | 物品规则,非法值也回退默认 |
| `get_weapon_rule(weapon_id)` | `String` | `"follow_set_rule"` | 武器自身规则 |
| `get_weapon_category_rule(set_id)` | `String` | `"manual"` | 武器类别规则 |
| `get_weapon_min_tier()` | `int` | `0` | 武器最低 tier 门槛 |
| `get_threshold(stat_key)` | `Dictionary` | `DEFAULT_THRESHOLD = {mode: "unlimited", value: 0}` | 阈值,unlimited 不拒绝 |
| `get_upgrade_config()` | `Dictionary` | 各字段回退 | `min_tier`(-1 不限)、`quality_first`、`ignore_forbid_on_stuck`(true)、`respect_thresholds`(true) |
| `get_upgrade_forbid_stats()` | `Array` | `[]` | 升级禁止属性 |
| `get_upgrade_priority()` | `Array` | `[]` | 升级优先级 |

---

## 十、关键设计要点

`★ Insight ─────────────────────────────────────`

1. **意图与事实分离**:`decision_result.gd`(DECISION_*,决策意图)与 `execute_result.gd`(RESULT_*,执行事实)词形不同(`purchase` vs `purchased`),decider 只输出意图,执行器返回事实,编排层用事实记账。

2. **is_affordable 与决策正交**:decider 只为预算墙读 currency/price,客观可执行性 `is_affordable` 由 `shop_automation` 在循环里重读自算,供 reroll 停止条件用(反映前序 purchase 扣减后的最新余额)。

3. **配置回退收拢 config 层**:`get_item_rule` / `get_weapon_rule` / `get_threshold` 等都在内部完成完整回退链,外部直接拿最终值,不做 `if null` 判断。默认值变更只需改 config 一处。

4. **turbo 同步 vs 非 turbo Timer 链**:turbo 用 `while+for` 一口气跑完;非 turbo 用 Timer 链状态机逐步驱动,链状态在 `_at_chain_*` 字段,ESC 暂停自然冻结,无协程 yield 风险。两条路径共用 `process_one_entry` / `decide_shop_entry` / `at_execute_action` 等原子方法。

5. **reroll 拦截双路径**:自动循环 reroll 走 `at_reroll_shop` -> `.super`(绕过覆写拦截);手动 F/鼠标 reroll 走覆写的 `_on_RerollButton_pressed`(链进行中拦截一切 pressed,防跨帧插队把链中商品换掉)。

6. **升级线独立**:4 选 1,决策内联在 `upgrade_automation._decide_one`(5 步:tier/forbid/阈值/品质/优先级),无 manual 停止条件,有 fallback(`ignore_forbid_on_stuck` 选品质最优),turbo/非 turbo 差异仅在 reroll 后是否等待。
`─────────────────────────────────────────────────`
