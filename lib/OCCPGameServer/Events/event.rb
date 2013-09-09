class Event

        attr_accessor :eventid, :name, :eventhandler
        attr_accessor :eventuid, :starttime, :endtime, :frequency, :drift
        attr_accessor :scores, :attributes

        def initialize()
            @scores = Array.new
            @attributes = Array.new
        end

end
