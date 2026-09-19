abilities = {
  damage_technique: Ability.find_by!(code: "damage_technique"),
  draw_cards: Ability.find_by!(code: "draw_cards")
}

card_abilities = [
  {
    card_code: "germany_tocnyj_vystrel",
    ability: abilities[:damage_technique],
    parameters: { damage: 4 }
  },
  {
    card_code: "germany_radioperekhvat",
    ability: abilities[:draw_cards],
    parameters: { count: 2 }
  },
  {
    card_code: "usa_lend_liz",
    ability: abilities[:draw_cards],
    parameters: { count: 2 }
  },
  {
    card_code: "usa_ognevoj_nalyot",
    ability: abilities[:damage_technique],
    parameters: { damage: 2 }
  },
  {
    card_code: "ussr_zalp_katyushi",
    ability: abilities[:damage_technique],
    parameters: { damage: 3 }
  },
  {
    card_code: "ussr_popolnenie",
    ability: abilities[:draw_cards],
    parameters: { count: 1 }
  }
]

card_abilities.each do |attributes|
  card = Card.find_by!(code: attributes[:card_code])

  card_ability = CardAbility.find_or_initialize_by(
    card: card,
    ability: attributes[:ability]
  )

  card_ability.parameters = attributes[:parameters]
  card_ability.save!
end
