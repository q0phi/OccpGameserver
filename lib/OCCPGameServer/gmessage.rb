module OCCPGameServer

    class GMessage

        attr_accessor :fromid, :signal, :msg
        attr_reader :uid

        def initialize(cHash)
            @fromid = cHash[:fromid]
            @signal = cHash[:signal]
            @msg = cHash[:msg]

            @uid = SecureRandom.uuid

        end

    end

end
