module OCCPGameServer
    class Event

        attr_accessor :eventid, :name, :eventhandler
        attr_accessor :eventuid, :starttime, :endtime, :drift
        attr_accessor :scores, :attributes, :rollover, :frequency
        attr_accessor :network, :poolname

        def initialize(eh)
            @scores = Array.new
            @attributes = Array.new

            @frequency = 0 

            @eventhandler = eh[:handler]
            @eventuid = eh[:eventuid]
            
            raise ArgumentError, "event requires a name" if eh[:name].nil?
            @name = eh[:name]
            
            raise ArgumentError, "no start time defined" if eh[:starttime].nil?
            @starttime = eh[:starttime].to_i
            
            raise ArgumentError, "no end time defined" if eh[:endtime].nil?
            @endtime = eh[:endtime].to_i
            
            raise ArgumentError, "no frequency defined --use 0 for a single event--" if eh[:frequency].nil?
            @frequency = eh[:frequency].to_f

            raise ArgumentError, "no drift defined --use 0 for no drift--" if eh[:drift].nil?
            @drift = eh[:drift].to_f
            
            raise ArgumentError, "no network name defined" if eh[:network].nil?
            @network = eh[:network].to_s

        end

     #   def update_period()
     #       
     #       if @freqscale === 'sec' 
     #           @period = 1/@frequency
     #       elsif @freqscale === 'min'
     #           @period = 60/@frequency
     #       elsif @freqscale === 'hour'
     #           @period = 3600/@frequency
     #       end
     #   end

     #   def frequency=(freq)
     #       @frequency=freq
     #       update_period()
     #   end
     #   def freqscale=(scale)
     #       @freqscale=scale
     #       update_period()
     #   end

end
end
