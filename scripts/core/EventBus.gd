extends Node
## 事件总线 — 全局信号分发中心
## 所有跨系统通信通过此总线，避免直接引用

signal resources_changed(faction: String)
signal unit_selected(unit)
signal units_selected(units: Array)
signal unit_deselected()
signal building_selected(building)
signal building_deselected()
signal building_placed(building)
signal building_destroyed(building)
signal unit_died(unit)
signal general_died(general)
signal government_upgraded(faction: String, new_level: int)
signal tech_researched(faction: String, tech_id: String)
signal unit_trained(faction: String, unit_id: String)
signal village_captured(faction: String, village)
signal horse_captured(faction: String, horse)
signal diplomatic_action(action: String, from_faction: String, to_faction: String)
signal season_changed(new_season: String)
signal morale_changed(faction: String, new_morale: float)
signal war_declared(attacker: String, defender: String)
signal victory(faction: String)
signal defeat(faction: String)
signal float_text(text: String, position: Vector3, color: Color)
signal rally_point_set(building, position: Vector3)


