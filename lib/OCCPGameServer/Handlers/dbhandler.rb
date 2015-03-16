module OCCPGameServer
class DbHandler < Handler

    def initialize(ev_handler_hash)
        super

    end

    # Parse the exec event xml code into a execevent object
    def parse_event(event, appCore)
        # Perform basic hash conversion
        eh = super
        
        new_event  = DbEvent.new(eh)
        
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
            raise ArgumentError, "event ip address pool name not defined"
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

        #Specific entries in the command
        targetServer = event.find('server').first 
        new_event.serverip = targetServer["ipaddress"]
        new_event.serverport = targetServer["port"]
        new_event.dbname = targetServer["dbname"]
        new_event.dbuser = targetServer["username"]
        new_event.dbpass = targetServer["password"]

        event.find('action').each{ |action|
            if action["file"] != nil
                new_event.actions << { file: action["file"] }
            elsif action["sql"] != nil
                new_event.actions << { sql: action["sql"] }
            else
                $log.error "invalid acion statement in #{event.name}".red
                raise ArgumentError, "invalid action statement for sql"
            end
        }
        
        return new_event
    end

    def run(event, app_core)

        if LOG_SHORT_UIDS
            lgeventuid = event.eventuid.split('-').last
        else 
            lgeventuid = event.eventuid
        end
        Log4r::NDC.push("DbHandler-#{lgeventuid}:")
        
        # setup the execution space
        # IE get a network namespace for this execution for the given IP address
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
                $log.warn "Unable to run #{event.name} with invalid pool definition; aborting execution".light_yellow
                return
            end
        end

        successActions = Array.new
        gameTimeStart = $appCore.gameclock.gametime

        begin
            # Change to the correct network namespace
            fd = IO.sysopen('/var/run/netns/' + netNS.nsName, 'r')
            success = $setns.call(fd, 0)
            
            raise ArgumentError, 'could not change to correct namespace' if success != 0
            success = nil

            $log.debug "Beginning DB session to remote server"

            client = Mysql2::Client.new( 
                        :host => event.serverip,
                        :port => event.serverport,
                        :username => event.dbuser,
                        :password => event.dbpass,
                        :database => event.dbname,
                        :flags => Mysql2::Client::MULTI_STATEMENTS )

            event.actions.each{ |action|
                # Get the SQL statements from file or directly
                if file = action[:file] 
                    text = File.read(file)
                elsif file = action[:sql]
                    text = action[:sql]
                end
               
                # run the query ignore results
                client.query(text)
                while client.next_result
                end
                successActions << action
            }
           
            client.close
            $log.debug "Closed DB session to remote server" 
            success = true

        rescue Mysql2::Error => e
            # User failed to login
            success = false
            $log.warn "Event #{event.name} #{lgeventuid} failed to run: #{e.message}".red

        rescue Exception => e
            msg = "Unknown Exception: Event #{event.name} #{lgeventuid} failed to run: #{e.message}".red
            $log.warn msg
            success = false
        end
        
        gameTimeEnd = $appCore.gameclock.gametime
        app_core.release_netns(netNS.nsName)
        
        #Log message that the event ran
        msgHash = {:handler => 'DbHandler', :eventname => event.name, :eventuid => event.eventuid, :custom => event.actions.to_s,
                    :starttime => gameTimeStart, :endtime => gameTimeEnd }
        
        $log.debug "#{lgeventuid.light_magenta} executed #{event.actions.to_s}"
        
        if( success === true )

            
            $log.info "#{event.name} #{lgeventuid.light_magenta} " + "SUCCESS".green
            
            app_core.INBOX << GMessage.new({:fromid=>'DbHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'SUCCESS'}) })
            
            #Score Database
            event.scores.each {|score|
                if score[:succeed]
                    app_core.INBOX << GMessage.new({:fromid=>'DbHandler',:signal=>'SCORE', :msg=>score.merge({:eventuid => event.eventuid})})
                end
            }

        elsif( success === nil )
                msg = "Command failed to run: #{event.name} no points computed : ERROR UNREACHABLE"
                $log.error(msg)

        else
            $log.info "#{event.name} #{lgeventuid.light_magenta} " + "FAILED".light_red
            successActions.each{ |file, error| $log.debug "#{event.name} #{lgeventuid.light_magenta} " + "PARTIAL SUCCESS ".green + successActions.to_s }
            
            app_core.INBOX << GMessage.new({:fromid=>'DbHandler',:signal=>'EVENTLOG', :msg=>msgHash.merge({:status => 'FAILED'}) })
            
            #Score Database
            event.scores.each {|score|
                if !score[:succeed]
                    app_core.INBOX << GMessage.new({:fromid=>'DbHandler',:signal=>'SCORE', :msg=>score.merge({:eventuid => event.eventuid})})
                end
            }
        end

        Log4r::NDC.pop

    end

end #end class
end #end module
