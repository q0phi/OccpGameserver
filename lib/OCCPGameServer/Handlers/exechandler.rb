module OCCPGameServer
class ExecHandler < Handler

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

        new_event  = ExecEvent.new(eh)
       
        # cross-verify event networking
        netHash = appCore.get_network(new_event.network)
        raise ArgumentError, "event network label not defined #{new_event.network}" if netHash.nil? || netHash.empty?

        # check for a valid ip address or pool name
        begin
            NetAddr.validate_ip_addr(event[:ipaddress])
            new_event.ipaddress = event[:ipaddress]
        rescue NetAddr::ValidationError => e
            raise ArgumentError, "event ip addrress or pool name not valid: #{event[:ipaddress]}" if !appCore.ipPools.member?(event[:ipaddress])
            new_event.ipaddress = event[:ipaddress]
        end

        # Add scores to event
        event.find('score-atomic').each{ |score|
            token = {:succeed => true}
            case score.attributes["when"]
            when 'success'
                token = {:succeed => true}
            when 'fail'
                token = {:succeed => false}
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

        Log4r::NDC.push('ExecHandler:')
        
        # setup the execution space
        # IE get a network namespace for this execution for the given IP address
        localiface = app_core.get_network(event.network)[:name]

        netNS = app_core.get_netns(localiface, event.ipaddress) 
        newCom = netNS.comwrap(event.command)
        begin
            # run the provided command
            #puts event.name + event.command.to_s
            success = system(newCom, [:out, :err]=>'/dev/null')
        
        rescue Exception => e
            app_core.release_netns(netNS.nsName)
            msg = "Event failed to run: #{e.message}".red
            $log.warn msg
        end
        
        #Log message that the event ran
        msgHash = {:handler => 'ExecHandler', :eventname => event.name, :eventuid => event.eventuid, :custom => event.command }
        
        if( success === true )

            $log.debug "#{event.name} #{event.command} " + "SUCCESS".green
            app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'SUCCESS'}) })
            
            #Score Database
            event.scores.each {|score|
                if score[:succeed]
                    app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'SCORE', :msg=>score.merge({:eventuid => event.eventuid})})
                end
            }

        elsif( success === nil )
                msg = "Command failed to run: #{event.command}"
                $log.error(msg)

        else
            $log.debug "#{event.name} #{event.command} " + "FAILED".red
            app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'FAILED'}) })
            
            #Score Database
            event.scores.each {|score|
                if !score[:succeed]
                    app_core.INBOX << GMessage.new({:fromid=>'ExecHandler',:signal=>'SCORE', :msg=>score.merge({:eventuid => event.eventuid})})
                end
            }
        end

        Log4r::NDC.pop

    end

end #end class
end #end module
