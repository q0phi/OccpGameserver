module OCCPGameServer
class NagiosPluginHandler < Handler

    @@nagiosStatus = {
        0 => 'OK',
        1 => 'WARNING',
        2 => 'CRITICAL',
        3 => 'UNKNOWN',
    }

   
    def initialize(ev_handler_hash)
        super

    end

    # Parse the exec event xml code into a execevent object
    def parse_event(event, appCore)
        eh = super

        new_event  = NagiosPluginEvent.new(eh)

         # Check if the :ipaddress field is included
        if eh.include?(:ipaddress)
            # Check if the pool specified exists and has a valid interface
            if !appCore.ipPools.member?(eh[:ipaddress]) 
                raise ArgumentError, "event ip address pool name not valid: #{eh[:ipaddress]}"
            elsif appCore.ipPools[eh[:ipaddress]][:ifname] == nil
                $log.warn "Event #{eh[:name]} uses ip address pool with no interface associated".light_yellow
            end
            # Assign the pool name even if their is no interface ready
            new_event.ipaddress = eh[:ipaddress]
        else
            $log.debug "Event #{eh[:name]} does not define an ip address pool; local exec only"
        end

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
        
        if event.ipaddress != nil
            ipPool = app_core.get_ip_pool(event.ipaddress)
            if ipPool[:ifname] != nil 
                ipAddr = ipPool[:addresses][rand(ipPool[:addresses].length)]
                netInfo = {:iface => ipPool[:ifname], :ipaddr => ipAddr , :cidr => ipPool[:cidr], :gateway => ipPool[:gateway] }
                begin
                    netNS = app_core.get_netns(netInfo) 
                rescue ArgumentError => e
                    msg = "unable to create network namespace for event #{e}; aborting execution"
                    print msg.red
                    $log.error msg.red
                    return
                end
            else
                $log.debug "Event #{event.name} ip address pool does not define an interface; local exec only"
            end
        end

        gameTimeStart = $appCore.gameclock.gametime

        #TODO Optimize command specialization to arrays
        begin
             # Change to the correct network namespace
            fd = IO.sysopen('/var/run/netns/' + netNS.nsName, 'r')
            success = $setns.call(fd, 0)
            
            raise ArgumentError, 'could not change to correct namespace' if success != 0

            # run the provided command
            success = system(event.command, [:out, :err]=>'/dev/null')
        
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
        elsif( [1,2,3].include?(returnValue) ) 
            $log.debug "#{event.name} #{event.eventuid.light_magenta} " + @@nagiosStatus[returnValue].light_red
            app_core.INBOX << GMessage.new({:fromid=>'NagiosPluginHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'FAILED'}) })
        else
            $log.error "Nagios plugin horrific failure".light_red
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
