module OCCPGameServer

    class GMessage

        attr_accessor :fromid, :signal, :msg

        def initialize(cHash)
            @fromid = cHash[:fromid]
            @signal = cHash[:signal]
            @msg = cHash[:msg]

        end

    end

end
