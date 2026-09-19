nations = {
  ussr: Nation.find_by!(code: "ussr"),
  germany: Nation.find_by!(code: "germany"),
  usa: Nation.find_by!(code: "usa")
}

headquarters = [
  {
    code: "germany_headquarters",
    nation: nations[:germany],
    name: "Штаб Германии",
    weight: 1,
    firepower: 2,
    hp: 16,
    fuel: 4
  },
  {
    code: "usa_headquarters",
    nation: nations[:usa],
    name: "Штаб США",
    weight: 1,
    firepower: 1,
    hp: 17,
    fuel: 6
  },
  {
    code: "ussr_headquarters",
    nation: nations[:ussr],
    name: "Штаб СССР",
    weight: 1,
    firepower: 1,
    hp: 19,
    fuel: 5
  }
]

techniques = [
  {
    code: "germany_pz_ii_l_luchs",
    nation: nations[:germany],
    name: "Pz.II Ausf. L «Luchs»",
    weight: 1,
    price: 2,
    technique_type: "light_tank",
    attack_range: 1,
    movement_count: 2,
    movement_type: "orthogonal",
    firepower: 2,
    hp: 4,
    fuel: 2
  },
  {
    code: "germany_pz_iii_j",
    nation: nations[:germany],
    name: "Pz.III Ausf. J",
    weight: 1,
    price: 3,
    technique_type: "medium_tank",
    attack_range: 1,
    movement_count: 1,
    movement_type: "diagonal",
    firepower: 3,
    hp: 6,
    fuel: 1
  },
  {
    code: "germany_pz_iv_h",
    nation: nations[:germany],
    name: "Pz.IV Ausf. H",
    weight: 2,
    price: 4,
    technique_type: "medium_tank",
    attack_range: 1,
    movement_count: 1,
    movement_type: "diagonal",
    firepower: 4,
    hp: 8,
    fuel: 1
  },
  {
    code: "germany_tiger_i",
    nation: nations[:germany],
    name: "Pz.VI Tiger I",
    weight: 4,
    price: 6,
    technique_type: "heavy_tank",
    attack_range: 1,
    movement_count: 1,
    movement_type: "orthogonal",
    firepower: 5,
    hp: 12,
    fuel: 1
  },
  {
    code: "germany_jagdpanther",
    nation: nations[:germany],
    name: "Jagdpanther",
    weight: 3,
    price: 5,
    technique_type: "tank_destroyer",
    attack_range: 1,
    movement_count: 1,
    movement_type: "orthogonal",
    firepower: 4,
    hp: 8,
    fuel: 1
  },
  {
    code: "germany_hummel",
    nation: nations[:germany],
    name: "Hummel",
    weight: 2,
    price: 4,
    technique_type: "artillery",
    attack_range: 1,
    movement_count: 1,
    movement_type: "orthogonal",
    firepower: 3,
    hp: 5,
    fuel: 2
  },

  {
    code: "usa_m3_stuart",
    nation: nations[:usa],
    name: "M3 Stuart",
    weight: 1,
    price: 2,
    technique_type: "light_tank",
    attack_range: 1,
    movement_count: 2,
    movement_type: "orthogonal",
    firepower: 2,
    hp: 4,
    fuel: 2
  },
  {
    code: "usa_m4_sherman",
    nation: nations[:usa],
    name: "M4 Sherman",
    weight: 2,
    price: 4,
    technique_type: "medium_tank",
    attack_range: 1,
    movement_count: 1,
    movement_type: "diagonal",
    firepower: 2,
    hp: 6,
    fuel: 2
  },
  {
    code: "usa_m4a3e8_easy_eight",
    nation: nations[:usa],
    name: "M4A3E8 «Easy Eight»",
    weight: 3,
    price: 5,
    technique_type: "medium_tank",
    attack_range: 1,
    movement_count: 1,
    movement_type: "diagonal",
    firepower: 4,
    hp: 8,
    fuel: 1
  },
  {
    code: "usa_m26_pershing",
    nation: nations[:usa],
    name: "M26 Pershing",
    weight: 3,
    price: 6,
    technique_type: "heavy_tank",
    attack_range: 1,
    movement_count: 1,
    movement_type: "orthogonal",
    firepower: 4,
    hp: 11,
    fuel: 1
  },
  {
    code: "usa_m18_hellcat",
    nation: nations[:usa],
    name: "M18 Hellcat",
    weight: 2,
    price: 6,
    technique_type: "tank_destroyer",
    attack_range: 1,
    movement_count: 1,
    movement_type: "orthogonal",
    firepower: 4,
    hp: 5,
    fuel: 2
  },
  {
    code: "usa_m7_priest",
    nation: nations[:usa],
    name: "M7 Priest",
    weight: 2,
    price: 4,
    technique_type: "artillery",
    attack_range: 1,
    movement_count: 1,
    movement_type: "orthogonal",
    firepower: 2,
    hp: 5,
    fuel: 1
  },

  {
    code: "ussr_t_70",
    nation: nations[:ussr],
    name: "Т-70",
    weight: 1,
    price: 2,
    technique_type: "light_tank",
    attack_range: 1,
    movement_count: 2,
    movement_type: "orthogonal",
    firepower: 1,
    hp: 5,
    fuel: 2
  },
  {
    code: "ussr_t_34",
    nation: nations[:ussr],
    name: "Т-34",
    weight: 2,
    price: 4,
    technique_type: "medium_tank",
    attack_range: 1,
    movement_count: 1,
    movement_type: "diagonal",
    firepower: 2,
    hp: 7,
    fuel: 2
  },
  {
    code: "ussr_t_34_85",
    nation: nations[:ussr],
    name: "Т-34-85",
    weight: 3,
    price: 6,
    technique_type: "medium_tank",
    attack_range: 1,
    movement_count: 1,
    movement_type: "diagonal",
    firepower: 3,
    hp: 8,
    fuel: 1
  },
  {
    code: "ussr_is_2",
    nation: nations[:ussr],
    name: "ИС-2",
    weight: 3,
    price: 6,
    technique_type: "heavy_tank",
    attack_range: 1,
    movement_count: 1,
    movement_type: "orthogonal",
    firepower: 3,
    hp: 12,
    fuel: 1
  },
  {
    code: "ussr_su_100",
    nation: nations[:ussr],
    name: "СУ-100",
    weight: 3,
    price: 5,
    technique_type: "tank_destroyer",
    attack_range: 1,
    movement_count: 1,
    movement_type: "orthogonal",
    firepower: 3,
    hp: 6,
    fuel: 1
  },
  {
    code: "ussr_su_26",
    nation: nations[:ussr],
    name: "СУ-26",
    weight: 2,
    price: 6,
    technique_type: "artillery",
    attack_range: 1,
    movement_count: 1,
    movement_type: "orthogonal",
    firepower: 2,
    hp: 7,
    fuel: 2
  }
]

orders = [
  {
    code: "germany_tocnyj_vystrel",
    nation: nations[:germany],
    name: "«Точный выстрел»",
    weight: 3,
    price: 4
  },
  {
    code: "germany_radioperekhvat",
    nation: nations[:germany],
    name: "«Радиоперехват»",
    weight: 2,
    price: 3
  },
  {
    code: "usa_lend_liz",
    nation: nations[:usa],
    name: "«Ленд-лиз»",
    weight: 1,
    price: 2
  },
  {
    code: "usa_ognevoj_nalyot",
    nation: nations[:usa],
    name: "«Огневой налёт»",
    weight: 1,
    price: 2
  },
  {
    code: "ussr_zalp_katyushi",
    nation: nations[:ussr],
    name: "«Залп „Катюши“»",
    weight: 2,
    price: 3
  },
  {
    code: "ussr_popolnenie",
    nation: nations[:ussr],
    name: "«Пополнение»",
    weight: 2,
    price: 2
  }
]

platoons = [
  {
    code: "germany_grenaderskij_vzvod",
    nation: nations[:germany],
    name: "Гренадёрский взвод",
    weight: 2,
    price: 3,
    firepower: 2,
    hp: 6,
    armor: 0,
    fuel: 0
  },
  {
    code: "germany_flak_88",
    nation: nations[:germany],
    name: "Расчёт Flak 88",
    weight: 3,
    price: 3,
    firepower: 0,
    hp: 5,
    armor: 2,
    fuel: 0
  },
  {
    code: "usa_inzhenernyj_vzvod",
    nation: nations[:usa],
    name: "Инженерный взвод",
    weight: 3,
    price: 4,
    firepower: 0,
    hp: 5,
    armor: 3,
    fuel: 0
  },
  {
    code: "usa_vzvod_bazukometchikov",
    nation: nations[:usa],
    name: "Взвод базукометчиков",
    weight: 3,
    price: 4,
    firepower: 2,
    hp: 4,
    armor: 0,
    fuel: 1
  },
  {
    code: "ussr_strelkovyj_vzvod",
    nation: nations[:ussr],
    name: "Стрелковый взвод",
    weight: 2,
    price: 3,
    firepower: 1,
    hp: 5,
    armor: 0,
    fuel: 0
  },
  {
    code: "ussr_vzvod_ptr",
    nation: nations[:ussr],
    name: "Взвод ПТР",
    weight: 3,
    price: 4,
    firepower: 1,
    hp: 6,
    armor: 2,
    fuel: 0
  }
]

headquarters.each do |attributes|
  card = Card.find_or_initialize_by(code: attributes[:code])

  card.assign_attributes(
    nation: attributes[:nation],
    name: attributes[:name],
    card_type: "headquarters",
    weight: attributes[:weight],
    price: nil
  )

  card.save!

  headquarters_card = Headquarters.find_or_initialize_by(card: card)
  headquarters_card.assign_attributes(
    firepower: attributes[:firepower],
    hp: attributes[:hp],
    fuel: attributes[:fuel]
  )
  headquarters_card.save!
end

techniques.each do |attributes|
  card = Card.find_or_initialize_by(code: attributes[:code])

  card.assign_attributes(
    nation: attributes[:nation],
    name: attributes[:name],
    card_type: "technique",
    weight: attributes[:weight],
    price: attributes[:price]
  )

  card.save!

  technique = Technique.find_or_initialize_by(card: card)
  technique.assign_attributes(
    technique_type: attributes[:technique_type],
    attack_range: attributes[:attack_range],
    movement_count: attributes[:movement_count],
    movement_type: attributes[:movement_type],
    firepower: attributes[:firepower],
    hp: attributes[:hp],
    fuel: attributes[:fuel]
  )
  technique.save!
end

orders.each do |attributes|
  card = Card.find_or_initialize_by(code: attributes[:code])

  card.assign_attributes(
    nation: attributes[:nation],
    name: attributes[:name],
    card_type: "order",
    weight: attributes[:weight],
    price: attributes[:price]
  )

  card.save!
end

platoons.each do |attributes|
  card = Card.find_or_initialize_by(code: attributes[:code])

  card.assign_attributes(
    nation: attributes[:nation],
    name: attributes[:name],
    card_type: "platoon",
    weight: attributes[:weight],
    price: attributes[:price]
  )

  card.save!

  platoon = Platoon.find_or_initialize_by(card: card)
  platoon.assign_attributes(
    firepower: attributes[:firepower],
    hp: attributes[:hp],
    armor: attributes[:armor],
    fuel: attributes[:fuel]
  )
  platoon.save!
end
