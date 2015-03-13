module OCCPGameServer
class NagiosPluginHandler < Handler

    @@nagiosStatus = {
        0 => 'OK',
        1 => 'WARNING',
        2 => 'CRITICAL',
        3 => 'UNKNOWN',
    }

    @@ipAddress = Struct.new(:ipaddress) do
        def get_address
            if ipaddress == 'random'
                ip = ''
            else
                ip = ipaddress
            end
            return ip
        end
    end

    def initialize(ev_handler_hash)
        super

        @interface = ev_handler_hash[:interface]

    end

    # Parse the exec event xml code into a execevent object
    def parse_event(event, appCore)
        require 'securerandom'

        eh = event.attributes.to_h.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
        
        eh.merge!({:eventuid => SecureRandom.uuid})

        new_event  = NagiosPluginEvent.new(eh)
       
        # cross-verify event networking
        #netHash = appCore.get_network(new_event.network)
        #raise ArgumentError, "event network label not defined #{new_event.network}" if netHash.nil? || netHash.empty?

        # check for a valid ip address or pool name
        #begin
        #    NetAddr.validate_ip_addr(event[:ipaddress])
        #    new_event.ipaddress = event[:ipaddress]
        #rescue NetAddr::ValidationError => e
            raise ArgumentError, "event ip addrress or pool name not valid: #{event[:ipaddress]}" if !appCore.ipPools.member?(event[:ipaddress])
            new_event.ipaddress = event[:ipaddress]
        #end

        # Add scores to event
        event.find('score-atomic').each{ |score|
            token = { }
            case score.attributes["when"]
            when 'OK'
                token = {:status => 0}
            when 'WARNING'
                token = {:status => 1}
            when 'CRITICAL'
                token = {:status => 2}
            when 'UNKNOWN'
                token = {:status => 3}
            end
            new_event.scores << token.merge( {:scoregroup => score.attributes["score-group"],
                                                :value => score.attributes["points"].to_f } )
        }

        #Support arbitrary parameter storage
        event.find('parameters/param').each { |param|
            new_event.attributes << { param.attributes["name"] => param.attributes["value"] }
        }
        
        return new_event
    end

    def run(event, app_core)

        Log4r::NDC.push('NagiosPluginHandler:')
        
        # setup the execution space
        # IE get a network namespace for this execution for the given IP address
        ipPool = app_core.get_ip_pool(event.ipaddress)
        if ipPool.nil? || ipPool.empty?
            raise ArgumentError, "event ip address pool not defined"
        end
        
        netLink = app_core.get_network(ipPool[:network])[:name]
        if netLink.nil? || netLink.empty?
            raise ArgumentError, "event ip address pool interface not defined"
        end
       
        ipAddr = ipPool[:addresses][rand(ipPool[:addresses].length)]
        netInfo = {:iface => netLink, :ipaddr => ipAddr , :cidr => ipPool[:cidr], :gateway => ipPool[:gateway] }
        #print "net info #{netInfo}"
        begin
            netNS = app_core.get_netns(netInfo) 
        rescue ArgumentError => e
            msg = "unable to create network namespace for event #{e}"
            print msg.red
            $log.error msg.red
        end

        # Prep the events command
        newCom = netNS.comwrap(event.command)

        gameTimeStart = $appCore.gameclock.gametime

        #TODO Optimize command specialization to arrays
        begin
            # run the provided command
            #puts event.name + event.command.to_s
            success = system(newCom, [:out, :err]=>'/dev/null')
        
        rescue Exception => e
            app_core.release_netns(netNS.nsName)
            msg = "Event failed to run: #{e.message}".red
            $log.warn msg
        end

        returnValue = $?.exitstatus
        
        gameTimeEnd = $appCore.gameclock.gametime
        app_core.release_netns(netNS.nsName)
        
        #Log message that the event ran
        msgHash = {:handler => 'NagiosPluginHandler', :eventname => event.name, :eventuid => event.eventuid, :custom => event.command,
                    :starttime => gameTimeStart, :endtime => gameTimeEnd }
        
        $log.debug "#{event.eventuid.light_magenta} returned #{returnValue} after executing #{event.command}"
        
        if( success === nil )
                msg = "Command failed to run: #{event.command}"
                $log.error(msg)
                Log4r::NDC.pop
                return nil
        elsif( returnValue === 0 ) #OK

            $log.info "#{event.name} #{event.eventuid.light_magenta} " + @@nagiosStatus[returnValue].green
            app_core.INBOX << GMessage.new({:fromid=>'NagiosPluginHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'OK'}) })
        else 
            $log.debug "#{event.name} #{event.eventuid.light_magenta} " + @@nagiosStatus[returnValue].light_red
            app_core.INBOX << GMessage.new({:fromid=>'NagiosPluginHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'FAILED'}) })
            
        end

        # Record Scores to Database
        event.scores.each {|score|
            if score[:status] === returnValue 
                app_core.INBOX << GMessage.new({:fromid=>'NagiosPluginHandler',:signal=>'SCORE', :msg=>score.merge({:eventuid => event.eventuid})})
            end
        }

        Log4r::NDC.pop

    end

end #end class
end #end module
