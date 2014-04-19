module OCCPGameServer

    class Main

        attr_accessor :gameclock, :networkid, :scenarioname, :INBOX, :eventRunQueue
        attr_accessor :STATE, :db, :scoreKeeper, :interfaces, :ipPools

        def initialize
            @events = {}
            @hosts = Array.new
            
            @teams = Array.new
            @localteams = Array.new
            
            #Run queue for event that have been launched by a ascheduler
            @eventRunQueue = Queue.new
            
            @INBOX = Queue.new
            @db = ''
            @handlers= Array.new
            @gameclock = GameClock.new
            @scoreKeeper = Score.new
            @interfaces = Array.new
            @ipPools = {}
            @nsPool = Array.new
            @STATE = WAIT
        end

        def add_event()
        end

        #Add a team host to the list
        def add_host(new_host)
            @hosts.push(new_host)
        end
        
        def add_team(new_team)
            @teams.push(new_team)
        end
        
        #Store each of the event handlers to be dispatched
        def add_handler(new_handler)
            @handlers.push(new_handler)
        end

        # Lookup a handler by name to get its information
        def get_handler(handle_name)
            return @handlers.find {|handler| handler.name == handle_name }
        end
        
        def get_handlers()
            @handlers
        end

        def get_network(name)
            return @interfaces.find{|netName| netName[:network] == name }
        end

        ##
        # Return a network namespace for the given network segment
        # If the ip address may either be a valid address or pool name 
        #
        def get_netns(networkSegment, ipaddr)

            if NetAddr.validate_ip_address(ipaddr) 

                netns = NetNSRegistry.get_netns(networkSegment, ipaddr)
                
            else
                # Choose a random ip address
                pool = @ipPools[ipaddr]
                if pool.nil? || pool.empty?
                    return nil
                end
                randIP = pool[rand(pool.length)]

                netns = NetNSRegistry.get_registered_netns(networkSegment, ipaddr)
            end

            return netns
        end

        ##
        # Release the name space when not using it
        #
        def release_netns(netnsName)
            NetNSRegistry.release_registered_netns(netnsName)
        end

        def set_state(state)
            
            case state
                when WAIT
                    if @STATE == RUN
                        $log.info 'Instance PAUSE Triggered'.yellow
                        @teams.each { |team|
                            team.INBOX << GMessage.new({:fromid=>'Main Thread',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> WAIT}})
                        }
                        @gameclock.pause
                    end
                when RUN
                    @gameclock.resume
                    @teams.each { |team|
                            team.INBOX << GMessage.new({:fromid=>'Main Thread',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> RUN}})
                            #team.set_state(state)
                    }
                    $log.info 'Instance RESUME Triggered'.yellow
                when STOP
                    #Clean everything up and signal all process to stop
                    @teams.each { |team|
                            team.INBOX << GMessage.new({:fromid=>'Main Thread',:signal=>'COMMAND', :msg=>{:command => 'STATE', :state=> STOP}})
                    }
                    exit_cleanup()

            end
            
            @STATE = state

        end
        def get_state()
            return @STATE
        end
        #Cleanup any residuals and wait for related threads to shutdown nicely
        def exit_cleanup()

            threadRelease = false

            while not threadRelease
                # Poll each thread until there all dead
                if @localteams.empty?
                    threadRelease = true
                end

                @localteams.delete_if{|evThread|
                    not evThread[:thr].alive?
                }

            end

            @scoreKeeper.cleanup

            $log.debug 'Team thread cleanup complete'
            Thread.exit
        end
 
        # Entry point for the post-setup code
        def run ()
            Log4r::NDC.push('Main:')

            #Launch each teams scheduler
            @teams.each { |team|
                if team.teamhost == "localhost" 
                    @localteams << {:teamid=>team.teamid, :thr=> Thread.new { team.run(self) }}
                else
                    #lookup the connection information for this team and dispatch the team
                end

            }
            
            #Poll the @INBOX waiting for tasks
            while message = @INBOX.pop do

                case message.signal
                
                when 'CONSOLE'
                    #Dump Messages to the Screen and into the logfile
                  #  puts message.fromid.to_s.yellow + " " + message.msg.to_s
                    from = message.fromid.to_s
                    $log.info(from + ": " + message.msg.to_s)

                when 'SCORE'
                    #We are receiving a score hash that should be added to the appropriate score group
                    timeT = Time.now.to_i
                    group = message.msg[:scoregroup]
                    value = message.msg[:value]
                    eventuid = message.msg[:eventuid]

                    $db.execute("INSERT INTO score VALUES (?,?,?,?)", [timeT, eventuid, group, value])
                    $log.debug("Score recorded in db.score")

               
                when 'EVENTLOG'
                    #Log that an event was run       
                    tblArray = [Time.now.to_i, 
                        message.msg[:handler], 
                        message.msg[:eventname], 
                        message.msg[:eventuid], 
                        message.msg[:custom], 
                        message.msg[:status] 
                    ]

                    $db.execute("INSERT INTO event VALUES (?,?,?,?,?,?);", tblArray);
                    $log.debug("Event Recorded in db.event")

                when 'COMMAND'

                    command = message.msg
                    
                    case command[:command]
                    when 'STATE'
                        set_state(command[:state])
                    end

                when 'STATUS'
                    @teams.each { |team|
                            team.INBOX << GMessage.new({:fromid=>'Main Thread',:signal=>'STATUS', :msg=>{}})
                    }

                when 'DIE'
                    break
                else
                    break
                end

            end #@INBOX Poll

            #wait for all the teams to finish
            @localteams.each { |team| team[:thr].join }
            #@taskmaster.join

        end #def run



    end #Class
  
end #Module
