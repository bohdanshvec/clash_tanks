[
  { code: "ussr", name: "СССР" },
  { code: "germany", name: "Германия" },
  { code: "usa", name: "США" }
].each do |attributes|
  nation = Nation.find_or_initialize_by(code: attributes[:code])
  nation.assign_attributes(attributes)
  nation.save!
end
