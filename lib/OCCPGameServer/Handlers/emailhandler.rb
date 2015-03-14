module OCCPGameServer
class EmailHandler < Handler
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

        new_event  = EmailEvent.new(eh)
       
        raise ArgumentError, "event ip addrress or pool name not valid: #{event[:ipaddress]}" if !appCore.ipPools.member?(event[:ipaddress])
        new_event.ipaddress = event[:ipaddress]

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

        event.find('server').each { |server|
            new_event.serverip = server.attributes["ipaddress"]
            new_event.serverport = server.attributes["port"]
        }
        event.find('message-header').each { |header|
            new_event.fqdn = header.attributes["fqdn"]
            new_event.to = header.attributes["to"]
            new_event.from = header.attributes["from"]
            new_event.subject = header.attributes["subject"]
        }

        new_event.body = event.find('body').first.content
        
        return new_event
    end

    def run(event, app_core)

        Log4r::NDC.push('EmailHandler:')
        
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

        # Re-generate the message, really for a current timestamp and unique Message-ID field
        event.command = event.get_command
        
        # Prep the events command
        newCom = netNS.comwrap(event.command)

        gameTimeStart = $appCore.gameclock.gametime

        begin
            # run the provided command
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
        msgHash = {:handler => 'EmailHandler', :eventname => event.name, :eventuid => event.eventuid, :custom => event.command,
                    :starttime => gameTimeStart, :endtime => gameTimeEnd }
        
        $log.debug "#{event.eventuid.light_magenta} returned #{returnValue} after executing #{event.command}"

        if( success === nil )
                msg = "Command failed to run: #{event.command}"
                $log.error(msg)
                Log4r::NDC.pop
                return nil
        elsif( returnValue === 0 ) #OK

            $log.info "#{event.name} #{event.eventuid.light_magenta} " + @@nagiosStatus[returnValue].green
            app_core.INBOX << GMessage.new({:fromid=>'EmailHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'OK'}) })
        elsif( [1,2,3].include?(returnValue) )
            $log.debug "#{event.name} #{event.eventuid.light_magenta} " + @@nagiosStatus[returnValue].light_red
            app_core.INBOX << GMessage.new({:fromid=>'EmailHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'FAILED'}) })
        else            
            $log.error "#{event.eventuid.light_magenta} returned #{returnValue} after executing #{event.command}".light_red
        end

        # Record Scores to Database
        event.scores.each {|score|
            if score[:status] === returnValue 
                app_core.INBOX << GMessage.new({:fromid=>'EmailHandler',:signal=>'SCORE', :msg=>score.merge({:eventuid => event.eventuid})})
            end
        }

        Log4r::NDC.pop

    end

end #end class
end #end module
