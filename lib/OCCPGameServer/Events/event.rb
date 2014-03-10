class Event

        attr_accessor :eventid, :name, :eventhandler
        attr_accessor :eventuid, :starttime, :endtime, :drift
        attr_accessor :scores, :attributes, :rollover

        attr_reader  :period, :frequency, :freqscale 

        def initialize()
            @scores = Array.new
            @attributes = Array.new

            @frequency = 1
            @freqscale = 'none'
        end

        def update_period()
            
            if @freqscale === 'sec' 
                @period = 1/@frequency
            elsif @freqscale === 'min'
                @period = 60/@frequency
            elsif @freqscale === 'hour'
                @period = 3600/@frequency
            end
        end

        def frequency=(freq)
            @frequency=freq
            update_period()
        end
        def freqscale=(scale)
            @freqscale=scale
            update_period()
        end

end
