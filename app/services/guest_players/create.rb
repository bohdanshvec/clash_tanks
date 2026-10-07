module GuestPlayers
  class Create
    def self.call
      new.call
    end

    def call
      Player.transaction do
        player = Player.create!(
          email: "guest-#{SecureRandom.hex(16)}@guest.local",
          name: "Гость",
          password: SecureRandom.base58(32),
          guest: true,
          last_seen_at: Time.current
        )

        StarterDecks::Create.call(player)

        player
      end
    end
  end
end
