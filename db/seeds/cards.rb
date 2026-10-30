nations = {
  ussr: Nation.find_by!(code: "ussr"),
  germany: Nation.find_by!(code: "germany"),
  usa: Nation.find_by!(code: "usa")
}

headquarters = [
  {
    code: "germany_headquarters_operation_weiß",
    nation: nations[:germany],
    name: "Operation „Weiß“",
    weight: 1,
    hp: 16,
    firepower: 2,
    fuel: 4
  },
  {
    code: "usa_headquarters_second_front",
    nation: nations[:usa],
    name: "Second front",
    weight: 1,
    hp: 17,
    firepower: 1,
    fuel: 6
  },
  {
    code: "ussr_headquarters_west_front",
    nation: nations[:ussr],
    name: "Західний фронт",
    weight: 1,
    hp: 19,
    firepower: 1,
    fuel: 5
  }
]

# Типи техніки визначають рух і спеціальні правила GameEngine.
# Усі карти техніки мають attack_range = 1.
movement = {
  "light_tank" => { movement_type: "orthogonal", movement_count: 2 },
  "medium_tank" => { movement_type: "diagonal", movement_count: 1 },
  "heavy_tank" => { movement_type: "orthogonal", movement_count: 1 },
  "tank_destroyer" => { movement_type: "orthogonal", movement_count: 1 },
  "artillery" => { movement_type: "orthogonal", movement_count: 1 }
}

# code, nation, name, type, weight, price, hp, firepower, fuel
technique_rows = [
  ["germany_pz_ii", :germany, "Pz.II", "light_tank", 1, 1, 1, 1, 0],
  ["germany_sd_222", :germany, "Sd.222", "light_tank", 2, 2, 1, 2, 0],
  ["germany_pz_iii_a_h", :germany, "Pz.III Ausf. A-H", "medium_tank", 3, 2, 3, 2, 0],
  ["germany_pz_iv_a_f1", :germany, "Pz.IV Ausf. A-F1", "medium_tank", 4, 4, 4, 1, 1],
  ["germany_jagdpanther_38a_hetzer", :germany, "Jagdpanther 38(A) Hetzer", "tank_destroyer", 4, 3, 4, 2, 1],
  ["germany_jagdpanther_iv", :germany, "Jagdpanther IV", "tank_destroyer", 5, 4, 5, 2, 1],
  ["germany_jagdpanther", :germany, "Jagdpanther", "tank_destroyer", 6, 5, 6, 2, 2],
  ["germany_tiger_i", :germany, "Pz.VI Tiger I", "heavy_tank", 7, 6, 7, 2, 1],
  ["germany_sturmpanzer_iv_brummbar", :germany, "Sturmpanzer IV Brummbar", "artillery", 8, 5, 4, 2, 1],

  ["usa_m3_stuart", :usa, "M3 Stuart", "light_tank", 1, 3, 1, 1, 0],
  ["usa_m8_greyhound", :usa, "M8 Greyhound", "light_tank", 2, 4, 2, 1, 1],
  ["usa_m3_lee_grant", :usa, "M3 Lee/Grant", "medium_tank", 3, 4, 3, 1, 1],
  ["usa_m4_sherman", :usa, "M4 Sherman", "medium_tank", 4, 5, 3, 2, 1],
  ["usa_m4a3e8_easy_eight", :usa, "M4A3E8 Easy Eight", "medium_tank", 4, 6, 4, 2, 0],
  ["usa_m4a3e2_jumbo", :usa, "M4A3E2 Jumbo", "medium_tank", 5, 6, 4, 2, 1],
  ["usa_m10_wolverine", :usa, "M10 Wolverine", "tank_destroyer", 6, 7, 5, 2, 1],
  ["usa_m26_pershing", :usa, "M26 Pershing", "heavy_tank", 7, 7, 5, 2, 1],
  ["usa_m8_hmc_scott", :usa, "M8 HMC Scott", "artillery", 8, 8, 3, 1, 1],

  ["ussr_bt_7", :ussr, "БТ-7", "light_tank", 1, 2, 1, 1, 0],
  ["ussr_t_60", :ussr, "Т-60", "light_tank", 2, 3, 2, 1, 1],
  ["ussr_t_34", :ussr, "Т-34", "medium_tank", 3, 4, 3, 1, 1],
  ["ussr_t_34_76", :ussr, "Т-34-76", "medium_tank", 4, 5, 4, 2, 1],
  ["ussr_su_85", :ussr, "СУ-85", "tank_destroyer", 4, 5, 5, 3, 0],
  ["ussr_su_100", :ussr, "СУ-100", "tank_destroyer", 6, 6, 5, 2, 1],
  ["ussr_t_35", :ussr, "T-35", "heavy_tank", 5, 5, 6, 1, 1],
  ["ussr_kv_1", :ussr, "КВ-1", "heavy_tank", 7, 6, 6, 2, 1],
  ["ussr_su_76m", :ussr, "СУ-76М", "artillery", 8, 6, 3, 1, 0]
]

techniques = technique_rows.map do |code, nation_code, name, technique_type, weight, price, hp, firepower, fuel|
  {
    code: code,
    nation: nations.fetch(nation_code),
    name: name,
    weight: weight,
    price: price,
    technique_type: technique_type,
    attack_range: 1,
    **movement.fetch(technique_type),
    hp: hp,
    firepower: firepower,
    fuel: fuel
  }
end

orders = [
  { code: "germany_tocnyj_postril", nation: nations[:germany], name: "Точний постріл", weight: 5, price: 4 },
  { code: "germany_radioperehoplena", nation: nations[:germany], name: "Радіоперехоплення", weight: 4, price: 2 },
  { code: "usa_lend_liz", nation: nations[:usa], name: "Ленд-ліз", weight: 3, price: 2 },
  { code: "usa_vognevij_nalit", nation: nations[:usa], name: "Вогневий наліт", weight: 3, price: 3 },
  { code: "ussr_zalp_katyushi", nation: nations[:ussr], name: "Залп „Катюші“", weight: 5, price: 4 },
  { code: "ussr_popovnena", nation: nations[:ussr], name: "Поповнення", weight: 3, price: 2 }
]

platoons = [
  { code: "germany_grenaderskij_vzvod", nation: nations[:germany], name: "Гренадерський взвод", weight: 4, price: 4, hp: 6, firepower: 2, armor: 0, fuel: 0 },
  { code: "germany_betone_ukripleniy", nation: nations[:germany], name: "Бетонне укріплення", weight: 3, price: 3, hp: 5, firepower: 0, armor: 2, fuel: 0 },
  { code: "usa_inzhenernij_vzvod", nation: nations[:usa], name: "Инженерний взвод", weight: 3, price: 4, hp: 5, firepower: 0, armor: 2, fuel: 0 },
  { code: "usa_vzvod_bazukometnikiv", nation: nations[:usa], name: "Взвод базукометників", weight: 5, price: 4, hp: 4, firepower: 1, armor: 0, fuel: 1 },
  { code: "ussr_strileckyj_vzvod", nation: nations[:ussr], name: "Стрелецький взвод", weight: 4, price: 4, hp: 4, firepower: 1, armor: 0, fuel: 0 },
  { code: "ussr_dot", nation: nations[:ussr], name: "ДОТ", weight: 4, price: 3, hp: 6, firepower: 0, armor: 2, fuel: 0 }
]

headquarters.each do |attributes|
  card = Card.find_or_initialize_by(code: attributes[:code])
  card.assign_attributes(
    nation: attributes[:nation], name: attributes[:name],
    card_type: "headquarters", weight: attributes[:weight], price: nil
    )
  card.save!

  headquarters_card = Headquarters.find_or_initialize_by(card: card)
  headquarters_card.assign_attributes(
    firepower: attributes[:firepower], hp: attributes[:hp], fuel: attributes[:fuel]
    )
  headquarters_card.save!
end

techniques.each do |attributes|
  card = Card.find_or_initialize_by(code: attributes[:code])
  card.assign_attributes(
    nation: attributes[:nation], name: attributes[:name],
    card_type: "technique", weight: attributes[:weight], price: attributes[:price]
    )
  card.save!

  technique = Technique.find_or_initialize_by(card: card)
  technique.assign_attributes(
    technique_type: attributes[:technique_type],
    attack_range: attributes[:attack_range],
    movement_count: attributes[:movement_count],
    movement_type: attributes[:movement_type],
    firepower: attributes[:firepower], hp: attributes[:hp], fuel: attributes[:fuel]
    )
  technique.save!
end

orders.each do |attributes|
  card = Card.find_or_initialize_by(code: attributes[:code])
  card.assign_attributes(
    nation: attributes[:nation], name: attributes[:name],
    card_type: "order", weight: attributes[:weight], price: attributes[:price]
    )
  card.save!
end

platoons.each do |attributes|
  card = Card.find_or_initialize_by(code: attributes[:code])
  card.assign_attributes(
    nation: attributes[:nation], name: attributes[:name],
    card_type: "platoon", weight: attributes[:weight], price: attributes[:price]
    )
  card.save!

  platoon = Platoon.find_or_initialize_by(card: card)
  platoon.assign_attributes(
    firepower: attributes[:firepower], hp: attributes[:hp],
    armor: attributes[:armor], fuel: attributes[:fuel]
    )
  platoon.save!
end
