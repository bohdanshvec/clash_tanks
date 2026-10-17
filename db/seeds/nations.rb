[
  { code: "ussr", name: "СРСР" },
  { code: "germany", name: "Німеччина" },
  { code: "usa", name: "США" }
].each do |attributes|
  nation = Nation.find_or_initialize_by(code: attributes[:code])
  nation.assign_attributes(attributes)
  nation.save!
end
