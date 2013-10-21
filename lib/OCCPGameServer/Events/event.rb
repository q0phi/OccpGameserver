class Event

        attr_accessor :eventid, :name, :eventhandler
        attr_accessor :eventuid, :starttime, :endtime, :frequency, :freqscale, :drift
        attr_accessor :scores, :attributes, :rollover

        def initialize()
            @scores = Array.new
            @attributes = Array.new
        end

end
